defmodule EverydayDash.Dashboard.StravaTokenStore.Database do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias EverydayDash.Dashboard.StravaTokenRecord
  alias EverydayDash.Repo

  @service "strava"

  def load do
    with true <- repo_available?(),
         %StravaTokenRecord{} = record <-
           Repo.one(
             from(record in StravaTokenRecord, where: record.service == ^@service, limit: 1)
           ) do
      {:ok,
       %{
         access_token: record.access_token,
         expires_at: record.expires_at,
         refresh_token: record.refresh_token
       }}
    else
      false -> {:error, :repo_unavailable}
      nil -> :missing
    end
  end

  def save(token_state) do
    if repo_available?() do
      changeset =
        StravaTokenRecord.changeset(%StravaTokenRecord{}, %{
          service: @service,
          access_token: token_state.access_token,
          refresh_token: token_state.refresh_token,
          expires_at: token_state.expires_at
        })

      Repo.insert(
        changeset,
        on_conflict: {:replace, [:access_token, :refresh_token, :expires_at, :updated_at]},
        conflict_target: :service
      )
      |> case do
        {:ok, _record} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :repo_unavailable}
    end
  end

  defp repo_available? do
    Process.whereis(Repo) != nil
  end
end
