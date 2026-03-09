defmodule EverydayDash.Dashboard.LoaderTest do
  use ExUnit.Case, async: false

  alias EverydayDash.Dashboard.Loader

  setup do
    original_config = Application.get_env(:everyday_dash, EverydayDash.Dashboard)

    on_exit(fn ->
      Application.put_env(:everyday_dash, EverydayDash.Dashboard, original_config)
    end)

    :ok
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

  defp dashboard_config do
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
    ]
  end
end
