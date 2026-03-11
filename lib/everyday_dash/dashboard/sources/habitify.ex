defmodule EverydayDash.Dashboard.Sources.Habitify do
  @moduledoc false

  alias EverydayDash.Accounts
  alias EverydayDash.Dashboard
  alias EverydayDash.Dashboard.HabitifyHistory
  alias EverydayDash.Dashboard.Series

  def verify_api_key(api_key) when is_binary(api_key) do
    case get(api_key, "/habits") do
      {:ok, habits} when is_list(habits) -> {:ok, Enum.reject(habits, &archived?/1)}
      {:ok, _payload} -> {:error, "Habitify returned an invalid habits payload."}
      {:error, _reason, message} -> {:error, message}
    end
  end

  def fetch(today, graph_days, integration) when graph_days > 0 do
    with {:ok, credentials} <- Accounts.decrypt_integration_credentials(integration),
         api_key when is_binary(api_key) <- Map.get(credentials, "api_key"),
         {:ok, habits} <- fetch_habits(api_key),
         {:ok, cards} <- fetch_cards(habits, today, graph_days, api_key) do
      {:ok,
       %{cards: cards, status: :ok, status_message: "Live data", updated_at: DateTime.utc_now()},
       %{
         external_username: integration.external_username || "Habitify"
       }}
    else
      nil ->
        {:error, :missing_credentials, "Habitify API key is missing.", %{}}

      {:error, _reason, _message} = error ->
        normalize_error(error)
    end
  end

  defp fetch_habits(api_key) do
    with {:ok, habits} when is_list(habits) <- get(api_key, "/habits") do
      {:ok, Enum.reject(habits, &archived?/1)}
    else
      {:ok, _payload} ->
        {:error, :request_failed, "Habitify returned an invalid habits payload."}

      {:error, _reason, _message} = error ->
        error
    end
  end

  defp fetch_cards(habits, today, graph_days, api_key) do
    habits
    |> Task.async_stream(
      &build_card(&1, graph_days, today, api_key),
      max_concurrency: max_concurrency(habits),
      ordered: true,
      timeout: :infinity
    )
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, {:ok, card}}, {:ok, cards} ->
        {:cont, {:ok, [card | cards]}}

      {:ok, {:error, reason, message}}, _acc ->
        {:halt, {:error, reason, message}}

      {:exit, reason}, _acc ->
        {:halt, {:error, :request_failed, "Habitify logs fetch exited: #{inspect(reason)}"}}
    end)
    |> case do
      {:ok, cards} -> {:ok, Enum.reverse(cards)}
      {:error, _reason, _message} = error -> error
    end
  end

  defp build_card(habit, graph_days, today, api_key) do
    with {:ok, logged_values_by_date} <- fetch_logged_values(habit, graph_days, today, api_key) do
      history =
        HabitifyHistory.build(
          logged_values_by_date,
          goal_target(habit["goal"]),
          graph_days,
          today
        )

      {:ok,
       %{
         completed_days: history.completed_days,
         goal_label: goal_label(habit["goal"]),
         id: habit["id"],
         name: habit["name"] || "Untitled habit",
         series: history.series,
         today_status: history.today_status,
         total_days: history.total_days
       }}
    end
  end

  defp fetch_logged_values(habit, graph_days, today, api_key) do
    dates = Series.display_dates(graph_days, today)
    habit_id = habit["id"]
    from = format_target_date(hd(dates))
    to = format_range_end(List.last(dates))

    with {:ok, logs} when is_list(logs) <-
           get(api_key, "/logs/#{habit_id}", params: [from: from, to: to]) do
      {:ok, aggregate_logs_by_date(logs)}
    else
      {:ok, _payload} ->
        {:error, :request_failed, "Habitify returned an invalid logs payload."}

      {:error, _reason, _message} = error ->
        error
    end
  end

  defp get(api_key, path, options \\ []) do
    config = Dashboard.habitify_config()

    request =
      Req.new(
        Keyword.merge(
          [
            url: base_url(config) <> path,
            headers: [
              {"authorization", api_key},
              {"accept", "application/json"},
              {"user-agent", "EverydayDash"}
            ],
            receive_timeout: 15_000
          ],
          Map.get(config, :request_options, [])
        )
      )

    params = Keyword.get(options, :params, [])

    case Req.get(request, params: params) do
      {:ok, %Req.Response{status: 200, body: %{"status" => true, "data" => data}}} ->
        {:ok, data}

      {:ok, %Req.Response{status: 200, body: %{"status" => false} = body}} ->
        {:error, :request_failed, Map.get(body, "message", "Habitify returned an error.")}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, :request_failed, "Habitify returned HTTP #{status}: #{describe_body(body)}"}

      {:error, error} ->
        {:error, :request_failed, Exception.message(error)}
    end
  end

  defp archived?(habit), do: Map.get(habit, "is_archived", false) == true

  defp goal_label(goal) when is_map(goal) do
    [
      format_goal_value(Map.get(goal, "value")),
      Map.get(goal, "unit_type"),
      Map.get(goal, "periodicity")
    ]
    |> Enum.reject(&blank?/1)
    |> Enum.join(" ")
    |> case do
      "" -> "Goal not set"
      label -> label
    end
  end

  defp goal_label(_goal), do: "Goal not set"

  defp goal_target(goal) when is_map(goal) do
    goal
    |> Map.get("value")
    |> parse_numeric()
  end

  defp goal_target(_goal), do: nil

  defp format_goal_value(value) when is_integer(value), do: Integer.to_string(value)

  defp format_goal_value(value) when is_float(value) do
    if value == Float.floor(value) do
      value |> trunc() |> Integer.to_string()
    else
      :erlang.float_to_binary(value, decimals: 1)
    end
  end

  defp format_goal_value(value) when is_binary(value), do: value
  defp format_goal_value(_value), do: nil

  defp describe_body(body) when is_binary(body), do: body

  defp describe_body(body) when is_map(body),
    do: Jason.encode_to_iodata!(body) |> IO.iodata_to_binary()

  defp describe_body(body), do: inspect(body)

  def format_target_date(date) do
    format_datetime(date, {0, 0, 0})
  end

  defp format_range_end(date) do
    format_datetime(date, {23, 59, 59})
  end

  defp format_datetime(date, {hour, minute, second}) do
    local_datetime = {{date.year, date.month, date.day}, {hour, minute, second}}

    offset_seconds =
      case :calendar.local_time_to_universal_time_dst(local_datetime) do
        [utc_datetime | _rest] ->
          :calendar.datetime_to_gregorian_seconds(local_datetime) -
            :calendar.datetime_to_gregorian_seconds(utc_datetime)

        [] ->
          0
      end

    "#{Date.to_iso8601(date)}T#{pad2(hour)}:#{pad2(minute)}:#{pad2(second)}#{format_utc_offset(offset_seconds)}"
  end

  defp aggregate_logs_by_date(logs) do
    Enum.reduce(logs, %{}, fn log, acc ->
      with {:ok, date} <- extract_log_date(log),
           value when is_number(value) <- parse_numeric(Map.get(log, "value")) do
        Map.update(acc, date, value, &(&1 + value))
      else
        _ -> acc
      end
    end)
  end

  defp extract_log_date(%{"created_date" => created_date}) when is_binary(created_date) do
    with {:ok, datetime, _offset} <- DateTime.from_iso8601(created_date) do
      local_datetime =
        datetime
        |> DateTime.to_naive()
        |> NaiveDateTime.to_erl()
        |> :calendar.universal_time_to_local_time()

      {{year, month, day}, _time} = local_datetime
      Date.new(year, month, day)
    end
  end

  defp extract_log_date(_log), do: :error

  defp parse_numeric(value) when is_integer(value), do: value * 1.0
  defp parse_numeric(value) when is_float(value), do: value

  defp parse_numeric(value) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp parse_numeric(_value), do: nil

  defp max_concurrency(habits) do
    habits
    |> length()
    |> min(System.schedulers_online() * 2)
    |> max(1)
  end

  defp normalize_error({:error, reason, message}), do: {:error, reason, message, %{}}

  defp base_url(config), do: Map.get(config, :base_url, "https://api.habitify.me")

  defp format_utc_offset(offset_seconds) do
    sign = if offset_seconds < 0, do: "-", else: "+"
    absolute_offset = abs(offset_seconds)
    hours = div(absolute_offset, 3_600)
    minutes = div(rem(absolute_offset, 3_600), 60)

    "#{sign}#{pad2(hours)}:#{pad2(minutes)}"
  end

  defp pad2(value) do
    value
    |> Integer.to_string()
    |> String.pad_leading(2, "0")
  end

  defp blank?(value), do: is_nil(value) or String.trim(to_string(value)) == ""
end
