defmodule EverydayDash.Dashboard.Loader do
  @moduledoc false

  alias EverydayDash.Accounts.User
  alias EverydayDash.Accounts.UserIntegration
  alias EverydayDash.Dashboard
  alias EverydayDash.Dashboard.Series
  alias EverydayDash.Dashboard.Sources.{GitHub, Habitify, Strava}

  @metric_specs [
    %{
      provider: :github,
      id: :github_commits,
      label: "GitHub commits",
      description:
        "Daily commit volume from your GitHub account, displayed as a rolling 7-day average.",
      accent: "embers",
      unit: "commits/day",
      source: GitHub,
      source_label: "GitHub"
    },
    %{
      provider: :strava,
      id: :strava_activities,
      label: "Strava activities",
      description:
        "Daily Strava activity count over the last month, smoothed with the same trailing window.",
      accent: "pine",
      unit: "activities/day",
      source: Strava,
      source_label: "Strava"
    }
  ]

  def initial_snapshot do
    today = Dashboard.today()
    now = now()

    %{
      generated_at: now,
      updated_at: nil,
      refreshing?: false,
      range_label: range_label(today),
      metrics: [],
      habitify: hidden_habitify()
    }
  end

  def fetch(%User{} = _user, integrations, previous_snapshot \\ nil) do
    today = Dashboard.today()
    now = now()
    integration_map = Map.new(integrations, &{&1.provider, &1})
    previous_metrics = previous_metric_map(previous_snapshot)
    previous_habitify = previous_habitify(previous_snapshot)

    {metrics, integration_updates} =
      Enum.reduce(@metric_specs, {[], []}, fn spec, {metrics, updates} ->
        case Map.get(integration_map, spec.provider) do
          %UserIntegration{status: :disconnected} ->
            {metrics, updates}

          nil ->
            {metrics, updates}

          integration ->
            {metric, attrs} =
              load_metric(spec, integration, today, Map.get(previous_metrics, spec.id))

            {metrics ++ [metric], [{spec.provider, attrs} | updates]}
        end
      end)

    {habitify, habitify_updates} =
      load_habitify(Map.get(integration_map, :habitify), today, previous_habitify)

    {:ok,
     %{
       generated_at: now,
       updated_at: now,
       refreshing?: false,
       range_label: range_label(today),
       metrics: metrics,
       habitify: habitify
     }, Enum.reverse(habitify_updates ++ integration_updates)}
  end

  def mark_refresh_failed(snapshot, reason) do
    message = "Refresh failed: #{Exception.message(reason)}"

    metrics =
      Enum.map(snapshot.metrics, fn metric ->
        if metric.status in [:ok, :stale] do
          %{metric | status: :stale, status_message: message}
        else
          %{metric | status: :error, status_message: message}
        end
      end)

    %{
      snapshot
      | refreshing?: false,
        metrics: metrics,
        habitify: mark_habitify_failed(snapshot.habitify, message)
    }
  end

  defp load_metric(spec, integration, today, previous_metric) do
    case spec.source.fetch(
           today,
           Dashboard.graph_days(),
           Dashboard.average_window_days(),
           integration
         ) do
      {:ok, %{counts: counts} = payload, attrs} ->
        {build_loaded_metric(spec, counts, payload, today), connected_attrs(attrs)}

      {:error, _reason, message, attrs} ->
        {fallback_metric(spec, today, previous_metric, message), error_attrs(attrs, message)}
    end
  rescue
    error ->
      {fallback_metric(spec, today, previous_metric, Exception.message(error)),
       error_attrs(%{}, Exception.message(error))}
  end

  defp load_habitify(nil, _today, _previous_habitify), do: {hidden_habitify(), []}

  defp load_habitify(%UserIntegration{status: :disconnected}, _today, _previous_habitify),
    do: {hidden_habitify(), []}

  defp load_habitify(integration, today, previous_habitify) do
    case Habitify.fetch(today, Dashboard.graph_days(), integration) do
      {:ok, %{cards: cards} = payload, attrs} ->
        {%{
           hidden?: false,
           cards: cards,
           status: Map.get(payload, :status, :ok),
           status_message: Map.get(payload, :status_message, "Live data"),
           updated_at: Map.get(payload, :updated_at, now())
         }, [{:habitify, connected_attrs(attrs)}]}

      {:error, _reason, message, attrs} ->
        {fallback_habitify(previous_habitify, message),
         [{:habitify, error_attrs(attrs, message)}]}
    end
  rescue
    error ->
      message = Exception.message(error)
      {fallback_habitify(previous_habitify, message), [{:habitify, error_attrs(%{}, message)}]}
  end

  defp build_loaded_metric(spec, counts, payload, today) do
    series = Series.build(counts, Dashboard.graph_days(), Dashboard.average_window_days(), today)
    average_series = series.average
    raw_series = series.raw
    status = Map.get(payload, :status, :ok)

    current_average =
      average_series
      |> List.last(%{value: 0.0})
      |> Map.fetch!(:value)

    today_count =
      raw_series
      |> List.last(%{value: 0})
      |> Map.fetch!(:value)

    %{
      id: spec.id,
      label: spec.label,
      description: spec.description,
      accent: spec.accent,
      unit: spec.unit,
      source_label: Map.get(payload, :source_label, spec.source_label),
      status: status,
      status_message: Map.get(payload, :status_message, "Live data"),
      setup_envs: [],
      current_average: current_average,
      today_count: today_count,
      total_count: Enum.reduce(raw_series, 0, &(&1.value + &2)),
      average_series: average_series,
      raw_series: raw_series,
      updated_at: Map.get(payload, :updated_at, now())
    }
  end

  defp fallback_metric(spec, today, previous_metric, message) do
    if previous_metric do
      %{previous_metric | status: :stale, status_message: "Using cached data. #{message}"}
    else
      build_state_metric(spec, today, :error, message)
    end
  end

  defp build_state_metric(spec, today, status, message) do
    series = Series.build(%{}, Dashboard.graph_days(), Dashboard.average_window_days(), today)

    %{
      id: spec.id,
      label: spec.label,
      description: spec.description,
      accent: spec.accent,
      unit: spec.unit,
      source_label: spec.source_label,
      status: status,
      status_message: message,
      setup_envs: [],
      current_average: 0.0,
      today_count: 0,
      total_count: 0,
      average_series: series.average,
      raw_series: series.raw,
      updated_at: nil
    }
  end

  defp hidden_habitify do
    %{
      hidden?: true,
      cards: [],
      status: nil,
      status_message: nil,
      updated_at: nil
    }
  end

  defp fallback_habitify(nil, message), do: build_state_habitify(:error, message)

  defp fallback_habitify(previous_habitify, message) do
    if cached_habitify_cards?(previous_habitify) do
      %{
        previous_habitify
        | hidden?: false,
          status: :stale,
          status_message: "Using cached data. #{message}"
      }
    else
      build_state_habitify(:error, message)
    end
  end

  defp build_state_habitify(status, message) do
    %{
      hidden?: false,
      cards: [],
      status: status,
      status_message: message,
      updated_at: nil
    }
  end

  defp mark_habitify_failed(%{hidden?: true} = habitify, _message), do: habitify

  defp mark_habitify_failed(habitify, message) do
    cond do
      cached_habitify_cards?(habitify) ->
        %{habitify | hidden?: false, status: :stale, status_message: message}

      is_map(habitify) ->
        %{habitify | hidden?: false, status: :error, status_message: message}

      true ->
        build_state_habitify(:error, message)
    end
  end

  defp cached_habitify_cards?(%{cards: cards}) when is_list(cards), do: cards != []
  defp cached_habitify_cards?(_habitify), do: false

  defp previous_metric_map(nil), do: %{}
  defp previous_metric_map(%{metrics: metrics}), do: Map.new(metrics, &{&1.id, &1})
  defp previous_habitify(nil), do: nil
  defp previous_habitify(%{habitify: habitify}), do: habitify

  defp connected_attrs(attrs) do
    attrs
    |> Map.new()
    |> Map.put(:status, :connected)
    |> Map.put(:last_error, nil)
    |> Map.put(:last_synced_at, now())
  end

  defp error_attrs(attrs, message) do
    attrs
    |> Map.new()
    |> Map.put(:status, :error)
    |> Map.put(:last_error, message)
  end

  defp range_label(today) do
    dates = Series.display_dates(Dashboard.graph_days(), today)

    case dates do
      [] ->
        "Past month"

      [single] ->
        short_date(single)

      dates ->
        "#{short_date(hd(dates))} - #{short_date(List.last(dates))}"
    end
  end

  defp short_date(date) do
    "#{Calendar.strftime(date, "%b")} #{date.day}"
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
