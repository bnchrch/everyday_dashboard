defmodule EverydayDash.Dashboard.StravaTokenStore do
  @moduledoc false

  alias EverydayDash.Dashboard.StravaTokenStore.Database
  alias EverydayDash.Dashboard.StravaTokenStore.File

  def load(config) do
    case Map.get(config, :token_store_backend, :file) do
      :database -> Database.load()
      :file -> File.load(Map.fetch!(config, :token_store_path))
    end
  end

  def save(config, token_state) do
    case Map.get(config, :token_store_backend, :file) do
      :database -> Database.save(token_state)
      :file -> File.save(Map.fetch!(config, :token_store_path), token_state)
    end
  end
end
