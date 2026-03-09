defmodule EverydayDash.Dashboard.StravaCacheStore.DatabaseTest do
  use EverydayDash.DataCase, async: false

  alias EverydayDash.Dashboard.StravaCacheRecord
  alias EverydayDash.Dashboard.StravaCacheStore.Database

  @moduletag skip: System.get_env("DATABASE_URL") in [nil, ""]

  setup do
    Repo.delete_all(StravaCacheRecord)
    :ok
  end

  test "round-trips a persisted cache record" do
    fetched_at = DateTime.utc_now()
    backoff_until = DateTime.add(fetched_at, 900, :second)

    cache_state = %{
      service: "strava_activities",
      counts: %{"2026-03-09" => 2},
      graph_days: 30,
      window_days: 7,
      fetched_at: fetched_at,
      backoff_until: backoff_until,
      rate_limit_headers: %{"limit" => "100,1000", "usage" => "10,200"}
    }

    assert :ok = Database.save(%{}, cache_state)

    assert {:ok, loaded} = Database.load(%{}, "strava_activities")
    assert loaded.service == cache_state.service
    assert loaded.counts == cache_state.counts
    assert loaded.graph_days == 30
    assert loaded.window_days == 7
    assert DateTime.compare(loaded.fetched_at, fetched_at) == :eq
    assert DateTime.compare(loaded.backoff_until, backoff_until) == :eq
    assert loaded.rate_limit_headers == cache_state.rate_limit_headers
  end
end
