defmodule EverydayDashWeb.DashboardLiveTest do
  use EverydayDashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import EverydayDash.AccountsFixtures

  alias EverydayDash.Accounts
  alias EverydayDash.Dashboard
  alias EverydayDash.Repo

  test "renders the metric cards and persisted habitify cards", %{conn: conn} do
    user = published_user_fixture("metric-owner")

    snapshot =
      Dashboard.Loader.initial_snapshot()
      |> Map.put(:updated_at, ~U[2026-03-09 12:00:00Z])
      |> Map.put(:metrics, [
        fallback_metric(:github_commits, "GitHub"),
        stale_strava_metric()
      ])
      |> Map.put(:habitify, %{
        hidden?: false,
        cards: [
          habit_card("habit-floss", "Floss", "completed", 7),
          habit_card("habit-todo", "Create Todo List", "in_progress", 5)
        ],
        status: :ok,
        status_message: "Live data",
        updated_at: ~U[2026-03-09 12:00:00Z]
      })

    persist_snapshot(user, snapshot)

    {:ok, view, _html} = live(conn, ~p"/u/#{user.slug}")

    assert has_element?(view, "#hero-message-rotator")
    assert has_element?(view, "#dashboard-metrics-grid")
    assert has_element?(view, "#metric-card-github_commits")
    assert has_element?(view, "#metric-card-strava_activities")
    assert has_element?(view, "#habitify-section")
    assert has_element?(view, "#habitify-grid")
    assert has_element?(view, "#habit-card-habit-floss")
    assert has_element?(view, "#habit-card-habit-todo")
  end

  test "renders an empty state when nothing public is connected", %{conn: conn} do
    user = published_user_fixture("empty-owner")
    persist_snapshot(user, Dashboard.Loader.initial_snapshot())

    {:ok, view, _html} = live(conn, ~p"/u/#{user.slug}")

    assert has_element?(view, "#dashboard-empty-state")
    refute has_element?(view, "#dashboard-metrics-grid")
    refute has_element?(view, "#habitify-section")
  end

  test "renders friendly Strava stale copy without setup env pills", %{conn: conn} do
    user = published_user_fixture("strava-owner")

    snapshot =
      Dashboard.Loader.initial_snapshot()
      |> Map.put(:updated_at, ~U[2026-03-09 12:00:00Z])
      |> Map.put(:metrics, [
        stale_strava_metric(),
        fallback_metric(:github_commits, "GitHub")
      ])
      |> Map.put(:habitify, %{
        hidden?: true,
        cards: [],
        status: nil,
        status_message: nil,
        updated_at: nil
      })

    persist_snapshot(user, snapshot)

    {:ok, view, _html} = live(conn, ~p"/u/#{user.slug}")
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

  defp published_user_fixture(slug) do
    user = user_fixture()

    user
    |> Ecto.Changeset.change(slug: slug, dashboard_published_at: DateTime.utc_now())
    |> Repo.update!()
    |> Accounts.get_user_with_dashboard!()
  end

  defp persist_snapshot(user, snapshot) do
    Dashboard.persist_snapshot!(Accounts.get_user_with_dashboard!(user.id), snapshot)
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
      source_label: "Strava",
      status: :stale,
      status_message: "Using cached Strava data while the rate limit resets.",
      setup_envs: [],
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
      setup_envs: [],
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
end
