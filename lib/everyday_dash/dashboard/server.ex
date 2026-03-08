defmodule EverydayDash.Dashboard.Server do
  @moduledoc false

  use GenServer

  alias EverydayDash.Dashboard
  alias EverydayDash.Dashboard.Loader
  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    state = %{
      snapshot: Loader.initial_snapshot(),
      refresh_timer: nil,
      task_ref: nil,
      task_pid: nil
    }

    {:ok, schedule_refresh(state, 0)}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, state.snapshot, state}
  end

  @impl true
  def handle_cast(:refresh_now, state) do
    {:noreply, trigger_refresh(state)}
  end

  @impl true
  def handle_info(:refresh, state) do
    {:noreply, trigger_refresh(state)}
  end

  @impl true
  def handle_info({ref, snapshot}, %{task_ref: ref} = state) do
    Process.demonitor(ref, [:flush])
    Dashboard.broadcast(snapshot)

    {:noreply,
     schedule_refresh(
       %{state | snapshot: snapshot, task_ref: nil, task_pid: nil},
       Dashboard.refresh_interval_ms()
     )}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{task_ref: ref} = state) do
    Logger.error("Dashboard refresh crashed: #{Exception.format_exit(reason)}")

    snapshot =
      state.snapshot
      |> Loader.mark_refresh_failed(exit_to_exception(reason))

    Dashboard.broadcast(snapshot)

    {:noreply,
     schedule_refresh(
       %{state | snapshot: snapshot, task_ref: nil, task_pid: nil},
       Dashboard.refresh_interval_ms()
     )}
  end

  @impl true
  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp trigger_refresh(%{task_ref: ref} = state) when not is_nil(ref) do
    state
  end

  defp trigger_refresh(state) do
    if state.refresh_timer, do: Process.cancel_timer(state.refresh_timer)

    task =
      Task.Supervisor.async_nolink(EverydayDash.TaskSupervisor, fn ->
        Loader.fetch(state.snapshot)
      end)

    snapshot = Loader.mark_refreshing(state.snapshot)
    Dashboard.broadcast(snapshot)

    %{state | snapshot: snapshot, refresh_timer: nil, task_ref: task.ref, task_pid: task.pid}
  end

  defp schedule_refresh(state, interval_ms) do
    if state.refresh_timer, do: Process.cancel_timer(state.refresh_timer)
    timer = Process.send_after(self(), :refresh, interval_ms)
    %{state | refresh_timer: timer}
  end

  defp exit_to_exception({%_{} = exception, _stacktrace}), do: exception
  defp exit_to_exception(%_{} = exception), do: exception

  defp exit_to_exception(reason),
    do: RuntimeError.exception("dashboard refresh exited: #{inspect(reason)}")
end
