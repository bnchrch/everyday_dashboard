defmodule EverydayDash.Dashboard.Sources.GitHubTest do
  use ExUnit.Case, async: false

  import Plug.Conn

  alias EverydayDash.Dashboard.Sources.GitHub

  setup {Req.Test, :verify_on_exit!}

  setup do
    original_config = Application.get_env(:everyday_dash, EverydayDash.Dashboard)

    on_exit(fn ->
      Application.put_env(:everyday_dash, EverydayDash.Dashboard, original_config)
    end)

    :ok
  end

  test "counts branch-only commits and de-duplicates duplicate shas across branches" do
    stub_name = {:github_test, System.unique_integer([:positive])}

    Req.Test.stub(stub_name, fn conn ->
      {conn, query, variables} = decode_graphql_request(conn)

      cond do
        String.contains?(query, "DashboardGitHubUser") ->
          Req.Test.json(conn, %{"data" => %{"user" => %{"id" => "USER_123"}}})

        String.contains?(query, "DashboardGitHubRepositories") ->
          assert variables["after"] == nil

          Req.Test.json(
            conn,
            repo_connection_response([
              repo_node("bnchrch/everyday_dashboard", "2026-03-09T12:00:00Z")
            ])
          )

        String.contains?(query, "DashboardGitHubBranchRefs") ->
          assert variables["owner"] == "bnchrch"
          assert variables["name"] == "everyday_dashboard"
          assert variables["after"] == nil

          Req.Test.json(conn, refs_response(["main", "feature/login"]))

        String.contains?(query, "DashboardGitHubBranchHistory") ->
          history_response =
            case variables["qualifiedName"] do
              "refs/heads/main" ->
                history_response([
                  commit_node("sha-main", "2026-03-08T09:00:00Z"),
                  commit_node("sha-dup", "2026-03-09T09:00:00Z")
                ])

              "refs/heads/feature/login" ->
                history_response([
                  commit_node("sha-dup", "2026-03-09T09:00:00Z"),
                  commit_node("sha-branch", "2026-03-09T12:00:00Z")
                ])

              other ->
                flunk("unexpected branch history request for #{inspect(other)}")
            end

          Req.Test.json(conn, history_response)

        true ->
          flunk("unexpected GitHub request: #{query}")
      end
    end)

    put_dashboard_config(stub_name)

    assert {:ok, payload} = GitHub.fetch(~D[2026-03-09], 30, 7)
    assert payload.source_label == "Git history"
    assert payload.status_message == "Live across owned repo branches."
    assert payload.counts == %{~D[2026-03-08] => 1, ~D[2026-03-09] => 2}
  end

  test "paginates repositories refs and branch history while aggregating across repos" do
    stub_name = {:github_test, System.unique_integer([:positive])}

    Req.Test.stub(stub_name, fn conn ->
      {conn, query, variables} = decode_graphql_request(conn)

      cond do
        String.contains?(query, "DashboardGitHubUser") ->
          Req.Test.json(conn, %{"data" => %{"user" => %{"id" => "USER_123"}}})

        String.contains?(query, "DashboardGitHubRepositories") and variables["after"] == nil ->
          Req.Test.json(
            conn,
            repo_connection_response(
              [repo_node("bnchrch/everyday_dashboard", "2026-03-09T12:00:00Z")],
              true,
              "repo-page-2"
            )
          )

        String.contains?(query, "DashboardGitHubRepositories") and
            variables["after"] == "repo-page-2" ->
          Req.Test.json(
            conn,
            repo_connection_response([repo_node("bnchrch/writing", "2026-03-09T07:00:00Z")])
          )

        String.contains?(query, "DashboardGitHubBranchRefs") and
          variables["name"] == "everyday_dashboard" and
            variables["after"] == nil ->
          Req.Test.json(conn, refs_response(["main"], true, "refs-page-2"))

        String.contains?(query, "DashboardGitHubBranchRefs") and
          variables["name"] == "everyday_dashboard" and
            variables["after"] == "refs-page-2" ->
          Req.Test.json(conn, refs_response(["feature/metrics"]))

        String.contains?(query, "DashboardGitHubBranchRefs") and variables["name"] == "writing" ->
          Req.Test.json(conn, refs_response(["master"]))

        String.contains?(query, "DashboardGitHubBranchHistory") and
          variables["qualifiedName"] == "refs/heads/main" and variables["after"] == nil ->
          Req.Test.json(
            conn,
            history_response([commit_node("sha-1", "2026-03-04T08:00:00Z")], true, "hist-page-2")
          )

        String.contains?(query, "DashboardGitHubBranchHistory") and
          variables["qualifiedName"] == "refs/heads/main" and variables["after"] == "hist-page-2" ->
          Req.Test.json(conn, history_response([commit_node("sha-2", "2026-03-09T08:30:00Z")]))

        String.contains?(query, "DashboardGitHubBranchHistory") and
            variables["qualifiedName"] == "refs/heads/feature/metrics" ->
          Req.Test.json(conn, history_response([commit_node("sha-3", "2026-03-09T09:00:00Z")]))

        String.contains?(query, "DashboardGitHubBranchHistory") and
            variables["qualifiedName"] == "refs/heads/master" ->
          Req.Test.json(conn, history_response([commit_node("sha-4", "2026-03-09T11:00:00Z")]))

        true ->
          flunk("unexpected GitHub request: #{inspect(variables)}")
      end
    end)

    put_dashboard_config(stub_name)

    assert {:ok, payload} = GitHub.fetch(~D[2026-03-09], 30, 7)
    assert payload.counts == %{~D[2026-03-04] => 1, ~D[2026-03-09] => 3}
  end

  test "skips archived repositories entirely" do
    stub_name = {:github_test, System.unique_integer([:positive])}

    Req.Test.stub(stub_name, fn conn ->
      {conn, query, variables} = decode_graphql_request(conn)

      cond do
        String.contains?(query, "DashboardGitHubUser") ->
          Req.Test.json(conn, %{"data" => %{"user" => %{"id" => "USER_123"}}})

        String.contains?(query, "DashboardGitHubRepositories") ->
          Req.Test.json(
            conn,
            repo_connection_response([
              repo_node("bnchrch/archived-repo", "2026-03-09T12:00:00Z", true),
              repo_node("bnchrch/everyday_dashboard", "2026-03-09T10:00:00Z")
            ])
          )

        String.contains?(query, "DashboardGitHubBranchRefs") and
            variables["name"] == "archived-repo" ->
          flunk("archived repositories should not be queried for refs")

        String.contains?(query, "DashboardGitHubBranchRefs") and
            variables["name"] == "everyday_dashboard" ->
          Req.Test.json(conn, refs_response(["main"]))

        String.contains?(query, "DashboardGitHubBranchHistory") and
            variables["qualifiedName"] == "refs/heads/main" ->
          Req.Test.json(conn, history_response([commit_node("sha-live", "2026-03-09T10:30:00Z")]))

        true ->
          flunk("unexpected GitHub request: #{inspect(variables)}")
      end
    end)

    put_dashboard_config(stub_name)

    assert {:ok, payload} = GitHub.fetch(~D[2026-03-09], 30, 7)
    assert payload.counts == %{~D[2026-03-09] => 1}
  end

  test "returns a friendly error when the configured github user does not exist" do
    stub_name = {:github_test, System.unique_integer([:positive])}

    Req.Test.stub(stub_name, fn conn ->
      {conn, query, _variables} = decode_graphql_request(conn)

      if String.contains?(query, "DashboardGitHubUser") do
        Req.Test.json(conn, %{"data" => %{"user" => nil}})
      else
        flunk("unexpected follow-up request after missing user")
      end
    end)

    put_dashboard_config(stub_name)

    assert {:error, :request_failed, "GitHub could not find @bnchrch."} =
             GitHub.fetch(~D[2026-03-09], 30, 7)
  end

  test "returns graphql errors from github cleanly" do
    stub_name = {:github_test, System.unique_integer([:positive])}

    Req.Test.stub(stub_name, fn conn ->
      {conn, query, variables} = decode_graphql_request(conn)

      cond do
        String.contains?(query, "DashboardGitHubUser") ->
          Req.Test.json(conn, %{"data" => %{"user" => %{"id" => "USER_123"}}})

        String.contains?(query, "DashboardGitHubRepositories") ->
          assert variables["login"] == "bnchrch"
          Req.Test.json(conn, %{"errors" => [%{"message" => "boom"}]})

        true ->
          flunk("unexpected GitHub request: #{query}")
      end
    end)

    put_dashboard_config(stub_name)

    assert {:error, :request_failed, "boom"} = GitHub.fetch(~D[2026-03-09], 30, 7)
  end

  test "returns a setup error when github config is missing" do
    put_dashboard_config(nil, %{username: nil, token: nil})

    assert {:error, :missing_config,
            "Set GITHUB_USERNAME and GITHUB_TOKEN to load live GitHub commits."} =
             GitHub.fetch(~D[2026-03-09], 30, 7)
  end

  defp put_dashboard_config(stub_name, overrides \\ %{}) do
    request_options =
      if stub_name do
        [plug: {Req.Test, stub_name}, retry: false]
      else
        []
      end

    github_config =
      %{
        username: "bnchrch",
        token: "github-token",
        request_options: request_options
      }
      |> Map.merge(overrides)

    Application.put_env(
      :everyday_dash,
      EverydayDash.Dashboard,
      refresh_interval_ms: 60_000,
      graph_days: 30,
      average_window_days: 7,
      github: github_config,
      habitify: %{api_key: nil},
      strava: %{
        client_id: nil,
        client_secret: nil,
        refresh_token: nil,
        token_store_backend: :file,
        token_store_path: "/tmp/strava_tokens_test.json"
      }
    )
  end

  defp decode_graphql_request(conn) do
    assert conn.request_path == "/graphql"
    {:ok, body, conn} = read_body(conn)
    payload = Jason.decode!(body)
    {conn, payload["query"], payload["variables"] || %{}}
  end

  defp repo_connection_response(nodes, has_next_page \\ false, end_cursor \\ nil) do
    %{
      "data" => %{
        "user" => %{
          "repositories" => %{
            "nodes" => nodes,
            "pageInfo" => %{
              "hasNextPage" => has_next_page,
              "endCursor" => end_cursor
            }
          }
        }
      }
    }
  end

  defp refs_response(branch_names, has_next_page \\ false, end_cursor \\ nil) do
    %{
      "data" => %{
        "repository" => %{
          "refs" => %{
            "nodes" => Enum.map(branch_names, &%{"name" => &1}),
            "pageInfo" => %{
              "hasNextPage" => has_next_page,
              "endCursor" => end_cursor
            }
          }
        }
      }
    }
  end

  defp history_response(nodes, has_next_page \\ false, end_cursor \\ nil) do
    %{
      "data" => %{
        "repository" => %{
          "ref" => %{
            "target" => %{
              "__typename" => "Commit",
              "history" => %{
                "nodes" => nodes,
                "pageInfo" => %{
                  "hasNextPage" => has_next_page,
                  "endCursor" => end_cursor
                }
              }
            }
          }
        }
      }
    }
  end

  defp repo_node(name_with_owner, pushed_at, is_archived \\ false) do
    %{
      "nameWithOwner" => name_with_owner,
      "isArchived" => is_archived,
      "pushedAt" => pushed_at
    }
  end

  defp commit_node(oid, authored_date) do
    %{
      "oid" => oid,
      "authoredDate" => authored_date
    }
  end
end
