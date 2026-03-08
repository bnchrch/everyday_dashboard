defmodule EverydayDash.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        EverydayDashWeb.Telemetry,
        {DNSCluster, query: Application.get_env(:everyday_dash, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: EverydayDash.PubSub}
      ] ++
        repo_children() ++
        [
          {Task.Supervisor, name: EverydayDash.TaskSupervisor},
          EverydayDash.Dashboard.Server,
          EverydayDashWeb.Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: EverydayDash.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EverydayDashWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp repo_children do
    case Application.get_env(:everyday_dash, EverydayDash.Repo) do
      nil -> []
      [] -> []
      _config -> [EverydayDash.Repo]
    end
  end
end
