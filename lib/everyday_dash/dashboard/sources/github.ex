defmodule EverydayDash.Dashboard.Sources.GitHub do
  @moduledoc false

  alias EverydayDash.Dashboard
  alias EverydayDash.Dashboard.Series

  @endpoint "https://api.github.com/graphql"
  @repo_page_size 25
  @ref_page_size 50
  @history_page_size 100

  @user_query """
  query DashboardGitHubUser($login: String!) {
    user(login: $login) {
      id
    }
  }
  """

  @repositories_query """
  query DashboardGitHubRepositories($login: String!, $after: String) {
    user(login: $login) {
      repositories(
        first: #{@repo_page_size},
        after: $after,
        ownerAffiliations: OWNER,
        orderBy: {field: PUSHED_AT, direction: DESC}
      ) {
        nodes {
          nameWithOwner
          isArchived
          pushedAt
        }
        pageInfo {
          hasNextPage
          endCursor
        }
      }
    }
  }
  """

  @refs_query """
  query DashboardGitHubBranchRefs($owner: String!, $name: String!, $after: String) {
    repository(owner: $owner, name: $name) {
      refs(refPrefix: "refs/heads/", first: #{@ref_page_size}, after: $after) {
        nodes {
          name
        }
        pageInfo {
          hasNextPage
          endCursor
        }
      }
    }
  }
  """

  @history_query """
  query DashboardGitHubBranchHistory(
    $owner: String!
    $name: String!
    $qualifiedName: String!
    $authorId: ID!
    $since: GitTimestamp!
    $after: String
  ) {
    repository(owner: $owner, name: $name) {
      ref(qualifiedName: $qualifiedName) {
        target {
          __typename
          ... on Commit {
            history(
              first: #{@history_page_size}
              after: $after
              since: $since
              author: {id: $authorId}
            ) {
              nodes {
                oid
                authoredDate
              }
              pageInfo {
                hasNextPage
                endCursor
              }
            }
          }
        }
      }
    }
  }
  """

  def fetch(today, graph_days, window_days) do
    config = Dashboard.github_config()
    username = Map.get(config, :username)
    token = Map.get(config, :token)

    cond do
      blank?(username) or blank?(token) ->
        {:error, :missing_config,
         "Set GITHUB_USERNAME and GITHUB_TOKEN to load live GitHub commits."}

      true ->
        request_counts(config, username, token, today, graph_days, window_days)
    end
  end

  defp request_counts(config, username, token, today, graph_days, window_days) do
    [from | _] = Series.query_dates(graph_days, window_days, today)
    request = request(config, token)

    with {:ok, author_id} <- fetch_user_id(request, username),
         {:ok, repositories} <- fetch_recent_repositories(request, username, from),
         {:ok, counts} <- fetch_commit_counts(request, repositories, author_id, from) do
      {:ok,
       %{
         counts: counts,
         source_label: "Git history",
         status_message: "Live across owned repo branches."
       }}
    end
  end

  defp fetch_user_id(request, username) do
    variables = %{login: username}

    case graphql(request, @user_query, variables) do
      {:ok, %{"user" => %{"id" => author_id}}} when is_binary(author_id) ->
        {:ok, author_id}

      {:ok, %{"user" => nil}} ->
        {:error, :request_failed, "GitHub could not find @#{username}."}

      {:ok, _data} ->
        {:error, :request_failed, "GitHub returned an unexpected user payload."}

      {:error, _reason, _message} = error ->
        error
    end
  end

  defp fetch_recent_repositories(request, username, from) do
    do_fetch_recent_repositories(request, username, from, nil, [])
  end

  defp do_fetch_recent_repositories(request, username, from, cursor, repositories) do
    variables = %{
      login: username,
      after: cursor
    }

    with {:ok, %{"user" => %{"repositories" => repository_connection}}} <-
           graphql(request, @repositories_query, variables) do
      nodes = Map.get(repository_connection, "nodes", [])
      page_info = Map.get(repository_connection, "pageInfo", %{})

      repositories =
        Enum.reduce(nodes, repositories, fn node, acc ->
          if recent_repository?(node, from) do
            case parse_repository(node) do
              {:ok, repository} -> [repository | acc]
              :error -> acc
            end
          else
            acc
          end
        end)

      if Map.get(page_info, "hasNextPage") and not stop_repository_pagination?(nodes, from) do
        do_fetch_recent_repositories(
          request,
          username,
          from,
          Map.get(page_info, "endCursor"),
          repositories
        )
      else
        {:ok, Enum.reverse(repositories)}
      end
    else
      {:ok, %{"user" => nil}} ->
        {:error, :request_failed, "GitHub could not find @#{username}."}

      {:ok, _data} ->
        {:error, :request_failed, "GitHub returned an unexpected repositories payload."}

      {:error, _reason, _message} = error ->
        error
    end
  end

  defp fetch_commit_counts(request, repositories, author_id, from) do
    state = %{counts: %{}, seen_oids: MapSet.new()}

    Enum.reduce_while(repositories, {:ok, state}, fn repository, {:ok, current_state} ->
      case fetch_repository_counts(request, repository, author_id, from, current_state) do
        {:ok, updated_state} -> {:cont, {:ok, updated_state}}
        {:error, _reason, _message} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, %{counts: counts}} -> {:ok, counts}
      {:error, _reason, _message} = error -> error
    end
  end

  defp fetch_repository_counts(request, repository, author_id, from, state, cursor \\ nil) do
    variables = %{
      owner: repository.owner,
      name: repository.name,
      after: cursor
    }

    with {:ok, data} <- graphql(request, @refs_query, variables),
         {:ok, state, page_info} <-
           reduce_branch_refs(request, repository, data, author_id, from, state) do
      if Map.get(page_info, "hasNextPage") do
        fetch_repository_counts(
          request,
          repository,
          author_id,
          from,
          state,
          Map.get(page_info, "endCursor")
        )
      else
        {:ok, state}
      end
    end
  end

  defp reduce_branch_refs(request, repository, data, author_id, from, state) do
    ref_connection = get_in(data, ["repository", "refs"]) || %{}
    nodes = Map.get(ref_connection, "nodes", [])
    page_info = Map.get(ref_connection, "pageInfo", %{})

    Enum.reduce_while(nodes, {:ok, state}, fn node, {:ok, current_state} ->
      case fetch_branch_history(request, repository, node, author_id, from, current_state) do
        {:ok, updated_state} -> {:cont, {:ok, updated_state}}
        {:error, _reason, _message} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, updated_state} -> {:ok, updated_state, page_info}
      {:error, _reason, _message} = error -> error
    end
  end

  defp fetch_branch_history(
         request,
         repository,
         branch_node,
         author_id,
         from,
         state,
         cursor \\ nil
       ) do
    branch_name = Map.get(branch_node, "name")

    if blank?(branch_name) do
      {:ok, state}
    else
      variables = %{
        owner: repository.owner,
        name: repository.name,
        qualifiedName: "refs/heads/#{branch_name}",
        authorId: author_id,
        since: iso8601_start(from),
        after: cursor
      }

      with {:ok, data} <- graphql(request, @history_query, variables),
           {:ok, history_connection} <- parse_history_connection(data) do
        state = accumulate_commits(history_connection["nodes"] || [], state, from)
        page_info = Map.get(history_connection, "pageInfo", %{})

        if Map.get(page_info, "hasNextPage") do
          fetch_branch_history(
            request,
            repository,
            branch_node,
            author_id,
            from,
            state,
            Map.get(page_info, "endCursor")
          )
        else
          {:ok, state}
        end
      end
    end
  end

  defp parse_history_connection(data) do
    case get_in(data, ["repository", "ref", "target"]) do
      nil ->
        {:ok, %{"nodes" => [], "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil}}}

      %{"__typename" => "Commit", "history" => history_connection}
      when is_map(history_connection) ->
        {:ok, history_connection}

      %{"__typename" => _typename} ->
        {:ok, %{"nodes" => [], "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil}}}

      _other ->
        {:error, :request_failed, "GitHub returned an unexpected branch history payload."}
    end
  end

  defp accumulate_commits(nodes, state, from) do
    Enum.reduce(nodes, state, fn node, acc ->
      with oid when is_binary(oid) <- node["oid"],
           false <- MapSet.member?(acc.seen_oids, oid),
           authored_date when is_binary(authored_date) <- node["authoredDate"],
           {:ok, datetime, _offset} <- DateTime.from_iso8601(authored_date),
           date <- DateTime.to_date(datetime),
           comparison when comparison in [:eq, :gt] <- Date.compare(date, from) do
        %{
          acc
          | seen_oids: MapSet.put(acc.seen_oids, oid),
            counts: Map.update(acc.counts, date, 1, &(&1 + 1))
        }
      else
        _ -> acc
      end
    end)
  end

  defp recent_repository?(%{"isArchived" => true}, _from), do: false

  defp recent_repository?(%{"pushedAt" => pushed_at}, from) when is_binary(pushed_at) do
    case DateTime.from_iso8601(pushed_at) do
      {:ok, datetime, _offset} ->
        Date.compare(DateTime.to_date(datetime), from) in [:eq, :gt]

      {:error, _reason} ->
        false
    end
  end

  defp recent_repository?(_node, _from), do: false

  defp stop_repository_pagination?(nodes, from) do
    nodes != [] and Enum.all?(nodes, &repository_older_than_window?(&1, from))
  end

  defp repository_older_than_window?(%{"pushedAt" => pushed_at}, from)
       when is_binary(pushed_at) do
    case DateTime.from_iso8601(pushed_at) do
      {:ok, datetime, _offset} ->
        Date.compare(DateTime.to_date(datetime), from) == :lt

      {:error, _reason} ->
        true
    end
  end

  defp repository_older_than_window?(_node, _from), do: true

  defp parse_repository(%{"nameWithOwner" => name_with_owner}) when is_binary(name_with_owner) do
    case String.split(name_with_owner, "/", parts: 2) do
      [owner, name] when owner != "" and name != "" ->
        {:ok, %{owner: owner, name: name}}

      _other ->
        :error
    end
  end

  defp parse_repository(_node), do: :error

  defp graphql(request, query, variables) do
    case Req.post(request, json: %{query: query, variables: variables}) do
      {:ok, %Req.Response{status: 200, body: %{"errors" => errors}}} ->
        {:error, :request_failed, format_graphql_errors(errors)}

      {:ok, %Req.Response{status: 200, body: %{"data" => data}}} ->
        {:ok, data}

      {:ok, %Req.Response{status: 200, body: body}} ->
        {:error, :request_failed,
         "GitHub returned an unexpected response: #{describe_body(body)}"}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, :request_failed, "GitHub returned HTTP #{status}: #{describe_body(body)}"}

      {:error, error} ->
        {:error, :request_failed, Exception.message(error)}
    end
  end

  defp request(config, token) do
    request_options = Map.get(config, :request_options, [])

    Req.new(
      [
        url: @endpoint,
        headers: [
          {"authorization", "Bearer #{token}"},
          {"user-agent", "EverydayDash"},
          {"accept", "application/json"}
        ],
        receive_timeout: 15_000
      ] ++ request_options
    )
  end

  defp format_graphql_errors(errors) do
    errors
    |> Enum.map_join("; ", fn error -> Map.get(error, "message", "unknown GraphQL error") end)
    |> case do
      "" -> "GitHub returned an unknown GraphQL error."
      message -> message
    end
  end

  defp describe_body(body) when is_binary(body), do: body

  defp describe_body(body) when is_map(body),
    do: Jason.encode_to_iodata!(body) |> IO.iodata_to_binary()

  defp describe_body(body), do: inspect(body)

  defp iso8601_start(date), do: "#{Date.to_iso8601(date)}T00:00:00Z"

  defp blank?(value), do: is_nil(value) or String.trim(value) == ""
end
