defmodule EverydayDash.Dashboard do
  @moduledoc false

  alias EverydayDash.Dashboard.Server

  @topic "dashboard:snapshot"
  @default_refresh_interval_ms 300_000
  @default_graph_days 30
  @default_average_window_days 7

  def subscribe do
    Phoenix.PubSub.subscribe(EverydayDash.PubSub, @topic)
  end

  def snapshot do
    GenServer.call(Server, :snapshot)
  end

  def refresh_now do
    GenServer.cast(Server, :refresh_now)
  end

  def today do
    NaiveDateTime.local_now() |> NaiveDateTime.to_date()
  end

  def broadcast(snapshot) do
    Phoenix.PubSub.broadcast(EverydayDash.PubSub, @topic, {:dashboard_snapshot, snapshot})
  end

  def config do
    Application.get_env(:everyday_dash, __MODULE__, [])
  end

  def refresh_interval_ms do
    Keyword.get(config(), :refresh_interval_ms, @default_refresh_interval_ms)
  end

  def graph_days do
    Keyword.get(config(), :graph_days, @default_graph_days)
  end

  def average_window_days do
    Keyword.get(config(), :average_window_days, @default_average_window_days)
  end

  def github_config do
    Keyword.get(config(), :github, %{})
  end

  def habitify_config do
    Keyword.get(config(), :habitify, %{})
  end

  def strava_config do
    Keyword.get(config(), :strava, %{})
  end
end
