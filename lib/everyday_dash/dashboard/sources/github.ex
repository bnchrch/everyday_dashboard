defmodule EverydayDash.Dashboard.Sources.GitHub do
  @moduledoc false

  alias EverydayDash.Dashboard
  alias EverydayDash.Dashboard.Series

  @endpoint "https://api.github.com/graphql"
  @query """
  query DashboardCommitCounts($login: String!, $from: DateTime!, $to: DateTime!) {
    user(login: $login) {
      contributionsCollection(from: $from, to: $to) {
        commitContributionsByRepository(maxRepositories: 100) {
          contributions(first: 100, orderBy: {field: OCCURRED_AT, direction: ASC}) {
            nodes {
              commitCount
              occurredAt
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
        request_counts(username, token, today, graph_days, window_days)
    end
  end

  defp request_counts(username, token, today, graph_days, window_days) do
    [from | _] = Series.query_dates(graph_days, window_days, today)
    to = today

    request =
      Req.new(
        url: @endpoint,
        headers: [
          {"authorization", "Bearer #{token}"},
          {"user-agent", "EverydayDash"},
          {"accept", "application/json"}
        ],
        receive_timeout: 15_000
      )

    variables = %{
      login: username,
      from: iso8601_start(from),
      to: iso8601_finish(to)
    }

    case Req.post(request, json: %{query: @query, variables: variables}) do
      {:ok, %Req.Response{status: 200, body: %{"data" => %{"user" => nil}}}} ->
        {:error, :request_failed, "GitHub could not find @#{username}."}

      {:ok, %Req.Response{status: 200, body: %{"errors" => errors}}} ->
        {:error, :request_failed, format_graphql_errors(errors)}

      {:ok, %Req.Response{status: 200, body: %{"data" => data} = body}} ->
        repositories =
          get_in(data, ["user", "contributionsCollection", "commitContributionsByRepository"]) ||
            []

        counts = parse_counts(repositories)

        status_message =
          case body["errors"] do
            nil -> "Live data"
            errors -> format_graphql_errors(errors)
          end

        {:ok,
         %{
           counts: counts,
           source_label: "Work",
           status_message: status_message
         }}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, :request_failed, "GitHub returned HTTP #{status}: #{describe_body(body)}"}

      {:error, error} ->
        {:error, :request_failed, Exception.message(error)}
    end
  end

  defp parse_counts(repositories) do
    Enum.reduce(repositories, %{}, fn repository, acc ->
      nodes = get_in(repository, ["contributions", "nodes"]) || []

      Enum.reduce(nodes, acc, fn node, counts ->
        with occurred_at when is_binary(occurred_at) <- node["occurredAt"],
             {:ok, datetime, _offset} <- DateTime.from_iso8601(occurred_at),
             commit_count when is_integer(commit_count) <- node["commitCount"] do
          date = DateTime.to_date(datetime)
          Map.update(counts, date, commit_count, &(&1 + commit_count))
        else
          _ -> counts
        end
      end)
    end)
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
  defp iso8601_finish(date), do: "#{Date.to_iso8601(date)}T23:59:59Z"

  defp blank?(value), do: is_nil(value) or String.trim(value) == ""
end
