defmodule EverydayDash.Dashboard.StravaTokenStore.File do
  @moduledoc false

  def load(path) do
    case File.read(path) do
      {:ok, json} ->
        with {:ok, decoded} <- Jason.decode(json) do
          {:ok,
           %{
             access_token: Map.get(decoded, "access_token"),
             expires_at: Map.get(decoded, "expires_at"),
             refresh_token: Map.get(decoded, "refresh_token")
           }}
        end

      {:error, :enoent} ->
        :missing

      {:error, reason} ->
        {:error, reason}
    end
  end

  def save(path, token_state) do
    File.mkdir_p(Path.dirname(path))

    body =
      Jason.encode!(%{
        access_token: token_state.access_token,
        expires_at: token_state.expires_at,
        refresh_token: token_state.refresh_token
      })

    File.write(path, body)
  end
end
