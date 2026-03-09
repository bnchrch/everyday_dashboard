defmodule EverydayDashWeb.DashboardLiveTest do
  use EverydayDashWeb.ConnCase, async: false

  alias EverydayDash.Dashboard.Loader
  import Phoenix.LiveViewTest

  setup do
    original_config = Application.get_env(:everyday_dash, EverydayDash.Dashboard)

    on_exit(fn ->
      Application.put_env(:everyday_dash, EverydayDash.Dashboard, original_config)
    end)

    :ok
  end

  test "renders the metric cards and injected habitify cards", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    snapshot =
      Loader.initial_snapshot()
      |> Map.put(:refreshing?, false)
      |> Map.put(:updated_at, ~U[2026-03-09 12:00:00Z])
      |> Map.put(:habitify, %{
        cards: [
          habit_card("habit-floss", "Floss", "completed", 7),
          habit_card("habit-todo", "Create Todo List", "in_progress", 5)
        ],
        status: :ok,
        status_message: "Live data",
        updated_at: ~U[2026-03-09 12:00:00Z]
      })

    send(view.pid, {:dashboard_snapshot, snapshot})
    _html = render(view)

    assert has_element?(view, "#hero-message-rotator")
    assert has_element?(view, "#dashboard-refresh-button")
    assert has_element?(view, "#dashboard-metrics-grid")
    assert has_element?(view, "#metric-card-github_commits")
    assert has_element?(view, "#metric-card-strava_activities")
    assert has_element?(view, "#habitify-section")
    assert has_element?(view, "#habitify-grid")
    assert has_element?(view, "#habit-card-habit-floss")
    assert has_element?(view, "#habit-card-habit-todo")
  end

  test "renders the habitify setup state when the api key is absent", %{conn: conn} do
    Application.put_env(:everyday_dash, EverydayDash.Dashboard, dashboard_config())

    {:ok, view, _html} = live(conn, ~p"/")

    snapshot = Loader.fetch()

    send(view.pid, {:dashboard_snapshot, snapshot})
    _html = render(view)

    assert has_element?(view, "#habitify-section")
    assert has_element?(view, "#habitify-empty-state")
    assert has_element?(view, "#habitify-empty-state code", "HABITIFY_API_KEY")
  end

  defp habit_card(id, name, today_status, completed_days) do
    %{
      completed_days: completed_days,
      goal_label: "1 rep daily",
      id: id,
      name: name,
      series: habit_series(completed_days),
      today_status: today_status,
      total_days: 30
    }
  end

  defp habit_series(completed_days) do
    List.duplicate(1, completed_days) ++ List.duplicate(0, 30 - completed_days)
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
