defmodule EverydayDash.Dashboard.LoaderTest do
  use ExUnit.Case, async: false

  import Plug.Conn

  alias EverydayDash.Dashboard
  alias EverydayDash.Dashboard.Loader
  alias EverydayDash.TestSupport.StravaCacheStoreStub

  setup {Req.Test, :verify_on_exit!}

  setup do
    original_config = Application.get_env(:everyday_dash, EverydayDash.Dashboard)

    on_exit(fn ->
      Application.put_env(:everyday_dash, EverydayDash.Dashboard, original_config)
    end)

    :ok
  end

  test "preserves a source-provided stale status for Strava when a persisted backoff is active" do
    cache_agent = start_supervised!({Agent, fn -> %{record: nil, saves: []} end})
    today = Dashboard.today()

    StravaCacheStoreStub.put(cache_agent, %{
      service: "strava_activities",
      counts: %{Date.to_iso8601(today) => 2},
      graph_days: 30,
      window_days: 7,
      fetched_at: DateTime.utc_now(),
      backoff_until: DateTime.add(DateTime.utc_now(), 900, :second),
      rate_limit_headers: %{"limit" => "100,1000", "usage" => "100,1000"}
    })

    Application.put_env(
      :everyday_dash,
      EverydayDash.Dashboard,
      dashboard_config(
        strava: %{
          cache_agent: cache_agent,
          cache_store: StravaCacheStoreStub,
          cache_ttl_ms: 900_000,
          client_id: nil,
          client_secret: nil,
          refresh_token: nil,
          token_store_backend: :file,
          token_store_path: "/tmp/strava_tokens_test.json"
        }
      )
    )

    snapshot = Loader.fetch()
    strava_metric = Enum.find(snapshot.metrics, &(&1.id == :strava_activities))

    assert strava_metric.status == :stale
    assert strava_metric.status_message == "Using cached Strava data while the rate limit resets."
    assert strava_metric.today_count == 2
  end

  test "keeps cached habitify cards as stale when the API is unavailable" do
    Application.put_env(:everyday_dash, EverydayDash.Dashboard, dashboard_config())

    previous_snapshot =
      Loader.initial_snapshot()
      |> Map.put(:habitify, %{
        cards: [
          %{
            completed_days: 4,
            goal_label: "1 rep daily",
            id: "habit-1",
            name: "Floss",
            series: List.duplicate(0, 30),
            today_status: "completed",
            total_days: 30
          }
        ],
        status: :ok,
        status_message: "Live data",
        updated_at: ~U[2026-03-09 12:00:00Z]
      })

    snapshot = Loader.fetch(previous_snapshot)

    assert snapshot.habitify.status == :stale
    assert snapshot.habitify.cards == previous_snapshot.habitify.cards
    assert snapshot.habitify.status_message =~ "Using cached data."
    assert snapshot.habitify.status_message =~ "HABITIFY_API_KEY"
  end

  test "builds the github metric today count and trailing average from branch history" do
    stub_name = {:github_loader_test, System.unique_integer([:positive])}
    today = Dashboard.today()

    Req.Test.stub(stub_name, fn conn ->
      assert conn.request_path == "/graphql"
      {:ok, body, conn} = read_body(conn)
      payload = Jason.decode!(body)
      query = payload["query"]
      variables = payload["variables"] || %{}

      cond do
        String.contains?(query, "DashboardGitHubUser") ->
          Req.Test.json(conn, %{"data" => %{"user" => %{"id" => "USER_123"}}})

        String.contains?(query, "DashboardGitHubRepositories") ->
          Req.Test.json(
            conn,
            %{
              "data" => %{
                "user" => %{
                  "repositories" => %{
                    "nodes" => [
                      %{
                        "nameWithOwner" => "bnchrch/everyday_dashboard",
                        "isArchived" => false,
                        "pushedAt" => authored_at(today, 0, 12)
                      }
                    ],
                    "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil}
                  }
                }
              }
            }
          )

        String.contains?(query, "DashboardGitHubBranchRefs") ->
          assert variables["name"] == "everyday_dashboard"

          Req.Test.json(
            conn,
            %{
              "data" => %{
                "repository" => %{
                  "refs" => %{
                    "nodes" => [%{"name" => "main"}],
                    "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil}
                  }
                }
              }
            }
          )

        String.contains?(query, "DashboardGitHubBranchHistory") ->
          assert variables["qualifiedName"] == "refs/heads/main"

          Req.Test.json(
            conn,
            %{
              "data" => %{
                "repository" => %{
                  "ref" => %{
                    "target" => %{
                      "__typename" => "Commit",
                      "history" => %{
                        "nodes" => [
                          %{"oid" => "sha-1", "authoredDate" => authored_at(today, -6, 8)},
                          %{"oid" => "sha-2", "authoredDate" => authored_at(today, -5, 8)},
                          %{"oid" => "sha-3", "authoredDate" => authored_at(today, -4, 8)},
                          %{"oid" => "sha-4", "authoredDate" => authored_at(today, -3, 8)},
                          %{"oid" => "sha-5", "authoredDate" => authored_at(today, 0, 8)},
                          %{"oid" => "sha-6", "authoredDate" => authored_at(today, 0, 9)},
                          %{"oid" => "sha-7", "authoredDate" => authored_at(today, 0, 10)}
                        ],
                        "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil}
                      }
                    }
                  }
                }
              }
            }
          )

        true ->
          flunk("unexpected GitHub request: #{query}")
      end
    end)

    Application.put_env(
      :everyday_dash,
      EverydayDash.Dashboard,
      dashboard_config(
        github: %{
          username: "bnchrch",
          token: "github-token",
          request_options: [plug: {Req.Test, stub_name}, retry: false]
        }
      )
    )

    snapshot = Loader.fetch()
    github_metric = Enum.find(snapshot.metrics, &(&1.id == :github_commits))

    assert github_metric.source_label == "Git history"
    assert github_metric.status == :ok
    assert github_metric.status_message == "Live across owned repo branches."
    assert github_metric.today_count == 3
    assert github_metric.current_average == 1.0
  end

  defp dashboard_config(overrides \\ []) do
    Keyword.merge(
      [
        refresh_interval_ms: 60_000,
        graph_days: 30,
        average_window_days: 7,
        github: %{username: nil, token: nil},
        habitify: %{api_key: nil},
        strava: %{
          client_id: nil,
          client_secret: nil,
          refresh_token: nil,
          token_store_backend: :file,
          token_store_path: "/tmp/strava_tokens_test.json"
        }
      ],
      overrides
    )
  end

  defp authored_at(today, day_offset, hour) do
    today
    |> Date.add(day_offset)
    |> Date.to_iso8601()
    |> Kernel.<>("T#{hour |> Integer.to_string() |> String.pad_leading(2, "0")}:00:00Z")
  end
end
