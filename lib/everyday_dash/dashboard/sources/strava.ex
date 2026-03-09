defmodule EverydayDash.Dashboard.Sources.Strava do
  @moduledoc false

  alias EverydayDash.Dashboard
  alias EverydayDash.Dashboard.Series
  alias EverydayDash.Dashboard.StravaCacheStore
  alias EverydayDash.Dashboard.StravaTokenStore
  require Logger

  @oauth_endpoint "https://www.strava.com/oauth/token"
  @activities_endpoint "https://www.strava.com/api/v3/athlete/activities"
  @cache_service "strava_activities"
  @default_cache_ttl_ms 900_000
  @page_size 200
  @max_pages 10

  def fetch(today, graph_days, window_days) do
    config = Dashboard.strava_config()
    cache = load_cache(config)

    case cached_response(cache, config, graph_days, window_days) do
      {:hit, payload} ->
        {:ok, payload}

      :miss ->
        fetch_live(config, cache, today, graph_days, window_days)
    end
  end

  defp fetch_live(config, cache, today, graph_days, window_days) do
    client_id = Map.get(config, :client_id)
    client_secret = Map.get(config, :client_secret)
    configured_refresh_token = Map.get(config, :refresh_token)

    with {:ok, access_token} <- access_token(config),
         {:ok, %{activities: activities, rate_limit_headers: rate_limit_headers}} <-
           fetch_activities_with_retry(
             access_token,
             today,
             graph_days,
             window_days,
             client_id,
             client_secret,
             configured_refresh_token,
             config
           ) do
      counts = activity_counts(activities)
      fetched_at = DateTime.utc_now()

      cache_state = %{
        service: @cache_service,
        counts: serialize_counts(counts),
        graph_days: graph_days,
        window_days: window_days,
        fetched_at: fetched_at,
        backoff_until: exhausted_backoff_until(rate_limit_headers, fetched_at),
        rate_limit_headers: rate_limit_headers
      }

      persist_cache(cache_state, config)

      {:ok, build_payload(counts, :ok, "Live data", fetched_at)}
    else
      {:error, :missing_config, message} ->
        {:error, :missing_config, message}

      {:error, :rate_limited, %{rate_limit_headers: rate_limit_headers}} ->
        handle_rate_limited(cache, config, graph_days, window_days, rate_limit_headers)

      {:error, :request_failed, _message} ->
        handle_request_failed(cache)
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
    with {:ok, stored_token} <- load_stored_token(config) do
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
  end

  defp load_stored_token(config) do
    case StravaTokenStore.load(config) do
      {:ok, token_state} ->
        {:ok, token_state}

      :missing ->
        {:ok, %{}}

      {:error, reason} ->
        Logger.warning("Could not read the Strava token store: #{inspect(reason)}")
        {:error, :request_failed, "Strava authentication is temporarily unavailable."}
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
    case fetch_activities(access_token, today, graph_days, window_days, config) do
      {:ok, result} ->
        {:ok, result}

      {:error, :unauthorized, _message} ->
        with {:ok, refreshed_access_token} <-
               load_or_refresh_token(
                 client_id,
                 client_secret,
                 configured_refresh_token,
                 config,
                 true
               ),
             {:ok, result} <-
               fetch_activities(refreshed_access_token, today, graph_days, window_days, config) do
          {:ok, result}
        end

      {:error, reason, message} ->
        {:error, reason, message}
    end
  end

  defp refresh_access_token(client_id, client_secret, refresh_token, config) do
    request = request(config, oauth_endpoint(config), [{"accept", "application/json"}])

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
            Logger.warning("Could not store the Strava token: #{inspect(reason)}")
            {:error, :request_failed, "Strava authentication is temporarily unavailable."}
        end

      {:ok, %Req.Response{status: status, body: body, headers: headers}} ->
        log_api_failure("Strava auth", status, body, headers)

        {:error, :request_failed,
         "Strava authentication failed. The dashboard will retry automatically."}

      {:error, error} ->
        Logger.warning("Strava auth transport error: #{Exception.message(error)}")
        {:error, :request_failed, "Strava authentication is temporarily unavailable."}
    end
  end

  defp fetch_activities(access_token, today, graph_days, window_days, config) do
    [from | _] = Series.query_dates(graph_days, window_days, today)
    after_timestamp = date_to_unix(from)

    do_fetch_activities(access_token, after_timestamp, 1, [], %{}, config)
  end

  defp do_fetch_activities(
         _access_token,
         _after_timestamp,
         page,
         activities,
         rate_limit_headers,
         _config
       )
       when page > @max_pages do
    {:ok, %{activities: activities, rate_limit_headers: rate_limit_headers}}
  end

  defp do_fetch_activities(access_token, after_timestamp, page, activities, _headers, config) do
    request =
      request(config, activities_endpoint(config), [
        {"authorization", "Bearer #{access_token}"},
        {"accept", "application/json"}
      ])

    params = [after: after_timestamp, page: page, per_page: @page_size]

    case Req.get(request, params: params) do
      {:ok, %Req.Response{status: 200, body: page_activities, headers: headers}}
      when is_list(page_activities) ->
        merged = activities ++ page_activities
        rate_limit_headers = extract_rate_limit_headers(headers)

        if length(page_activities) < @page_size do
          {:ok, %{activities: merged, rate_limit_headers: rate_limit_headers}}
        else
          do_fetch_activities(
            access_token,
            after_timestamp,
            page + 1,
            merged,
            rate_limit_headers,
            config
          )
        end

      {:ok, %Req.Response{status: 401, body: body, headers: headers}} ->
        log_api_failure("Strava activities", 401, body, headers)
        {:error, :unauthorized, "Strava rejected the cached access token."}

      {:ok, %Req.Response{status: 429, body: body, headers: headers}} ->
        rate_limit_headers = extract_rate_limit_headers(headers)
        log_api_failure("Strava activities", 429, body, headers)
        {:error, :rate_limited, %{rate_limit_headers: rate_limit_headers}}

      {:ok, %Req.Response{status: status, body: body, headers: headers}} ->
        log_api_failure("Strava activities", status, body, headers)
        {:error, :request_failed, "Strava is temporarily unavailable."}

      {:error, error} ->
        Logger.warning("Strava activities transport error: #{Exception.message(error)}")
        {:error, :request_failed, "Strava is temporarily unavailable."}
    end
  end

  defp load_cache(config) do
    case StravaCacheStore.load(config, @cache_service) do
      {:ok, cache_state} ->
        deserialize_cache(cache_state)

      :missing ->
        nil

      {:error, :repo_unavailable} ->
        nil

      {:error, reason} ->
        Logger.warning("Could not read the Strava cache store: #{inspect(reason)}")
        nil
    end
  end

  defp cached_response(nil, _config, _graph_days, _window_days), do: :miss

  defp cached_response(cache, config, graph_days, window_days) do
    cond do
      not cache_matches_window?(cache, graph_days, window_days) ->
        :miss

      backoff_active?(cache) ->
        {:hit,
         cached_payload(cache, :stale, "Using cached Strava data while the rate limit resets.")}

      cache_fresh?(cache, config) ->
        {:hit, cached_payload(cache, :ok, "Recently synced from Strava.")}

      true ->
        :miss
    end
  end

  defp handle_rate_limited(cache, config, graph_days, window_days, rate_limit_headers) do
    backoff_until = rate_limit_backoff_until(rate_limit_headers, DateTime.utc_now())

    if cache_matches_window?(cache, graph_days, window_days) do
      cache
      |> Map.put(:backoff_until, backoff_until)
      |> Map.put(:rate_limit_headers, rate_limit_headers)
      |> serialize_cache()
      |> persist_cache(config)

      {:ok,
       cached_payload(cache, :stale, "Using cached Strava data while the rate limit resets.")}
    else
      {:error, :request_failed,
       "Strava is rate limited right now. The dashboard will retry after the current window resets."}
    end
  end

  defp handle_request_failed(cache) do
    if is_map(cache) do
      {:ok,
       cached_payload(
         cache,
         :stale,
         "Using cached Strava data while Strava is temporarily unavailable."
       )}
    else
      {:error, :request_failed,
       "Strava is temporarily unavailable. The dashboard will retry automatically."}
    end
  end

  defp cached_payload(cache, status, message) do
    build_payload(cache.counts, status, message, cache.fetched_at)
  end

  defp build_payload(counts, status, status_message, fetched_at) do
    %{
      counts: counts,
      source_label: "Play",
      status: status,
      status_message: status_message,
      updated_at: fetched_at
    }
  end

  defp activity_counts(activities) do
    Enum.reduce(activities, %{}, fn activity, acc ->
      case extract_date(activity) do
        {:ok, date} -> Map.update(acc, date, 1, &(&1 + 1))
        :error -> acc
      end
    end)
  end

  defp persist_cache(cache_state, config) when is_map(cache_state) do
    case StravaCacheStore.save(config, cache_state) do
      :ok -> :ok
      {:error, :repo_unavailable} -> :ok
      {:error, reason} -> Logger.warning("Could not persist Strava cache: #{inspect(reason)}")
    end
  end

  defp cache_matches_window?(
         %{graph_days: graph_days, window_days: window_days},
         graph_days,
         window_days
       ),
       do: true

  defp cache_matches_window?(_cache, _graph_days, _window_days), do: false

  defp cache_fresh?(%{fetched_at: %DateTime{} = fetched_at}, config) do
    DateTime.diff(DateTime.utc_now(), fetched_at, :second) * 1_000 < cache_ttl_ms(config)
  end

  defp cache_fresh?(_cache, _config), do: false

  defp backoff_active?(%{backoff_until: %DateTime{} = backoff_until}) do
    DateTime.compare(backoff_until, DateTime.utc_now()) == :gt
  end

  defp backoff_active?(_cache), do: false

  defp serialize_cache(cache_state) do
    %{cache_state | counts: serialize_counts(cache_state.counts)}
  end

  defp deserialize_cache(cache_state) do
    %{cache_state | counts: deserialize_counts(Map.get(cache_state, :counts, %{}))}
  end

  defp serialize_counts(counts) do
    Map.new(counts, fn {date, value} -> {Date.to_iso8601(date), value} end)
  end

  defp deserialize_counts(counts) do
    Enum.reduce(counts, %{}, fn {date, value}, acc ->
      case Date.from_iso8601(date) do
        {:ok, parsed_date} -> Map.put(acc, parsed_date, value)
        {:error, _reason} -> acc
      end
    end)
  end

  defp cache_ttl_ms(config) do
    Map.get(config, :cache_ttl_ms, @default_cache_ttl_ms)
  end

  defp request(config, url, headers) do
    Req.new(
      Keyword.merge(
        [url: url, headers: headers, receive_timeout: 15_000],
        Map.get(config, :request_options, [])
      )
    )
  end

  defp oauth_endpoint(config), do: Map.get(config, :oauth_endpoint, @oauth_endpoint)

  defp activities_endpoint(config),
    do: Map.get(config, :activities_endpoint, @activities_endpoint)

  defp exhausted_backoff_until(rate_limit_headers, now) do
    case exhausted_window(rate_limit_headers) do
      :daily -> next_midnight_utc(now)
      :short -> next_quarter_hour(now)
      _window -> nil
    end
  end

  defp rate_limit_backoff_until(rate_limit_headers, now) do
    case exhausted_backoff_until(rate_limit_headers, now) do
      nil -> next_quarter_hour(now)
      backoff_until -> backoff_until
    end
  end

  defp exhausted_window(rate_limit_headers) do
    limit = rate_pair(rate_limit_headers["limit"])
    usage = rate_pair(rate_limit_headers["usage"])

    cond do
      exhausted?(usage, limit, 1) -> :daily
      exhausted?(usage, limit, 0) -> :short
      true -> nil
    end
  end

  defp exhausted?(usage, limit, index) do
    case {Enum.at(usage, index), Enum.at(limit, index)} do
      {usage_value, limit_value} when is_integer(usage_value) and is_integer(limit_value) ->
        usage_value >= limit_value

      _other ->
        false
    end
  end

  defp rate_pair(nil), do: []

  defp rate_pair(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(&Integer.parse/1)
    |> Enum.flat_map(fn
      {integer, ""} -> [integer]
      _other -> []
    end)
  end

  defp extract_rate_limit_headers(headers) do
    limit =
      header_value(headers, "x-readratelimit-limit") || header_value(headers, "x-ratelimit-limit")

    usage =
      header_value(headers, "x-readratelimit-usage") || header_value(headers, "x-ratelimit-usage")

    %{}
    |> maybe_put("limit", limit)
    |> maybe_put("usage", usage)
  end

  defp header_value(headers, expected_name) do
    Enum.find_value(headers, fn {name, value} ->
      if String.downcase(name) == expected_name, do: normalize_header_value(value)
    end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp normalize_header_value([value | _rest]) when is_binary(value), do: value
  defp normalize_header_value(value) when is_binary(value), do: value
  defp normalize_header_value(_value), do: nil

  defp next_quarter_hour(now) do
    delta_minutes =
      case rem(now.minute, 15) do
        0 -> 15
        remainder -> 15 - remainder
      end

    now
    |> DateTime.truncate(:second)
    |> DateTime.add(-now.second, :second)
    |> DateTime.add(delta_minutes * 60, :second)
  end

  defp next_midnight_utc(now) do
    tomorrow = now |> DateTime.to_date() |> Date.add(1)
    DateTime.from_naive!(NaiveDateTime.new!(tomorrow, ~T[00:00:00]), "Etc/UTC")
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

  defp log_api_failure(label, status, body, headers) do
    Logger.warning(
      "#{label} failed with HTTP #{status} limit_headers=#{inspect(extract_rate_limit_headers(headers))} body=#{truncate(describe_body(body), 400)}"
    )
  end

  defp truncate(value, max_bytes) do
    if byte_size(value) > max_bytes do
      binary_part(value, 0, max_bytes) <> "..."
    else
      value
    end
  end

  defp describe_body(body) when is_binary(body), do: body

  defp describe_body(body) when is_map(body),
    do: Jason.encode_to_iodata!(body) |> IO.iodata_to_binary()

  defp describe_body(body), do: inspect(body)

  defp blank?(value), do: is_nil(value) or String.trim(to_string(value)) == ""
end
