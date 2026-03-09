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

  test "renders friendly Strava stale copy without setup env pills", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    snapshot =
      Loader.initial_snapshot()
      |> Map.put(:refreshing?, false)
      |> Map.put(:updated_at, ~U[2026-03-09 12:00:00Z])
      |> Map.put(:metrics, [
        stale_strava_metric(),
        fallback_metric(:github_commits, "Work")
      ])

    send(view.pid, {:dashboard_snapshot, snapshot})
    html = render(view)

    assert has_element?(
             view,
             "#metric-card-strava_activities",
             "Using cached Strava data while the rate limit resets."
           )

    refute has_element?(view, "#metric-card-strava_activities code")
    refute html =~ "\"errors\""
    refute html =~ "Rate Limit Exceeded"
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

  defp stale_strava_metric do
    %{
      id: :strava_activities,
      label: "Strava activities",
      description:
        "Daily Strava activity count over the last month, smoothed with the same trailing window.",
      accent: "pine",
      unit: "activities/day",
      source_label: "Play",
      status: :stale,
      status_message: "Using cached Strava data while the rate limit resets.",
      setup_envs: ["STRAVA_CLIENT_ID", "STRAVA_CLIENT_SECRET", "STRAVA_REFRESH_TOKEN"],
      current_average: 1.4,
      today_count: 1,
      total_count: 4,
      average_series: series_points([0.0, 0.5, 1.0, 1.4]),
      raw_series: raw_points([0, 1, 2, 1]),
      updated_at: ~U[2026-03-09 12:00:00Z]
    }
  end

  defp fallback_metric(id, headline) do
    %{
      id: id,
      label: if(id == :github_commits, do: "GitHub commits", else: "Metric"),
      description: "Fallback metric for test coverage.",
      accent: "embers",
      unit: "commits/day",
      source_label: headline,
      status: :ok,
      status_message: "Live data",
      setup_envs: ["GITHUB_USERNAME", "GITHUB_TOKEN"],
      current_average: 0.0,
      today_count: 0,
      total_count: 0,
      average_series: series_points([0.0, 0.0, 0.0, 0.0]),
      raw_series: raw_points([0, 0, 0, 0]),
      updated_at: ~U[2026-03-09 12:00:00Z]
    }
  end

  defp series_points(values) do
    Enum.with_index(values, fn value, index ->
      %{date: Date.add(~D[2026-03-06], index), value: value}
    end)
  end

  defp raw_points(values) do
    Enum.with_index(values, fn value, index ->
      %{date: Date.add(~D[2026-03-06], index), value: value}
    end)
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
