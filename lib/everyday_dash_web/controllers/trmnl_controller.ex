defmodule EverydayDashWeb.TrmnlController do
  use EverydayDashWeb, :controller

  alias EverydayDash.Dashboard

  def show(conn, _params) do
    conn
    |> put_root_layout(false)
    |> put_layout(false)
    |> put_resp_header("x-robots-tag", "noindex")
    |> render(:show, page_title: "Everyday Dash TRMNL", snapshot: Dashboard.snapshot())
  end
end
