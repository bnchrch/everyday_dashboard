defmodule EverydayDash.Dashboard.Loader do
  @moduledoc false

  alias EverydayDash.Dashboard
  alias EverydayDash.Dashboard.Sources.Habitify
  alias EverydayDash.Dashboard.Series
  alias EverydayDash.Dashboard.Sources.GitHub
  alias EverydayDash.Dashboard.Sources.Strava

  @metric_specs [
    %{
      id: :github_commits,
      label: "GitHub commits",
      description:
        "Daily commit volume from your GitHub account, displayed as a rolling 7-day average.",
      accent: "embers",
      unit: "commits/day",
      source: GitHub,
      source_label: "GitHub GraphQL",
      setup_envs: ["GITHUB_USERNAME", "GITHUB_TOKEN"]
    },
    %{
      id: :strava_activities,
      label: "Strava activities",
      description:
        "Daily Strava activity count over the last month, smoothed with the same trailing window.",
      accent: "pine",
      unit: "activities/day",
      source: Strava,
      source_label: "Strava API",
      setup_envs: ["STRAVA_CLIENT_ID", "STRAVA_CLIENT_SECRET", "STRAVA_REFRESH_TOKEN"]
    }
  ]

  def initial_snapshot do
    today = Dashboard.today()
    now = now()

    %{
      generated_at: now,
      updated_at: nil,
      refreshing?: true,
      range_label: range_label(today),
      metrics: Enum.map(@metric_specs, &initial_metric(&1, today)),
      habitify: initial_habitify()
    }
  end

  def fetch(previous_snapshot \\ nil) do
    today = Dashboard.today()
    now = now()
    previous_metrics = previous_metric_map(previous_snapshot)
    previous_habitify = previous_habitify(previous_snapshot)

    metrics =
      Enum.map(@metric_specs, fn spec ->
        load_metric(spec, today, Map.get(previous_metrics, spec.id))
      end)

    %{
      generated_at: now,
      updated_at: now,
      refreshing?: false,
      range_label: range_label(today),
      metrics: metrics,
      habitify: load_habitify(today, previous_habitify)
    }
  end

  def mark_refreshing(snapshot) do
    Map.put(snapshot, :refreshing?, true)
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
        habitify: mark_habitify_failed(snapshot, message)
    }
  end

  defp load_metric(spec, today, previous_metric) do
    case spec.source.fetch(today, Dashboard.graph_days(), Dashboard.average_window_days()) do
      {:ok, %{counts: counts} = payload} ->
        build_loaded_metric(spec, counts, payload, today)

      {:error, :missing_config, message} ->
        build_state_metric(spec, today, :setup_required, message)

      {:error, _reason, message} ->
        fallback_metric(spec, today, previous_metric, message)
    end
  rescue
    error ->
      fallback_metric(spec, today, previous_metric, Exception.message(error))
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
      setup_envs: spec.setup_envs,
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
      setup_envs: spec.setup_envs,
      current_average: 0.0,
      today_count: 0,
      total_count: 0,
      average_series: series.average,
      raw_series: series.raw,
      updated_at: nil
    }
  end

  defp initial_metric(spec, today) do
    build_state_metric(spec, today, :loading, "Pulling the first snapshot.")
  end

  defp initial_habitify do
    build_state_habitify(:loading, "Pulling the first snapshot.")
  end

  defp load_habitify(today, previous_habitify) do
    case Habitify.fetch(today, Dashboard.graph_days()) do
      {:ok, %{cards: cards} = payload} ->
        %{
          cards: cards,
          status: :ok,
          status_message: Map.get(payload, :status_message, "Live data"),
          updated_at: now()
        }

      {:error, :missing_config, message} ->
        fallback_habitify(previous_habitify, :setup_required, message)

      {:error, _reason, message} ->
        fallback_habitify(previous_habitify, :error, message)
    end
  rescue
    error ->
      fallback_habitify(previous_habitify, :error, Exception.message(error))
  end

  defp fallback_habitify(previous_habitify, status, message) do
    if cached_habitify_cards?(previous_habitify) do
      %{previous_habitify | status: :stale, status_message: "Using cached data. #{message}"}
    else
      build_state_habitify(status, message)
    end
  end

  defp build_state_habitify(status, message) do
    %{
      cards: [],
      status: status,
      status_message: message,
      updated_at: nil
    }
  end

  defp mark_habitify_failed(snapshot, message) do
    habitify = Map.get(snapshot, :habitify)

    cond do
      cached_habitify_cards?(habitify) ->
        %{habitify | status: :stale, status_message: message}

      is_map(habitify) ->
        %{habitify | status: :error, status_message: message}

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

  defp now do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end
end
