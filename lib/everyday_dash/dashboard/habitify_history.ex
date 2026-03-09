defmodule EverydayDash.Dashboard.HabitifyHistory do
  @moduledoc false

  alias EverydayDash.Dashboard.Series

  def build(logged_values_by_date, goal_target, graph_days, today \\ Date.utc_today())
      when graph_days > 0 do
    dates = Series.display_dates(graph_days, today)
    threshold = completion_threshold(goal_target)

    series =
      Enum.map(dates, fn date ->
        value_for_total(Map.get(logged_values_by_date, date, 0.0), threshold)
      end)

    today_total = Map.get(logged_values_by_date, today, 0.0)

    %{
      completed_days: Enum.count(series, &(&1 == 1)),
      series: series,
      today_status: today_status(today_total, threshold),
      total_days: length(series)
    }
  end

  defp completion_threshold(goal_target) when is_number(goal_target) and goal_target > 0,
    do: goal_target

  defp completion_threshold(_goal_target), do: 0.000001

  defp value_for_total(total, threshold) when total >= threshold, do: 1
  defp value_for_total(_total, _threshold), do: 0

  defp today_status(total, threshold) when total >= threshold, do: "completed"
  defp today_status(total, _threshold) when total > 0, do: "in_progress"
  defp today_status(_total, _threshold), do: "none"
end
