defmodule EverydayDash.Dashboard.Serializer do
  @moduledoc false

  def dump(snapshot) do
    %{
      "generated_at" => dump_datetime(snapshot.generated_at),
      "updated_at" => dump_datetime(snapshot.updated_at),
      "refreshing" => snapshot.refreshing?,
      "range_label" => snapshot.range_label,
      "metrics" => Enum.map(snapshot.metrics, &dump_metric/1),
      "habitify" => dump_habitify(snapshot.habitify)
    }
  end

  def load(payload) when is_map(payload) do
    %{
      generated_at: load_datetime(payload["generated_at"]),
      updated_at: load_datetime(payload["updated_at"]),
      refreshing?: Map.get(payload, "refreshing", false),
      range_label: Map.get(payload, "range_label", "Past month"),
      metrics: payload |> Map.get("metrics", []) |> Enum.map(&load_metric/1),
      habitify: load_habitify(Map.get(payload, "habitify", %{}))
    }
  end

  defp dump_metric(metric) do
    %{
      "id" => Atom.to_string(metric.id),
      "label" => metric.label,
      "description" => metric.description,
      "accent" => metric.accent,
      "unit" => metric.unit,
      "source_label" => metric.source_label,
      "status" => Atom.to_string(metric.status),
      "status_message" => metric.status_message,
      "setup_envs" => Map.get(metric, :setup_envs, []),
      "current_average" => metric.current_average,
      "today_count" => metric.today_count,
      "total_count" => metric.total_count,
      "average_series" => Enum.map(metric.average_series, &dump_series_point/1),
      "raw_series" => Enum.map(metric.raw_series, &dump_series_point/1),
      "updated_at" => dump_datetime(metric.updated_at)
    }
  end

  defp load_metric(metric) do
    %{
      id: load_metric_id(metric["id"]),
      label: metric["label"],
      description: metric["description"],
      accent: metric["accent"],
      unit: metric["unit"],
      source_label: metric["source_label"],
      status: load_status(metric["status"]),
      status_message: metric["status_message"],
      setup_envs: Map.get(metric, "setup_envs", []),
      current_average: Map.get(metric, "current_average", 0.0),
      today_count: Map.get(metric, "today_count", 0),
      total_count: Map.get(metric, "total_count", 0),
      average_series: metric |> Map.get("average_series", []) |> Enum.map(&load_series_point/1),
      raw_series: metric |> Map.get("raw_series", []) |> Enum.map(&load_series_point/1),
      updated_at: load_datetime(metric["updated_at"])
    }
  end

  defp dump_habitify(habitify) do
    %{
      "hidden" => Map.get(habitify, :hidden?, false),
      "cards" => Enum.map(Map.get(habitify, :cards, []), &dump_habit_card/1),
      "status" => dump_optional_status(Map.get(habitify, :status)),
      "status_message" => Map.get(habitify, :status_message),
      "updated_at" => dump_datetime(Map.get(habitify, :updated_at))
    }
  end

  defp load_habitify(habitify) do
    %{
      hidden?: Map.get(habitify, "hidden", false),
      cards: habitify |> Map.get("cards", []) |> Enum.map(&load_habit_card/1),
      status: load_optional_status(Map.get(habitify, "status")),
      status_message: Map.get(habitify, "status_message"),
      updated_at: load_datetime(Map.get(habitify, "updated_at"))
    }
  end

  defp dump_habit_card(card) do
    %{
      "completed_days" => card.completed_days,
      "goal_label" => card.goal_label,
      "id" => card.id,
      "name" => card.name,
      "series" => card.series,
      "today_status" => card.today_status,
      "total_days" => card.total_days
    }
  end

  defp load_habit_card(card) do
    %{
      completed_days: Map.get(card, "completed_days", 0),
      goal_label: Map.get(card, "goal_label"),
      id: Map.get(card, "id"),
      name: Map.get(card, "name"),
      series: Map.get(card, "series", []),
      today_status: Map.get(card, "today_status", "none"),
      total_days: Map.get(card, "total_days", 0)
    }
  end

  defp dump_series_point(point) do
    %{"date" => Date.to_iso8601(point.date), "value" => point.value}
  end

  defp load_series_point(point) do
    {:ok, date} = Date.from_iso8601(point["date"])
    %{date: date, value: Map.get(point, "value", 0)}
  end

  defp dump_datetime(nil), do: nil
  defp dump_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp load_datetime(nil), do: nil

  defp load_datetime(datetime) when is_binary(datetime) do
    case DateTime.from_iso8601(datetime) do
      {:ok, parsed_datetime, _offset} -> parsed_datetime
      _ -> nil
    end
  end

  defp dump_optional_status(nil), do: nil
  defp dump_optional_status(status), do: Atom.to_string(status)

  defp load_optional_status(nil), do: nil
  defp load_optional_status(status), do: load_status(status)

  defp load_status("ok"), do: :ok
  defp load_status("stale"), do: :stale
  defp load_status("loading"), do: :loading
  defp load_status("setup_required"), do: :setup_required
  defp load_status("error"), do: :error
  defp load_status("hidden"), do: :hidden
  defp load_status(_status), do: :error

  defp load_metric_id("github_commits"), do: :github_commits
  defp load_metric_id("strava_activities"), do: :strava_activities
  defp load_metric_id(_metric_id), do: :github_commits
end
