defmodule EverydayDash.Dashboard.Sources.StravaTest do
  use ExUnit.Case, async: false

  import Plug.Conn

  alias EverydayDash.Dashboard.Sources.Strava
  alias EverydayDash.TestSupport.StravaCacheStoreStub

  setup {Req.Test, :verify_on_exit!}

  setup do
    original_config = Application.get_env(:everyday_dash, EverydayDash.Dashboard)
    cache_agent = start_supervised!({Agent, fn -> %{record: nil, saves: []} end})

    token_store_path =
      Path.join(System.tmp_dir!(), "strava_tokens_#{System.unique_integer([:positive])}.json")

    on_exit(fn ->
      Application.put_env(:everyday_dash, EverydayDash.Dashboard, original_config)
      File.rm(token_store_path)
    end)

    {:ok, cache_agent: cache_agent, token_store_path: token_store_path}
  end

  test "returns a fresh persisted cache without calling Strava", %{
    cache_agent: cache_agent,
    token_store_path: token_store_path
  } do
    stub_name = {:strava_test, System.unique_integer([:positive])}

    Req.Test.stub(stub_name, fn _conn ->
      flunk("unexpected Strava request")
    end)

    StravaCacheStoreStub.put(cache_agent, cache_record(%{counts: %{"2026-03-09" => 2}}))

    put_dashboard_config(cache_agent, token_store_path, stub_name, %{
      client_id: nil,
      client_secret: nil
    })

    assert {:ok, payload} = Strava.fetch(~D[2026-03-09], 30, 7)
    assert payload.status == :ok
    assert payload.status_message == "Recently synced from Strava."
    assert payload.counts == %{~D[2026-03-09] => 2}
    assert StravaCacheStoreStub.saves(cache_agent) == []
  end

  test "refetches expired cache, persists the new counts, and returns ok", %{
    cache_agent: cache_agent,
    token_store_path: token_store_path
  } do
    stub_name = {:strava_test, System.unique_integer([:positive])}

    write_token_file(token_store_path)

    StravaCacheStoreStub.put(
      cache_agent,
      cache_record(%{
        counts: %{"2026-03-08" => 4},
        fetched_at: DateTime.add(DateTime.utc_now(), -4_000, :second)
      })
    )

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

    put_dashboard_config(cache_agent, token_store_path, stub_name)

    assert {:ok, payload} = Strava.fetch(~D[2026-03-09], 30, 7)
    assert payload.status == :ok
    assert payload.status_message == "Live data"
    assert payload.counts == %{~D[2026-03-08] => 1, ~D[2026-03-09] => 1}

    assert [
             %{
               counts: %{"2026-03-08" => 1, "2026-03-09" => 1},
               graph_days: 30,
               window_days: 7,
               backoff_until: nil
             } = saved
           ] = StravaCacheStoreStub.saves(cache_agent)

    assert saved.rate_limit_headers == %{"limit" => "100,1000", "usage" => "10,200"}
    assert %DateTime{} = saved.fetched_at
  end

  test "returns stale cached data and stores backoff when Strava rate limits", %{
    cache_agent: cache_agent,
    token_store_path: token_store_path
  } do
    stub_name = {:strava_test, System.unique_integer([:positive])}

    write_token_file(token_store_path)

    cached_record =
      cache_record(%{
        counts: %{"2026-03-08" => 3},
        fetched_at: DateTime.add(DateTime.utc_now(), -4_000, :second)
      })

    StravaCacheStoreStub.put(cache_agent, cached_record)

    Req.Test.expect(stub_name, fn conn ->
      assert conn.request_path == "/api/v3/athlete/activities"
      rate_limited_response(conn, "100,1000", "100,1000")
    end)

    put_dashboard_config(cache_agent, token_store_path, stub_name)

    assert {:ok, payload} = Strava.fetch(~D[2026-03-09], 30, 7)
    assert payload.status == :stale
    assert payload.status_message == "Using cached Strava data while the rate limit resets."
    assert payload.counts == %{~D[2026-03-08] => 3}
    refute payload.status_message =~ "\"errors\""
    refute payload.status_message =~ "Rate Limit Exceeded"

    assert [%{backoff_until: %DateTime{} = backoff_until} = saved] =
             StravaCacheStoreStub.saves(cache_agent)

    assert DateTime.compare(backoff_until, DateTime.utc_now()) == :gt
    assert saved.rate_limit_headers == %{"limit" => "100,1000", "usage" => "100,1000"}
    assert saved.counts == cached_record.counts
  end

  test "returns a friendly error when Strava rate limits and no cache exists", %{
    cache_agent: cache_agent,
    token_store_path: token_store_path
  } do
    stub_name = {:strava_test, System.unique_integer([:positive])}

    write_token_file(token_store_path)
    StravaCacheStoreStub.clear(cache_agent)

    Req.Test.expect(stub_name, fn conn ->
      assert conn.request_path == "/api/v3/athlete/activities"
      rate_limited_response(conn, "100,1000", "100,1000")
    end)

    put_dashboard_config(cache_agent, token_store_path, stub_name)

    assert {:error, :request_failed, message} = Strava.fetch(~D[2026-03-09], 30, 7)

    assert message ==
             "Strava is rate limited right now. The dashboard will retry after the current window resets."

    refute message =~ "\"errors\""
    refute message =~ "Rate Limit Exceeded"
  end

  test "ignores cache records built for a different graph window", %{
    cache_agent: cache_agent,
    token_store_path: token_store_path
  } do
    stub_name = {:strava_test, System.unique_integer([:positive])}

    write_token_file(token_store_path)

    StravaCacheStoreStub.put(
      cache_agent,
      cache_record(%{
        counts: %{"2026-03-09" => 9},
        graph_days: 14
      })
    )

    Req.Test.expect(stub_name, fn conn ->
      assert conn.request_path == "/api/v3/athlete/activities"

      conn
      |> put_resp_header("x-readratelimit-limit", "100,1000")
      |> put_resp_header("x-readratelimit-usage", "12,220")
      |> Req.Test.json([
        %{"start_date_local" => "2026-03-09T08:00:00Z"}
      ])
    end)

    put_dashboard_config(cache_agent, token_store_path, stub_name)

    assert {:ok, payload} = Strava.fetch(~D[2026-03-09], 30, 7)
    assert payload.counts == %{~D[2026-03-09] => 1}

    assert [%{graph_days: 30, window_days: 7}] = StravaCacheStoreStub.saves(cache_agent)
  end

  defp put_dashboard_config(cache_agent, token_store_path, stub_name, overrides \\ %{}) do
    strava_config =
      %{
        cache_agent: cache_agent,
        cache_store: StravaCacheStoreStub,
        cache_ttl_ms: 900_000,
        client_id: "strava-client-id",
        client_secret: "strava-client-secret",
        refresh_token: "strava-refresh-token",
        request_options: [plug: {Req.Test, stub_name}, retry: false],
        token_store_backend: :file,
        token_store_path: token_store_path
      }
      |> Map.merge(overrides)

    Application.put_env(
      :everyday_dash,
      EverydayDash.Dashboard,
      refresh_interval_ms: 60_000,
      graph_days: 30,
      average_window_days: 7,
      github: %{username: nil, token: nil},
      habitify: %{api_key: nil},
      strava: strava_config
    )
  end

  defp write_token_file(token_store_path) do
    File.write!(
      token_store_path,
      Jason.encode!(%{
        "access_token" => "cached-access-token",
        "expires_at" => System.system_time(:second) + 3_600,
        "refresh_token" => "strava-refresh-token"
      })
    )
  end

  defp cache_record(overrides) do
    defaults = %{
      service: "strava_activities",
      counts: %{"2026-03-08" => 1},
      graph_days: 30,
      window_days: 7,
      fetched_at: DateTime.utc_now(),
      backoff_until: nil,
      rate_limit_headers: %{}
    }

    Map.merge(defaults, overrides)
  end

  defp rate_limited_response(conn, usage, limit) do
    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("x-readratelimit-limit", limit)
    |> put_resp_header("x-readratelimit-usage", usage)
    |> send_resp(429, Jason.encode!(%{"errors" => [%{"message" => "Rate Limit Exceeded"}]}))
  end
end
