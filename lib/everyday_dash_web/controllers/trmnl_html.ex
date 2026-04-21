defmodule EverydayDashWeb.TrmnlHTML do
  use EverydayDashWeb, :html

  embed_templates "trmnl_html/*"

  attr :metric, :map, required: true

  def metric_card(assigns) do
    ~H"""
    <article id={"shot-metric-#{@metric.id}"} class="shot-card shot-metric">
      <div class="shot-metric__body">
        <div class="shot-metric__header">
          <div class="shot-metric__intro">
            <p class="shot-eyebrow">{@metric.label}</p>
            <h2 class="shot-metric__title">{@metric.source_label}</h2>
          </div>

          <span class="shot-badge">{status_label(@metric.status)}</span>
        </div>

        <div class="shot-metric__chart-shell">
          <svg
            viewBox="0 0 100 100"
            preserveAspectRatio="none"
            class="shot-metric__chart"
            aria-hidden="true"
          >
            <line
              :for={y <- [20, 42, 64, 86]}
              x1="0"
              y1={y}
              x2="100"
              y2={y}
              class="shot-metric__grid"
            />
            <path d={area_path(@metric.average_series)} class="shot-metric__area" />
            <polyline points={polyline_points(@metric.average_series)} class="shot-metric__line" />
          </svg>

          <div class="shot-metric__value-block">
            <div class="shot-metric__value-block-inner">
              <p class="shot-metric__subhead">{value_kicker(@metric.status)}</p>
              <p class="shot-metric__value">{value_display(@metric)}</p>
              <p class="shot-metric__unit">{value_unit(@metric)}</p>
            </div>
          </div>
        </div>

        <div class="shot-metric__stats">
          <div class="shot-stat">
            <span class="shot-stat__label">Today</span>
            <strong class="shot-stat__value">{@metric.today_count}</strong>
          </div>

          <div class="shot-stat">
            <span class="shot-stat__label">Past month</span>
            <strong class="shot-stat__value">{@metric.total_count}</strong>
          </div>
        </div>

        <p :if={@metric.status != :ok} class="shot-note">
          {status_copy(@metric)}
        </p>
      </div>
    </article>
    """
  end

  attr :card, :map, required: true

  def habit_card(assigns) do
    ~H"""
    <article id={"shot-habit-#{@card.id}"} class="shot-card shot-habit">
      <div class="shot-habit__header">
        <div class="shot-habit__intro">
          <p class="shot-eyebrow">Habit</p>
          <h3 class="shot-habit__title">{@card.name}</h3>
          <p class="shot-habit__goal">{@card.goal_label}</p>
        </div>

        <span class="shot-badge">{habit_badge_label(@card.today_status)}</span>
      </div>

      <div class="shot-habit__bars" aria-hidden="true">
        <span :for={value <- @card.series} class={habit_bar_class(value)} />
      </div>

      <p class="shot-habit__summary">
        {@card.completed_days}/{@card.total_days} done - {habit_today_copy(@card.today_status)}
      </p>
    </article>
    """
  end

  attr :habitify, :map, required: true

  def habitify_empty_state(assigns) do
    ~H"""
    <article id="shot-habitify-empty" class="shot-card shot-empty">
      <p class="shot-eyebrow">{habitify_empty_eyebrow(@habitify)}</p>
      <h3 class="shot-empty__title">{habitify_empty_title(@habitify)}</h3>
      <p class="shot-note">{@habitify.status_message}</p>
    </article>
    """
  end

  def snapshot_status(snapshot) do
    cond do
      snapshot.refreshing? ->
        "Refreshing data..."

      is_nil(snapshot.updated_at) ->
        "Preparing the first snapshot..."

      true ->
        "Last updated #{relative_time(snapshot.updated_at)}"
    end
  end

  def shown_habit_cards(%{cards: cards}) when is_list(cards), do: Enum.take(cards, 3)
  def shown_habit_cards(_habitify), do: []

  defp status_label(:ok), do: "Live"
  defp status_label(:stale), do: "Stale"
  defp status_label(:loading), do: "Loading"
  defp status_label(:setup_required), do: "Setup"
  defp status_label(:error), do: "Retrying"

  defp status_copy(%{status: :ok, status_message: "Live data"}), do: "Live from the source."
  defp status_copy(%{status: :ok, status_message: message}), do: message
  defp status_copy(%{status: :stale, status_message: message}), do: message
  defp status_copy(%{status: :loading, status_message: message}), do: message
  defp status_copy(%{status: :setup_required, status_message: message}), do: message
  defp status_copy(%{status: :error, status_message: message}), do: message

  defp value_kicker(:ok), do: "Current 7-day average"
  defp value_kicker(:stale), do: "Current 7-day average"
  defp value_kicker(:loading), do: "Sync status"
  defp value_kicker(:setup_required), do: "Sync status"
  defp value_kicker(:error), do: "Sync status"

  defp value_display(%{status: status} = metric) when status in [:ok, :stale] do
    metric.current_average
    |> Float.round(1)
    |> :erlang.float_to_binary(decimals: 1)
  end

  defp value_display(%{status: :loading}), do: "Syncing"
  defp value_display(%{status: :setup_required}), do: "Connect"
  defp value_display(%{status: :error}), do: "Waiting"

  defp value_unit(%{status: status, unit: unit}) when status in [:ok, :stale], do: unit
  defp value_unit(%{status: :loading}), do: "first snapshot"
  defp value_unit(%{status: :setup_required}), do: "add tokens below"
  defp value_unit(%{status: :error}), do: "automatic retry active"

  defp habitify_empty_eyebrow(%{status: :loading}), do: "Syncing"
  defp habitify_empty_eyebrow(%{status: :setup_required}), do: "Setup required"
  defp habitify_empty_eyebrow(%{status: :error}), do: "Retry pending"
  defp habitify_empty_eyebrow(%{status: :stale}), do: "Using cache"
  defp habitify_empty_eyebrow(%{status: :ok}), do: "Nothing live yet"

  defp habitify_empty_title(%{status: :ok}), do: "No active Habitify habits found."
  defp habitify_empty_title(%{status: :loading}), do: "Pulling Habitify habits."

  defp habitify_empty_title(%{status: :setup_required}),
    do: "Connect Habitify to render mini-graphs."

  defp habitify_empty_title(%{status: :error}), do: "Habitify is temporarily unavailable."
  defp habitify_empty_title(%{status: :stale}), do: "Cached Habitify cards are not available."

  defp habit_badge_label("completed"), do: "Done"
  defp habit_badge_label("in_progress"), do: "Live"
  defp habit_badge_label(_status), do: "Idle"

  defp habit_bar_class(1), do: "shot-habit__bar shot-habit__bar--done"
  defp habit_bar_class(_value), do: "shot-habit__bar shot-habit__bar--miss"

  defp habit_today_copy("completed"), do: "Completed"
  defp habit_today_copy("in_progress"), do: "In progress"
  defp habit_today_copy(_status), do: "Not done"

  defp polyline_points(series) do
    series
    |> chart_points()
    |> Enum.map_join(" ", fn {x, y} -> "#{format_coordinate(x)},#{format_coordinate(y)}" end)
  end

  defp area_path([]), do: ""

  defp area_path(series) do
    points = chart_points(series)
    {first_x, _first_y} = hd(points)
    {last_x, _last_y} = List.last(points)

    path =
      points
      |> Enum.with_index()
      |> Enum.map(fn {{x, y}, index} ->
        command = if index == 0, do: "M", else: "L"
        "#{command} #{format_coordinate(x)} #{format_coordinate(y)}"
      end)
      |> Enum.join(" ")

    "#{path} L #{format_coordinate(last_x)} 100 L #{format_coordinate(first_x)} 100 Z"
  end

  defp chart_points([]), do: [{0.0, 90.0}]

  defp chart_points(series) do
    values = Enum.map(series, & &1.value)
    max_value = max(Enum.max(values), 1.0)
    count = max(length(series) - 1, 1)

    Enum.with_index(series)
    |> Enum.map(fn {%{value: value}, index} ->
      x = index / count * 100
      y = 90 - value / max_value * 66
      {x, y}
    end)
  end

  defp format_coordinate(value) do
    value
    |> Float.round(2)
    |> :erlang.float_to_binary(decimals: 2)
  end

  defp relative_time(updated_at) do
    seconds = DateTime.diff(DateTime.utc_now(), updated_at, :second)

    cond do
      seconds < 60 -> "moments ago"
      seconds < 3_600 -> "#{div(seconds, 60)} minutes ago"
      true -> "#{div(seconds, 3_600)} hours ago"
    end
  end
end
