defmodule EverydayDash.Dashboard.Sources.GitHub do
  @moduledoc false

  alias EverydayDash.Accounts
  alias EverydayDash.Dashboard
  alias EverydayDash.Dashboard.Series

  @query """
  query DashboardCommitCounts($from: DateTime!, $to: DateTime!) {
    viewer {
      id
      login
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

  def authorization_url(state, redirect_uri) do
    config = Dashboard.github_config()
    client_id = Map.get(config, :client_id)

    cond do
      blank?(client_id) ->
        {:error, "GitHub OAuth is not configured."}

      true ->
        params = %{
          "client_id" => client_id,
          "redirect_uri" => redirect_uri,
          "scope" => "read:user",
          "state" => state
        }

        {:ok, "#{Map.get(config, :authorize_url)}?#{URI.encode_query(params)}"}
    end
  end

  def exchange_code(code, redirect_uri) do
    config = Dashboard.github_config()

    with {:ok, client_id} <- fetch_required(config, :client_id, "GitHub OAuth is not configured."),
         {:ok, client_secret} <-
           fetch_required(config, :client_secret, "GitHub OAuth is not configured."),
         {:ok, %Req.Response{status: 200, body: %{"access_token" => access_token} = body}} <-
           Req.post(
             Req.new(
               url: Map.get(config, :token_url),
               headers: [{"accept", "application/json"}],
               receive_timeout: 15_000
             ),
             form: [
               client_id: client_id,
               client_secret: client_secret,
               code: code,
               redirect_uri: redirect_uri
             ]
           ) do
      {:ok, %{access_token: access_token, scope: body["scope"]}}
    else
      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "GitHub authorization failed with HTTP #{status}: #{describe_body(body)}"}

      {:error, error} ->
        {:error, Exception.message(error)}

      {:error, _reason, message} ->
        {:error, message}
    end
  end

  def fetch_profile(access_token) do
    with {:ok, %{"data" => %{"viewer" => viewer}}} <-
           graph_query(access_token, @query, viewer_variables()) do
      {:ok, %{id: viewer["id"], login: viewer["login"]}}
    else
      {:error, message} -> {:error, message}
      _other -> {:error, "GitHub did not return the viewer profile."}
    end
  end

  def fetch(today, graph_days, window_days, integration) do
    with {:ok, credentials} <- Accounts.decrypt_integration_credentials(integration),
         token when is_binary(token) <- Map.get(credentials, "access_token"),
         [from | _] <- Series.query_dates(graph_days, window_days, today),
         {:ok, %{"data" => %{"viewer" => viewer} = _data}} <-
           graph_query(
             token,
             @query,
             %{
               "from" => iso8601_start(from),
               "to" => iso8601_finish(today)
             }
           ) do
      repositories =
        get_in(viewer, ["contributionsCollection", "commitContributionsByRepository"]) || []

      counts = parse_counts(repositories)
      source_label = viewer["login"] || integration.external_username || "GitHub"

      {:ok,
       %{
         counts: counts,
         source_label: source_label,
         status_message: "Live data"
       },
       %{
         external_id: viewer["id"],
         external_username: viewer["login"]
       }}
    else
      nil ->
        {:error, :missing_credentials, "GitHub access is missing.", %{}}

      {:error, message} ->
        {:error, :request_failed, message, %{}}

      _other ->
        {:error, :request_failed, "GitHub returned an unexpected response.", %{}}
    end
  end

  defp graph_query(access_token, query, variables) do
    config = Dashboard.github_config()

    case Req.post(
           Req.new(
             url: Map.get(config, :api_url),
             headers: [
               {"authorization", "Bearer #{access_token}"},
               {"user-agent", "EverydayDash"},
               {"accept", "application/json"}
             ],
             receive_timeout: 15_000
           ),
           json: %{query: query, variables: variables}
         ) do
      {:ok, %Req.Response{status: 200, body: %{"errors" => errors}}} ->
        {:error, format_graphql_errors(errors)}

      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "GitHub returned HTTP #{status}: #{describe_body(body)}"}

      {:error, error} ->
        {:error, Exception.message(error)}
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

  defp viewer_variables do
    %{
      "from" => iso8601_start(Date.utc_today()),
      "to" => iso8601_finish(Date.utc_today())
    }
  end

  defp describe_body(body) when is_binary(body), do: body

  defp describe_body(body) when is_map(body),
    do: Jason.encode_to_iodata!(body) |> IO.iodata_to_binary()

  defp describe_body(body), do: inspect(body)

  defp fetch_required(config, key, message) do
    case Map.get(config, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _missing -> {:error, :missing_config, message}
    end
  end

  defp iso8601_start(date), do: "#{Date.to_iso8601(date)}T00:00:00Z"
  defp iso8601_finish(date), do: "#{Date.to_iso8601(date)}T23:59:59Z"
  defp blank?(value), do: is_nil(value) or String.trim(value) == ""
end
