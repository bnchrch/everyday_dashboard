defmodule EverydayDash.Dashboard do
  @moduledoc false

  alias EverydayDash.Accounts
  alias EverydayDash.Accounts.User
  alias EverydayDash.Dashboard.{Loader, RefreshManager, Serializer, SnapshotRecord}
  alias EverydayDash.Repo

  @topic_prefix "dashboard:snapshot"
  @default_refresh_ttl_ms 900_000
  @default_graph_days 30
  @default_average_window_days 7

  def subscribe(%User{id: user_id}), do: subscribe(user_id)

  def subscribe(user_id) when is_integer(user_id) do
    Phoenix.PubSub.subscribe(EverydayDash.PubSub, topic(user_id))
  end

  def broadcast(%User{id: user_id}, snapshot), do: broadcast(user_id, snapshot)

  def broadcast(user_id, snapshot) when is_integer(user_id) do
    Phoenix.PubSub.broadcast(
      EverydayDash.PubSub,
      topic(user_id),
      {:dashboard_snapshot, snapshot}
    )
  end

  def snapshot_for_user(%User{} = user) do
    user
    |> Accounts.preload_dashboard_data()
    |> Map.get(:dashboard_snapshot)
    |> snapshot_from_record()
  end

  def public_dashboard_by_slug(slug) do
    case Accounts.get_published_user_by_slug(slug) do
      nil ->
        {:error, :not_found}

      %User{} = user ->
        {:ok, user, snapshot_from_record(user.dashboard_snapshot)}
    end
  end

  def request_refresh(user_or_id, opts \\ [])

  def request_refresh(%User{id: user_id}, opts) do
    request_refresh(user_id, opts)
  end

  def request_refresh(user_id, opts) when is_integer(user_id) do
    if async_refresh?() do
      RefreshManager.request_refresh(%User{id: user_id}, opts)
    else
      refresh_now(user_id, opts)
    end
  end

  def maybe_refresh(%User{} = user, opts \\ []) do
    user = Accounts.preload_dashboard_data(user)
    force? = Keyword.get(opts, :force, false)

    if auto_refresh_enabled?() and (force? or stale?(user.dashboard_snapshot)) do
      request_refresh(user, force: force?)
    end

    :ok
  end

  def mark_refreshing!(%User{} = user) do
    snapshot =
      user
      |> Map.get(:dashboard_snapshot)
      |> snapshot_from_record()
      |> Map.put(:refreshing?, true)

    persist_snapshot!(user, snapshot,
      refreshing: true,
      refreshed_at: user.dashboard_snapshot && user.dashboard_snapshot.refreshed_at
    )

    snapshot
  end

  def persist_snapshot!(%User{} = user, snapshot, opts \\ []) do
    record =
      user.dashboard_snapshot ||
        %SnapshotRecord{user_id: user.id}

    attrs = %{
      user_id: user.id,
      payload: Serializer.dump(snapshot),
      refreshed_at: Keyword.get(opts, :refreshed_at, snapshot.updated_at),
      refreshing: Keyword.get(opts, :refreshing, false),
      last_error: Keyword.get(opts, :last_error)
    }

    record
    |> SnapshotRecord.changeset(attrs)
    |> Repo.insert_or_update!()
  end

  def snapshot_from_record(nil), do: Loader.initial_snapshot()

  def snapshot_from_record(%SnapshotRecord{payload: payload, refreshing: refreshing})
      when payload in [%{}, nil] do
    Loader.initial_snapshot()
    |> Map.put(:refreshing?, refreshing)
  end

  def snapshot_from_record(%SnapshotRecord{payload: payload, refreshing: refreshing}) do
    payload
    |> Serializer.load()
    |> Map.put(:refreshing?, refreshing)
  end

  def stale?(nil), do: true
  def stale?(%SnapshotRecord{refreshed_at: nil}), do: true

  def stale?(%SnapshotRecord{refreshed_at: %DateTime{} = refreshed_at}) do
    DateTime.diff(DateTime.utc_now(), refreshed_at, :millisecond) >= refresh_ttl_ms()
  end

  def today do
    NaiveDateTime.local_now() |> NaiveDateTime.to_date()
  end

  def config do
    Application.get_env(:everyday_dash, __MODULE__, [])
  end

  def refresh_ttl_ms do
    Keyword.get(config(), :refresh_ttl_ms, @default_refresh_ttl_ms)
  end

  def async_refresh? do
    Keyword.get(config(), :async_refresh?, true)
  end

  def auto_refresh_enabled? do
    Keyword.get(config(), :auto_refresh_on_mount?, true)
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

  defp refresh_now(user_id, opts) do
    user = Accounts.get_user_with_dashboard!(user_id)
    force? = Keyword.get(opts, :force, false)

    if force? or stale?(user.dashboard_snapshot) do
      user
      |> mark_refreshing!()
      |> then(&broadcast(user_id, &1))

      complete_refresh(user_id)
    else
      :ok
    end
  end

  defp complete_refresh(user_id) do
    user = Accounts.get_user_with_dashboard!(user_id)
    previous_snapshot = snapshot_from_record(user.dashboard_snapshot)

    {:ok, snapshot, integration_updates} =
      Loader.fetch(user, user.integrations, previous_snapshot)

    Enum.each(integration_updates, fn {provider, attrs} ->
      _ = Accounts.upsert_integration(user, provider, attrs)
    end)

    fresh_user = Accounts.get_user_with_dashboard!(user_id)
    persisted = persist_snapshot!(fresh_user, snapshot, refreshing: false, last_error: nil)
    broadcast(user_id, snapshot_from_record(persisted))
    :ok
  rescue
    error ->
      fail_refresh(user_id, error)
  catch
    kind, reason ->
      fail_refresh(user_id, Exception.normalize(kind, reason, __STACKTRACE__))
  end

  defp fail_refresh(user_id, error) do
    user = Accounts.get_user_with_dashboard!(user_id)

    failed_snapshot =
      user.dashboard_snapshot
      |> snapshot_from_record()
      |> Loader.mark_refresh_failed(error)

    persisted =
      persist_snapshot!(user, failed_snapshot,
        refreshing: false,
        last_error: Exception.message(error),
        refreshed_at: user.dashboard_snapshot && user.dashboard_snapshot.refreshed_at
      )

    broadcast(user_id, snapshot_from_record(persisted))
    :ok
  end

  defp topic(user_id), do: "#{@topic_prefix}:#{user_id}"
end
