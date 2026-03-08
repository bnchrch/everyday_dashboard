defmodule EverydayDashWeb.DashboardLiveTest do
  use EverydayDashWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the dashboard cards", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "One page for the signals that matter every day."
    assert html =~ "GitHub commits"
    assert html =~ "Strava activities"
    assert html =~ "Life metrics, refreshed from the source"
  end
end
