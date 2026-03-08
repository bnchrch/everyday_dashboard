defmodule EverydayDash.Dashboard.Sources.Strava do
  @moduledoc false

  alias EverydayDash.Dashboard
  alias EverydayDash.Dashboard.Series
  alias EverydayDash.Dashboard.StravaTokenStore

  @oauth_endpoint "https://www.strava.com/oauth/token"
  @activities_endpoint "https://www.strava.com/api/v3/athlete/activities"
  @page_size 200
  @max_pages 10

  def fetch(today, graph_days, window_days) do
    config = Dashboard.strava_config()
    client_id = Map.get(config, :client_id)
    client_secret = Map.get(config, :client_secret)
    configured_refresh_token = Map.get(config, :refresh_token)
    token_store_path = Map.get(config, :token_store_path)

    with {:ok, access_token} <- access_token(config),
         {:ok, activities} <-
           fetch_activities_with_retry(
             access_token,
             today,
             graph_days,
             window_days,
             client_id,
             client_secret,
             configured_refresh_token,
             token_store_path
           ) do
      {:ok, build_payload(activities)}
    end
  end

  defp access_token(config) do
    client_id = Map.get(config, :client_id)
    client_secret = Map.get(config, :client_secret)
    configured_refresh_token = Map.get(config, :refresh_token)

    cond do
      blank?(client_id) or blank?(client_secret) ->
        {:error, :missing_config,
         "Set STRAVA_CLIENT_ID and STRAVA_CLIENT_SECRET to enable live Strava data."}

      true ->
        load_or_refresh_token(client_id, client_secret, configured_refresh_token, config, false)
    end
  end

  defp load_or_refresh_token(
         client_id,
         client_secret,
         configured_refresh_token,
         config,
         force_refresh?
       ) do
    stored_token =
      case StravaTokenStore.load(config) do
        {:ok, token_state} -> token_state
        :missing -> %{}
        {:error, reason} -> raise "could not read Strava token store: #{inspect(reason)}"
      end

    stored_refresh_token =
      Map.get(stored_token, :refresh_token) || Map.get(stored_token, "refresh_token")

    now = System.system_time(:second)

    cond do
      refresh_token_changed?(configured_refresh_token, stored_refresh_token) ->
        refresh_access_token(client_id, client_secret, configured_refresh_token, config)

      valid_access_token?(stored_token, now) and not force_refresh? ->
        {:ok, stored_token.access_token}

      true ->
        refresh_token =
          configured_refresh_token ||
            stored_refresh_token

        if blank?(refresh_token) do
          {:error, :missing_config,
           "Set STRAVA_REFRESH_TOKEN to bootstrap the Strava token refresh flow."}
        else
          refresh_access_token(client_id, client_secret, refresh_token, config)
        end
    end
  end

  defp fetch_activities_with_retry(
         access_token,
         today,
         graph_days,
         window_days,
         client_id,
         client_secret,
         configured_refresh_token,
         config
       ) do
    case fetch_activities(access_token, today, graph_days, window_days) do
      {:ok, activities} ->
        {:ok, activities}

      {:error, :unauthorized, _message} ->
        with {:ok, refreshed_access_token} <-
               load_or_refresh_token(
                 client_id,
                 client_secret,
                 configured_refresh_token,
                 config,
                 true
               ),
             {:ok, activities} <-
               fetch_activities(refreshed_access_token, today, graph_days, window_days) do
          {:ok, activities}
        end

      {:error, reason, message} ->
        {:error, reason, message}
    end
  end

  defp refresh_access_token(client_id, client_secret, refresh_token, config) do
    request =
      Req.new(
        url: @oauth_endpoint,
        headers: [{"accept", "application/json"}],
        receive_timeout: 15_000
      )

    params = [
      client_id: client_id,
      client_secret: client_secret,
      grant_type: "refresh_token",
      refresh_token: refresh_token
    ]

    case Req.post(request, form: params) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        token_state = %{
          access_token: body["access_token"],
          expires_at: body["expires_at"],
          refresh_token: body["refresh_token"]
        }

        case StravaTokenStore.save(config, token_state) do
          :ok ->
            {:ok, token_state.access_token}

          {:error, reason} ->
            {:error, :request_failed, "Could not store Strava token: #{inspect(reason)}"}
        end

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, :request_failed, "Strava auth returned HTTP #{status}: #{describe_body(body)}"}

      {:error, error} ->
        {:error, :request_failed, Exception.message(error)}
    end
  end

  defp fetch_activities(access_token, today, graph_days, window_days) do
    [from | _] = Series.query_dates(graph_days, window_days, today)
    after_timestamp = date_to_unix(from)

    do_fetch_activities(access_token, after_timestamp, 1, [])
  end

  defp do_fetch_activities(_access_token, _after_timestamp, page, activities)
       when page > @max_pages do
    {:ok, activities}
  end

  defp do_fetch_activities(access_token, after_timestamp, page, activities) do
    request =
      Req.new(
        url: @activities_endpoint,
        headers: [
          {"authorization", "Bearer #{access_token}"},
          {"accept", "application/json"}
        ],
        receive_timeout: 15_000
      )

    params = [after: after_timestamp, page: page, per_page: @page_size]

    case Req.get(request, params: params) do
      {:ok, %Req.Response{status: 200, body: page_activities}} when is_list(page_activities) ->
        merged = activities ++ page_activities

        if length(page_activities) < @page_size do
          {:ok, merged}
        else
          do_fetch_activities(access_token, after_timestamp, page + 1, merged)
        end

      {:ok, %Req.Response{status: 401, body: body}} ->
        {:error, :unauthorized, "Strava returned HTTP 401: #{describe_body(body)}"}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, :request_failed, "Strava returned HTTP #{status}: #{describe_body(body)}"}

      {:error, error} ->
        {:error, :request_failed, Exception.message(error)}
    end
  end

  defp extract_date(%{"start_date_local" => <<date::binary-size(10), _rest::binary>>}) do
    Date.from_iso8601(date)
  end

  defp extract_date(%{"start_date" => <<date::binary-size(10), _rest::binary>>}) do
    Date.from_iso8601(date)
  end

  defp extract_date(_activity), do: :error

  defp date_to_unix(date) do
    {:ok, datetime, _offset} = DateTime.from_iso8601("#{Date.to_iso8601(date)}T00:00:00Z")
    DateTime.to_unix(datetime)
  end

  defp valid_access_token?(token_state, now) do
    access_token = Map.get(token_state, :access_token) || Map.get(token_state, "access_token")
    expires_at = Map.get(token_state, :expires_at) || Map.get(token_state, "expires_at")

    is_binary(access_token) and is_integer(expires_at) and expires_at - now > 120
  end

  defp refresh_token_changed?(configured_refresh_token, stored_refresh_token) do
    not blank?(configured_refresh_token) and configured_refresh_token != stored_refresh_token
  end

  defp build_payload(activities) do
    counts =
      Enum.reduce(activities, %{}, fn activity, acc ->
        case extract_date(activity) do
          {:ok, date} -> Map.update(acc, date, 1, &(&1 + 1))
          :error -> acc
        end
      end)

    %{
      counts: counts,
      source_label: "OAuth refresh",
      status_message: "Live data"
    }
  end

  defp describe_body(body) when is_binary(body), do: body

  defp describe_body(body) when is_map(body),
    do: Jason.encode_to_iodata!(body) |> IO.iodata_to_binary()

  defp describe_body(body), do: inspect(body)

  defp blank?(value), do: is_nil(value) or String.trim(to_string(value)) == ""
end
