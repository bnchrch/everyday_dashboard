defmodule EverydayDash.Dashboard.RefreshManager do
  @moduledoc false

  use GenServer

  alias EverydayDash.Accounts
  alias EverydayDash.Dashboard
  alias EverydayDash.Dashboard.Loader
  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def request_refresh(user, opts \\ []) do
    GenServer.cast(__MODULE__, {:request_refresh, user.id, Keyword.get(opts, :force, false)})
  end

  @impl true
  def init(_opts) do
    {:ok, %{tasks: %{}}}
  end

  @impl true
  def handle_cast({:request_refresh, user_id, force?}, state) do
    if Map.has_key?(state.tasks, user_id) do
      {:noreply, state}
    else
      user = Accounts.get_user_with_dashboard!(user_id)

      if force? or Dashboard.stale?(user.dashboard_snapshot) do
        snapshot = Dashboard.mark_refreshing!(user)
        Dashboard.broadcast(user_id, snapshot)

        task =
          Task.Supervisor.async_nolink(EverydayDash.TaskSupervisor, fn ->
            fresh_user = Accounts.get_user_with_dashboard!(user_id)
            previous_snapshot = Dashboard.snapshot_from_record(fresh_user.dashboard_snapshot)
            Loader.fetch(fresh_user, fresh_user.integrations, previous_snapshot)
          end)

        {:noreply, %{state | tasks: Map.put(state.tasks, user_id, task.ref)}}
      else
        {:noreply, state}
      end
    end
  end

  @impl true
  def handle_info({ref, {:ok, snapshot, integration_updates}}, state) do
    Process.demonitor(ref, [:flush])

    {user_id, tasks} = pop_task_by_ref(state.tasks, ref)
    user = Accounts.get_user_with_dashboard!(user_id)

    Enum.each(integration_updates, fn {provider, attrs} ->
      _ = Accounts.upsert_integration(user, provider, attrs)
    end)

    fresh_user = Accounts.get_user_with_dashboard!(user_id)

    persisted =
      Dashboard.persist_snapshot!(fresh_user, snapshot, refreshing: false, last_error: nil)

    Dashboard.broadcast(user_id, Dashboard.snapshot_from_record(persisted))

    {:noreply, %{state | tasks: tasks}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case pop_task_by_ref(state.tasks, ref) do
      {nil, tasks} ->
        {:noreply, %{state | tasks: tasks}}

      {user_id, tasks} ->
        Logger.error(
          "Dashboard refresh crashed for user #{user_id}: #{Exception.format_exit(reason)}"
        )

        user = Accounts.get_user_with_dashboard!(user_id)

        failed_snapshot =
          user.dashboard_snapshot
          |> Dashboard.snapshot_from_record()
          |> Loader.mark_refresh_failed(exit_to_exception(reason))

        persisted =
          Dashboard.persist_snapshot!(user, failed_snapshot,
            refreshing: false,
            last_error: Exception.message(exit_to_exception(reason)),
            refreshed_at: user.dashboard_snapshot && user.dashboard_snapshot.refreshed_at
          )

        Dashboard.broadcast(user_id, Dashboard.snapshot_from_record(persisted))

        {:noreply, %{state | tasks: tasks}}
    end
  end

  @impl true
  def handle_info(_message, state), do: {:noreply, state}

  defp pop_task_by_ref(tasks, ref) do
    case Enum.find(tasks, fn {_user_id, task_ref} -> task_ref == ref end) do
      nil -> {nil, tasks}
      {user_id, _task_ref} -> {user_id, Map.delete(tasks, user_id)}
    end
  end

  defp exit_to_exception({%_{} = exception, _stacktrace}), do: exception
  defp exit_to_exception(%_{} = exception), do: exception

  defp exit_to_exception(reason),
    do: RuntimeError.exception("dashboard refresh exited: #{inspect(reason)}")
end
