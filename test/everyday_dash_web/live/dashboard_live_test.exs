defmodule EverydayDashWeb.DashboardLiveTest do
  use EverydayDashWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the dashboard cards", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "One page for the signals that matter every day."
    assert html =~ "GitHub commits"
    assert html =~ "Strava activities"
    assert html =~ "Life metrics, refreshed from the source"
    assert html =~ ~s(phx-hook="HeroMessageRotator")
    assert html =~ ~s(phx-update="ignore")
    assert html =~ "Remember:"
    assert html =~ "You are the base"
    assert html =~ ~s(data-messages="[&quot;You are the base&quot;)
  end
end
