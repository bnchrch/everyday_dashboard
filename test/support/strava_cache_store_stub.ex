defmodule EverydayDash.TestSupport.StravaCacheStoreStub do
  @moduledoc false

  def load(config, _service) do
    case Agent.get(agent_name(config), & &1.record) do
      nil -> :missing
      record -> {:ok, record}
    end
  end

  def save(config, cache_state) do
    Agent.update(agent_name(config), fn state ->
      %{state | record: cache_state, saves: [cache_state | state.saves]}
    end)

    :ok
  end

  def put(agent_name, cache_state) do
    Agent.update(agent_name, fn state -> %{state | record: cache_state} end)
  end

  def saves(agent_name) do
    Agent.get(agent_name, &Enum.reverse(&1.saves))
  end

  def clear(agent_name) do
    Agent.update(agent_name, fn _state -> %{record: nil, saves: []} end)
  end

  defp agent_name(config) do
    Map.fetch!(config, :cache_agent)
  end
end
