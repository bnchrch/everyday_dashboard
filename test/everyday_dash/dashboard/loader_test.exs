defmodule EverydayDash.Dashboard.LoaderTest do
  use ExUnit.Case, async: false

  import Plug.Conn

  alias EverydayDash.Accounts.User
  alias EverydayDash.Accounts.UserIntegration
  alias EverydayDash.Credentials
  alias EverydayDash.Dashboard.Loader

  setup {Req.Test, :verify_on_exit!}

  setup do
    original_config = Application.get_env(:everyday_dash, EverydayDash.Dashboard)

    on_exit(fn ->
      Application.put_env(:everyday_dash, EverydayDash.Dashboard, original_config)
    end)

    :ok
  end

  test "preserves a source-provided stale status for Strava when a persisted backoff is active" do
    today = EverydayDash.Dashboard.today()

    Application.put_env(:everyday_dash, EverydayDash.Dashboard, dashboard_config())

    integration = %UserIntegration{
      provider: :strava,
      status: :connected,
      cache_payload: %{
        "counts" => %{Date.to_iso8601(today) => 2},
        "graph_days" => 30,
        "window_days" => 7,
        "fetched_at" => DateTime.to_iso8601(DateTime.utc_now()),
        "backoff_until" => DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), 900, :second)),
        "rate_limit_headers" => %{"limit" => "100,1000", "usage" => "100,1000"}
      }
    }

    assert {:ok, snapshot, [{:strava, attrs}]} = Loader.fetch(%User{}, [integration])
    strava_metric = Enum.find(snapshot.metrics, &(&1.id == :strava_activities))

    assert strava_metric.status == :stale
    assert strava_metric.status_message == "Using cached Strava data while the rate limit resets."
    assert strava_metric.today_count == 2
    assert attrs.status == :connected
  end

  test "keeps cached habitify cards as stale when the API is unavailable" do
    stub_name = {:loader_habitify, System.unique_integer([:positive])}

    Req.Test.stub(stub_name, fn conn ->
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(500, Jason.encode!(%{"status" => false, "message" => "unavailable"}))
    end)

    Application.put_env(
      :everyday_dash,
      EverydayDash.Dashboard,
      dashboard_config(
        habitify: %{
          base_url: "https://habitify.test",
          request_options: [plug: {Req.Test, stub_name}, retry: false]
        }
      )
    )

    {:ok, ciphertext} = Credentials.encrypt(%{"api_key" => "habitify-key"})

    integration = %UserIntegration{
      provider: :habitify,
      status: :connected,
      credential_ciphertext: ciphertext
    }

    previous_snapshot =
      Loader.initial_snapshot()
      |> Map.put(:habitify, %{
        hidden?: false,
        cards: [
          %{
            completed_days: 4,
            goal_label: "1 rep daily",
            id: "habit-1",
            name: "Floss",
            series: List.duplicate(0, 30),
            today_status: "completed",
            total_days: 30
          }
        ],
        status: :ok,
        status_message: "Live data",
        updated_at: ~U[2026-03-09 12:00:00Z]
      })

    assert {:ok, snapshot, [{:habitify, attrs}]} =
             Loader.fetch(%User{}, [integration], previous_snapshot)

    assert snapshot.habitify.status == :stale
    assert snapshot.habitify.cards == previous_snapshot.habitify.cards
    assert snapshot.habitify.status_message =~ "Using cached data."
    assert attrs.status == :error
  end

  defp dashboard_config(overrides \\ []) do
    Keyword.merge(
      [
        refresh_ttl_ms: 900_000,
        graph_days: 30,
        average_window_days: 7,
        github: %{},
        habitify: %{base_url: "https://api.habitify.me", request_options: [retry: false]},
        strava: %{
          client_id: nil,
          client_secret: nil,
          authorize_url: "https://www.strava.com/oauth/authorize",
          token_url: "https://www.strava.com/oauth/token",
          activities_url: "https://www.strava.com/api/v3/athlete/activities"
        }
      ],
      overrides
    )
  end
end
