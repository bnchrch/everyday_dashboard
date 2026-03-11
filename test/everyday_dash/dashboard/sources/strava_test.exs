defmodule EverydayDash.Dashboard.Sources.StravaTest do
  use ExUnit.Case, async: false

  import Plug.Conn

  alias EverydayDash.Accounts.UserIntegration
  alias EverydayDash.Credentials
  alias EverydayDash.Dashboard.Sources.Strava

  setup {Req.Test, :verify_on_exit!}

  setup do
    original_config = Application.get_env(:everyday_dash, EverydayDash.Dashboard)

    on_exit(fn ->
      Application.put_env(:everyday_dash, EverydayDash.Dashboard, original_config)
    end)

    :ok
  end

  test "returns a fresh persisted cache without calling Strava" do
    stub_name = {:strava_test, System.unique_integer([:positive])}

    Req.Test.stub(stub_name, fn _conn ->
      flunk("unexpected Strava request")
    end)

    put_dashboard_config(stub_name)

    integration =
      integration_fixture(%{
        "counts" => %{"2026-03-09" => 2},
        "graph_days" => 30,
        "window_days" => 7,
        "fetched_at" => DateTime.to_iso8601(DateTime.utc_now()),
        "backoff_until" => nil,
        "rate_limit_headers" => %{}
      })

    assert {:ok, payload, attrs} = Strava.fetch(~D[2026-03-09], 30, 7, integration)
    assert payload.status == :ok
    assert payload.status_message == "Recently synced from Strava."
    assert payload.counts == %{~D[2026-03-09] => 2}
    assert attrs == %{}
  end

  test "refetches expired cache and returns cache attrs" do
    stub_name = {:strava_test, System.unique_integer([:positive])}

    Req.Test.expect(stub_name, fn conn ->
      assert conn.request_path == "/api/v3/athlete/activities"

      conn
      |> put_resp_header("x-readratelimit-limit", "100,1000")
      |> put_resp_header("x-readratelimit-usage", "10,200")
      |> Req.Test.json([
        %{"start_date_local" => "2026-03-08T08:00:00Z"},
        %{"start_date_local" => "2026-03-09T08:00:00Z"}
      ])
    end)

    put_dashboard_config(stub_name)

    integration =
      integration_fixture(%{
        "counts" => %{"2026-03-08" => 4},
        "graph_days" => 30,
        "window_days" => 7,
        "fetched_at" => DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), -4_000, :second)),
        "backoff_until" => nil,
        "rate_limit_headers" => %{}
      })

    assert {:ok, payload, attrs} = Strava.fetch(~D[2026-03-09], 30, 7, integration)
    assert payload.status == :ok
    assert payload.status_message == "Live data"
    assert payload.counts == %{~D[2026-03-08] => 1, ~D[2026-03-09] => 1}
    assert attrs.cache_payload["counts"] == %{"2026-03-08" => 1, "2026-03-09" => 1}
    assert attrs.cache_payload["graph_days"] == 30
    assert attrs.cache_payload["window_days"] == 7
    assert attrs.rate_limit_headers == %{"limit" => "100,1000", "usage" => "10,200"}
    assert attrs.backoff_until == nil
  end

  test "returns stale cached data and stores backoff when Strava rate limits" do
    stub_name = {:strava_test, System.unique_integer([:positive])}

    Req.Test.expect(stub_name, fn conn ->
      assert conn.request_path == "/api/v3/athlete/activities"
      rate_limited_response(conn, "100,1000", "100,1000")
    end)

    put_dashboard_config(stub_name)

    integration =
      integration_fixture(%{
        "counts" => %{"2026-03-08" => 3},
        "graph_days" => 30,
        "window_days" => 7,
        "fetched_at" => DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), -4_000, :second)),
        "backoff_until" => nil,
        "rate_limit_headers" => %{}
      })

    assert {:ok, payload, attrs} = Strava.fetch(~D[2026-03-09], 30, 7, integration)
    assert payload.status == :stale
    assert payload.status_message == "Using cached Strava data while the rate limit resets."
    assert payload.counts == %{~D[2026-03-08] => 3}
    assert %DateTime{} = attrs.backoff_until
    assert attrs.rate_limit_headers == %{"limit" => "100,1000", "usage" => "100,1000"}
    assert attrs.cache_payload["counts"] == %{"2026-03-08" => 3}
  end

  test "returns a friendly error when Strava rate limits and no cache exists" do
    stub_name = {:strava_test, System.unique_integer([:positive])}

    Req.Test.expect(stub_name, fn conn ->
      assert conn.request_path == "/api/v3/athlete/activities"
      rate_limited_response(conn, "100,1000", "100,1000")
    end)

    put_dashboard_config(stub_name)

    integration = integration_fixture(%{})

    assert {:error, :request_failed, message, _attrs} =
             Strava.fetch(~D[2026-03-09], 30, 7, integration)

    assert message ==
             "Strava is rate limited right now. The dashboard will retry after the current window resets."
  end

  test "ignores cache records built for a different graph window" do
    stub_name = {:strava_test, System.unique_integer([:positive])}

    Req.Test.expect(stub_name, fn conn ->
      assert conn.request_path == "/api/v3/athlete/activities"

      conn
      |> put_resp_header("x-readratelimit-limit", "100,1000")
      |> put_resp_header("x-readratelimit-usage", "12,220")
      |> Req.Test.json([
        %{"start_date_local" => "2026-03-09T08:00:00Z"}
      ])
    end)

    put_dashboard_config(stub_name)

    integration =
      integration_fixture(%{
        "counts" => %{"2026-03-09" => 9},
        "graph_days" => 14,
        "window_days" => 7,
        "fetched_at" => DateTime.to_iso8601(DateTime.utc_now()),
        "backoff_until" => nil,
        "rate_limit_headers" => %{}
      })

    assert {:ok, payload, attrs} = Strava.fetch(~D[2026-03-09], 30, 7, integration)
    assert payload.counts == %{~D[2026-03-09] => 1}
    assert attrs.cache_payload["graph_days"] == 30
    assert attrs.cache_payload["window_days"] == 7
  end

  defp put_dashboard_config(stub_name) do
    Application.put_env(
      :everyday_dash,
      EverydayDash.Dashboard,
      refresh_ttl_ms: 900_000,
      graph_days: 30,
      average_window_days: 7,
      github: %{},
      habitify: %{base_url: "https://api.habitify.me"},
      strava: %{
        cache_ttl_ms: 900_000,
        client_id: "strava-client-id",
        client_secret: "strava-client-secret",
        request_options: [plug: {Req.Test, stub_name}, retry: false],
        authorize_url: "https://www.strava.com/oauth/authorize",
        token_url: "https://www.strava.com/oauth/token",
        activities_url: "https://www.strava.com/api/v3/athlete/activities"
      }
    )
  end

  defp integration_fixture(cache_payload) do
    {:ok, ciphertext} =
      Credentials.encrypt(%{
        "access_token" => "cached-access-token",
        "refresh_token" => "strava-refresh-token",
        "expires_at" => System.system_time(:second) + 3_600
      })

    %UserIntegration{
      provider: :strava,
      status: :connected,
      credential_ciphertext: ciphertext,
      cache_payload: cache_payload
    }
  end

  defp rate_limited_response(conn, usage, limit) do
    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("x-readratelimit-limit", limit)
    |> put_resp_header("x-readratelimit-usage", usage)
    |> send_resp(429, Jason.encode!(%{"errors" => [%{"message" => "Rate Limit Exceeded"}]}))
  end
end
