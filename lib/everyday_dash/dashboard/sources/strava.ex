defmodule EverydayDash.Dashboard.Sources.Strava do
  @moduledoc false

  alias EverydayDash.Accounts
  alias EverydayDash.Credentials
  alias EverydayDash.Dashboard
  alias EverydayDash.Dashboard.Series

  @default_cache_ttl_ms 900_000
  @page_size 200
  @max_pages 10

  def authorization_url(state, redirect_uri) do
    config = Dashboard.strava_config()
    client_id = Map.get(config, :client_id)

    cond do
      blank?(client_id) ->
        {:error, "Strava OAuth is not configured."}

      true ->
        params = %{
          "client_id" => client_id,
          "redirect_uri" => redirect_uri,
          "response_type" => "code",
          "approval_prompt" => "auto",
          "scope" => "activity:read_all",
          "state" => state
        }

        {:ok, "#{Map.get(config, :authorize_url)}?#{URI.encode_query(params)}"}
    end
  end

  def exchange_code(code, redirect_uri) do
    config = Dashboard.strava_config()

    with {:ok, client_id} <- fetch_required(config, :client_id, "Strava OAuth is not configured."),
         {:ok, client_secret} <-
           fetch_required(config, :client_secret, "Strava OAuth is not configured."),
         {:ok, %Req.Response{status: 200, body: body}} <-
           Req.post(
             request(config, Map.get(config, :token_url), [{"accept", "application/json"}]),
             form: [
               client_id: client_id,
               client_secret: client_secret,
               code: code,
               grant_type: "authorization_code",
               redirect_uri: redirect_uri
             ]
           ) do
      {:ok,
       %{
         access_token: body["access_token"],
         refresh_token: body["refresh_token"],
         expires_at: body["expires_at"],
         athlete: body["athlete"] || %{}
       }}
    else
      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "Strava authorization failed with HTTP #{status}: #{describe_body(body)}"}

      {:error, error} ->
        {:error, Exception.message(error)}

      {:error, _reason, message} ->
        {:error, message}
    end
  end

  def fetch(today, graph_days, window_days, integration) do
    config = Dashboard.strava_config()
    cache = load_cache(integration)

    case cached_response(cache, config, graph_days, window_days) do
      {:hit, payload} ->
        {:ok, payload, %{}}

      :miss ->
        fetch_live(config, cache, today, graph_days, window_days, integration)
    end
  end

  defp fetch_live(config, cache, today, graph_days, window_days, integration) do
    with {:ok, credentials} <- Accounts.decrypt_integration_credentials(integration),
         {:ok, access_token, auth_attrs, credentials} <- access_token(credentials, config),
         {:ok, %{activities: activities, rate_limit_headers: rate_limit_headers}, auth_attrs} <-
           fetch_activities_with_retry(
             access_token,
             today,
             graph_days,
             window_days,
             credentials,
             config,
             auth_attrs
           ) do
      counts = activity_counts(activities)
      fetched_at = DateTime.utc_now()

      cache_state = %{
        counts: counts,
        graph_days: graph_days,
        window_days: window_days,
        fetched_at: fetched_at,
        backoff_until: exhausted_backoff_until(rate_limit_headers, fetched_at),
        rate_limit_headers: rate_limit_headers
      }

      {:ok, build_payload(counts, :ok, "Live data", fetched_at),
       auth_attrs
       |> Map.merge(cache_attrs(cache_state))
       |> Map.put(:last_error, nil)}
    else
      {:error, :rate_limited, %{rate_limit_headers: rate_limit_headers, auth_attrs: auth_attrs}} ->
        handle_rate_limited(
          cache,
          config,
          graph_days,
          window_days,
          rate_limit_headers,
          auth_attrs
        )

      {:error, :request_failed, message, auth_attrs} ->
        handle_request_failed(cache, message, auth_attrs)

      {:error, :missing_credentials, message, attrs} ->
        {:error, :missing_credentials, message, attrs}

      {:error, :missing_config, message, attrs} ->
        {:error, :missing_config, message, attrs}
    end
  end

  defp access_token(credentials, config) do
    with {:ok, client_id} <- fetch_required(config, :client_id, "Strava OAuth is not configured."),
         {:ok, client_secret} <-
           fetch_required(config, :client_secret, "Strava OAuth is not configured.") do
      refresh_token = Map.get(credentials, "refresh_token")
      access_token = Map.get(credentials, "access_token")
      expires_at = Map.get(credentials, "expires_at")

      cond do
        blank?(refresh_token) ->
          {:error, :missing_credentials, "Strava credentials are missing.", %{}}

        valid_access_token?(access_token, expires_at) ->
          {:ok, access_token, %{}, credentials}

        true ->
          refresh_access_token(client_id, client_secret, refresh_token, config)
      end
    else
      {:error, _reason, message} ->
        {:error, :missing_config, message, %{}}
    end
  end

  defp fetch_activities_with_retry(
         access_token,
         today,
         graph_days,
         window_days,
         credentials,
         config,
         auth_attrs
       ) do
    case fetch_activities(access_token, today, graph_days, window_days, config) do
      {:ok, result} ->
        {:ok, result, auth_attrs}

      {:error, :unauthorized, _message} ->
        with {:ok, client_id} <-
               fetch_required(config, :client_id, "Strava OAuth is not configured."),
             {:ok, client_secret} <-
               fetch_required(config, :client_secret, "Strava OAuth is not configured."),
             {:ok, refreshed_access_token, refreshed_attrs, _credentials} <-
               refresh_access_token(
                 client_id,
                 client_secret,
                 Map.get(credentials, "refresh_token"),
                 config
               ),
             {:ok, result} <-
               fetch_activities(refreshed_access_token, today, graph_days, window_days, config) do
          {:ok, result, Map.merge(auth_attrs, refreshed_attrs)}
        else
          {:error, _reason, message} ->
            {:error, :request_failed, message, auth_attrs}
        end

      {:error, :rate_limited, %{rate_limit_headers: rate_limit_headers}} ->
        {:error, :rate_limited, %{rate_limit_headers: rate_limit_headers, auth_attrs: auth_attrs}}

      {:error, :request_failed, message} ->
        {:error, :request_failed, message, auth_attrs}
    end
  end

  defp refresh_access_token(client_id, client_secret, refresh_token, config) do
    request =
      request(config, Map.get(config, :token_url), [{"accept", "application/json"}])

    params = [
      client_id: client_id,
      client_secret: client_secret,
      grant_type: "refresh_token",
      refresh_token: refresh_token
    ]

    case Req.post(request, form: params) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        credentials = %{
          "access_token" => body["access_token"],
          "refresh_token" => body["refresh_token"],
          "expires_at" => body["expires_at"]
        }

        {:ok, ciphertext} = Credentials.encrypt(credentials)

        {:ok, body["access_token"],
         %{
           credential_ciphertext: ciphertext,
           token_expires_at: unix_to_datetime(body["expires_at"])
         }, credentials}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, :request_failed,
         "Strava authentication failed with HTTP #{status}: #{describe_body(body)}"}

      {:error, error} ->
        {:error, :request_failed, Exception.message(error)}
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
      request(config, Map.get(config, :activities_url), [
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

      {:ok, %Req.Response{status: 401}} ->
        {:error, :unauthorized, "Strava rejected the cached access token."}

      {:ok, %Req.Response{status: 429, headers: headers}} ->
        {:error, :rate_limited, %{rate_limit_headers: extract_rate_limit_headers(headers)}}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, :request_failed, "Strava returned HTTP #{status}: #{describe_body(body)}"}

      {:error, error} ->
        {:error, :request_failed, Exception.message(error)}
    end
  end

  defp load_cache(integration) do
    integration
    |> Map.get(:cache_payload, %{})
    |> deserialize_cache()
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

  defp handle_rate_limited(
         cache,
         _config,
         graph_days,
         window_days,
         rate_limit_headers,
         auth_attrs
       ) do
    backoff_until = rate_limit_backoff_until(rate_limit_headers, DateTime.utc_now())

    if cache_matches_window?(cache, graph_days, window_days) do
      refreshed_cache =
        cache
        |> Map.put(:backoff_until, backoff_until)
        |> Map.put(:rate_limit_headers, rate_limit_headers)

      {:ok,
       cached_payload(
         refreshed_cache,
         :stale,
         "Using cached Strava data while the rate limit resets."
       ),
       auth_attrs
       |> Map.merge(cache_attrs(refreshed_cache))
       |> Map.put(:last_error, "Using cached Strava data while the rate limit resets.")}
    else
      {:error, :request_failed,
       "Strava is rate limited right now. The dashboard will retry after the current window resets.",
       auth_attrs}
    end
  end

  defp handle_request_failed(cache, message, auth_attrs) do
    if is_map(cache) do
      {:ok,
       cached_payload(
         cache,
         :stale,
         "Using cached Strava data while Strava is temporarily unavailable."
       ), Map.put(auth_attrs, :last_error, message)}
    else
      {:error, :request_failed, message, auth_attrs}
    end
  end

  defp cached_payload(cache, status, message) do
    build_payload(cache.counts, status, message, cache.fetched_at)
  end

  defp build_payload(counts, status, status_message, fetched_at) do
    %{
      counts: counts,
      source_label: "Strava",
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

  defp cache_attrs(cache_state) do
    %{
      cache_payload: serialize_cache(cache_state),
      backoff_until: cache_state.backoff_until,
      rate_limit_headers: cache_state.rate_limit_headers
    }
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
    %{
      "counts" => serialize_counts(cache_state.counts),
      "graph_days" => cache_state.graph_days,
      "window_days" => cache_state.window_days,
      "fetched_at" => dump_datetime(cache_state.fetched_at),
      "backoff_until" => dump_datetime(cache_state.backoff_until),
      "rate_limit_headers" => cache_state.rate_limit_headers
    }
  end

  defp deserialize_cache(%{} = cache_state) when map_size(cache_state) == 0, do: nil

  defp deserialize_cache(cache_state) do
    %{
      counts: deserialize_counts(Map.get(cache_state, "counts", %{})),
      graph_days: Map.get(cache_state, "graph_days"),
      window_days: Map.get(cache_state, "window_days"),
      fetched_at: load_datetime(Map.get(cache_state, "fetched_at")),
      backoff_until: load_datetime(Map.get(cache_state, "backoff_until")),
      rate_limit_headers: Map.get(cache_state, "rate_limit_headers", %{})
    }
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
    now
    |> DateTime.truncate(:second)
    |> DateTime.add(1, :day)
    |> DateTime.to_date()
    |> DateTime.new!(~T[00:00:00], "Etc/UTC")
  end

  defp extract_date(%{"start_date_local" => local_date}) when is_binary(local_date) do
    with {:ok, datetime, _offset} <- DateTime.from_iso8601(local_date) do
      {:ok, DateTime.to_date(datetime)}
    else
      _ -> :error
    end
  end

  defp extract_date(_activity), do: :error

  defp date_to_unix(date) do
    date
    |> DateTime.new!(~T[00:00:00], "Etc/UTC")
    |> DateTime.to_unix()
  end

  defp unix_to_datetime(nil), do: nil
  defp unix_to_datetime(unix) when is_integer(unix), do: DateTime.from_unix!(unix)

  defp valid_access_token?(access_token, expires_at) when is_binary(access_token) do
    case expires_at do
      unix when is_integer(unix) -> unix - 60 > System.system_time(:second)
      _other -> true
    end
  end

  defp valid_access_token?(_access_token, _expires_at), do: false

  defp dump_datetime(nil), do: nil
  defp dump_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp load_datetime(nil), do: nil

  defp load_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp fetch_required(config, key, message) do
    case Map.get(config, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _missing -> {:error, :missing_config, message}
    end
  end

  defp describe_body(body) when is_binary(body), do: body

  defp describe_body(body) when is_map(body),
    do: Jason.encode_to_iodata!(body) |> IO.iodata_to_binary()

  defp describe_body(body), do: inspect(body)
  defp blank?(value), do: is_nil(value) or String.trim(to_string(value)) == ""
end
