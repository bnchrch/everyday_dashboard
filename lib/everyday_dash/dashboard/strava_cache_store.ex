defmodule EverydayDash.Dashboard.StravaCacheStore do
  @moduledoc false

  alias EverydayDash.Dashboard.StravaCacheStore.Database

  def load(config, service) do
    cache_store_module(config).load(config, service)
  end

  def save(config, cache_state) do
    cache_store_module(config).save(config, cache_state)
  end

  defp cache_store_module(config) do
    Map.get(config, :cache_store, Database)
  end
end
