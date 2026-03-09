defmodule EverydayDash.Dashboard.LoaderTest do
  use ExUnit.Case, async: false

  alias EverydayDash.Dashboard.Loader
  alias EverydayDash.TestSupport.StravaCacheStoreStub

  setup do
    original_config = Application.get_env(:everyday_dash, EverydayDash.Dashboard)

    on_exit(fn ->
      Application.put_env(:everyday_dash, EverydayDash.Dashboard, original_config)
    end)

    :ok
  end

  test "preserves a source-provided stale status for Strava when a persisted backoff is active" do
    cache_agent = start_supervised!({Agent, fn -> %{record: nil, saves: []} end})

    StravaCacheStoreStub.put(cache_agent, %{
      service: "strava_activities",
      counts: %{"2026-03-09" => 2},
      graph_days: 30,
      window_days: 7,
      fetched_at: DateTime.utc_now(),
      backoff_until: DateTime.add(DateTime.utc_now(), 900, :second),
      rate_limit_headers: %{"limit" => "100,1000", "usage" => "100,1000"}
    })

    Application.put_env(
      :everyday_dash,
      EverydayDash.Dashboard,
      dashboard_config(
        strava: %{
          cache_agent: cache_agent,
          cache_store: StravaCacheStoreStub,
          cache_ttl_ms: 900_000,
          client_id: nil,
          client_secret: nil,
          refresh_token: nil,
          token_store_backend: :file,
          token_store_path: "/tmp/strava_tokens_test.json"
        }
      )
    )

    snapshot = Loader.fetch()
    strava_metric = Enum.find(snapshot.metrics, &(&1.id == :strava_activities))

    assert strava_metric.status == :stale
    assert strava_metric.status_message == "Using cached Strava data while the rate limit resets."
    assert strava_metric.today_count == 2
  end

  test "keeps cached habitify cards as stale when the API is unavailable" do
    Application.put_env(:everyday_dash, EverydayDash.Dashboard, dashboard_config())

    previous_snapshot =
      Loader.initial_snapshot()
      |> Map.put(:habitify, %{
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

    snapshot = Loader.fetch(previous_snapshot)

    assert snapshot.habitify.status == :stale
    assert snapshot.habitify.cards == previous_snapshot.habitify.cards
    assert snapshot.habitify.status_message =~ "Using cached data."
    assert snapshot.habitify.status_message =~ "HABITIFY_API_KEY"
  end

  defp dashboard_config(overrides \\ []) do
    Keyword.merge(
      [
        refresh_interval_ms: 60_000,
        graph_days: 30,
        average_window_days: 7,
        github: %{username: nil, token: nil},
        habitify: %{api_key: nil},
        strava: %{
          client_id: nil,
          client_secret: nil,
          refresh_token: nil,
          token_store_backend: :file,
          token_store_path: "/tmp/strava_tokens_test.json"
        }
      ],
      overrides
    )
  end
end
