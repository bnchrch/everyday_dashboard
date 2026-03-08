defmodule EverydayDashWeb.PageController do
  use EverydayDashWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
