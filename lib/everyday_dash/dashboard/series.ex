defmodule EverydayDash.Dashboard.Series do
  @moduledoc false

  def display_dates(graph_days, today \\ Date.utc_today()) when graph_days > 0 do
    start_date = Date.add(today, 1 - graph_days)
    Enum.to_list(Date.range(start_date, today))
  end

  def query_dates(graph_days, window_days, today \\ Date.utc_today())
      when graph_days > 0 and window_days > 0 do
    start_date = Date.add(today, 2 - graph_days - window_days)
    Enum.to_list(Date.range(start_date, today))
  end

  def build(counts_by_date, graph_days, window_days, today \\ Date.utc_today())
      when graph_days > 0 and window_days > 0 do
    display_dates = display_dates(graph_days, today)
    query_dates = query_dates(graph_days, window_days, today)

    counts =
      Enum.reduce(query_dates, counts_by_date, fn date, acc ->
        Map.put_new(acc, date, 0)
      end)

    average =
      Enum.map(display_dates, fn date ->
        window_start = Date.add(date, 1 - window_days)

        total =
          Date.range(window_start, date)
          |> Enum.reduce(0, fn window_date, sum ->
            sum + Map.get(counts, window_date, 0)
          end)

        %{date: date, value: total / window_days}
      end)

    raw =
      Enum.map(display_dates, fn date ->
        %{date: date, value: Map.get(counts, date, 0)}
      end)

    %{average: average, raw: raw}
  end
end
