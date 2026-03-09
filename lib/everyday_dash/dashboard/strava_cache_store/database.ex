defmodule EverydayDash.Dashboard.StravaCacheStore.Database do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias EverydayDash.Dashboard.StravaCacheRecord
  alias EverydayDash.Repo

  def load(_config, service) do
    with true <- repo_available?(),
         %StravaCacheRecord{} = record <-
           Repo.one(
             from(record in StravaCacheRecord, where: record.service == ^service, limit: 1)
           ) do
      {:ok,
       %{
         service: record.service,
         counts: record.counts || %{},
         graph_days: record.graph_days,
         window_days: record.window_days,
         fetched_at: record.fetched_at,
         backoff_until: record.backoff_until,
         rate_limit_headers: record.rate_limit_headers || %{}
       }}
    else
      false -> {:error, :repo_unavailable}
      nil -> :missing
    end
  end

  def save(_config, cache_state) do
    if repo_available?() do
      changeset = StravaCacheRecord.changeset(%StravaCacheRecord{}, cache_state)

      Repo.insert(
        changeset,
        on_conflict:
          {:replace,
           [
             :counts,
             :graph_days,
             :window_days,
             :fetched_at,
             :backoff_until,
             :rate_limit_headers,
             :updated_at
           ]},
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
