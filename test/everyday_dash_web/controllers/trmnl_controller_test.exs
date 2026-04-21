defmodule EverydayDashWeb.TrmnlControllerTest do
  use EverydayDashWeb.ConnCase, async: true

  test "renders a screenshot-safe TRMNL document", %{conn: conn} do
    conn = get(conn, ~p"/trmnl/screenshot")
    html = html_response(conn, 200)

    assert html =~ ~s(id="trmnl-screenshot")
    assert html =~ ~s(id="trmnl-screenshot-metrics")
    assert html =~ ~s(id="trmnl-screenshot-habits")
    assert html =~ ~s(id="shot-metric-github_commits")
    assert html =~ ~s(id="shot-metric-strava_activities")
    assert html =~ "width: 800px;"
    assert html =~ "height: 480px;"
    assert html =~ "<style>"
    refute html =~ "/assets/css/app.css"
    refute html =~ "/assets/js/app.js"
    refute html =~ "phx-hook"
  end
end
