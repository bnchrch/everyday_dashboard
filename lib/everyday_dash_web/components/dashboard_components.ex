defmodule EverydayDashWeb.DashboardComponents do
  @moduledoc false

  use EverydayDashWeb, :html

  attr :metric, :map, required: true
  attr :range_label, :string, required: true

  def metric_card(assigns) do
    ~H"""
    <article id={"metric-card-#{@metric.id}"} class={metric_card_class(@metric)}>
      <div class="metric-card__wash"></div>
      <div class="relative flex h-full flex-col gap-6">
        <div class="flex items-start justify-between gap-5">
          <div class="space-y-3">
            <p class="metric-card__label">{@metric.label}</p>
            <h2 class="metric-card__headline">{@metric.source_label}</h2>
            <p class="max-w-xl text-sm leading-6 text-white/68">
              {@metric.description}
            </p>
          </div>

          <span class={status_badge_class(@metric.status)}>
            {status_label(@metric.status)}
          </span>
        </div>

        <div class="metric-card__chart">
          <svg viewBox="0 0 100 100" class="metric-card__chart-svg" aria-hidden="true">
            <line
              :for={y <- [20, 42, 64, 86]}
              x1="0"
              y1={y}
              x2="100"
              y2={y}
              class="metric-card__grid"
            />
            <path d={area_path(@metric.average_series)} class="metric-card__area" />
            <polyline
              points={polyline_points(@metric.average_series)}
              class="metric-card__line"
            />
          </svg>

          <div class="absolute inset-0 flex items-center justify-center">
            <div class="text-center">
              <p class="metric-card__subhead">{value_kicker(@metric.status)}</p>
              <p class="metric-card__value">{value_display(@metric)}</p>
              <p class="metric-card__unit">{value_unit(@metric)}</p>
            </div>
          </div>
        </div>

        <div class="grid gap-3 text-sm text-white/78 sm:grid-cols-2">
          <div class="metric-card__stat">
            <span class="metric-card__stat-label">Today</span>
            <strong class="metric-card__stat-value">{@metric.today_count}</strong>
          </div>

          <div class="metric-card__stat">
            <span class="metric-card__stat-label">Past month</span>
            <strong class="metric-card__stat-value">{@metric.total_count}</strong>
          </div>
        </div>

        <div class="flex flex-col gap-3 text-xs leading-5 text-white/62 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <p>{@range_label}</p>
            <p>Trailing 7-day average</p>
          </div>

          <p>{status_copy(@metric)}</p>
        </div>

        <div
          :if={@metric.status in [:setup_required, :error]}
          class="rounded-[1.4rem] border border-white/10 bg-white/6 px-4 py-4 text-sm text-white/78"
        >
          <p>{@metric.status_message}</p>
          <div class="mt-3 flex flex-wrap gap-2">
            <code :for={env_var <- @metric.setup_envs} class="metric-card__env">
              {env_var}
            </code>
          </div>
        </div>
      </div>
    </article>
    """
  end

  defp metric_card_class(metric) do
    [
      "metric-card",
      "metric-card--#{metric.accent}"
    ]
  end

  attr :habitify, :map, required: true
  attr :range_label, :string, required: true

  def habitify_section(assigns) do
    ~H"""
    <section id="habitify-section" class="mx-auto flex w-full max-w-[78rem] flex-col gap-5">
      <div class="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
        <div class="space-y-2">
          <p class="dashboard-kicker">Habitify, pulled live</p>
          <h2 class="habitify-section__title">Small graphs for the habits that shape the day.</h2>
        </div>

        <div class="text-sm leading-6 text-[color:var(--dashboard-muted)] sm:text-right">
          <p>{habitify_status_copy(@habitify)}</p>
          <p>{@range_label}</p>
        </div>
      </div>

      <div
        :if={@habitify.cards == []}
        id="habitify-empty-state"
        class="habitify-empty-state"
      >
        <div class="space-y-2">
          <p class="habitify-empty-state__eyebrow">{habitify_empty_eyebrow(@habitify)}</p>
          <h3 class="habitify-empty-state__title">{habitify_empty_title(@habitify)}</h3>
          <p class="text-sm leading-6 text-white/74">{@habitify.status_message}</p>
        </div>

        <div
          :if={@habitify.status in [:setup_required, :error]}
          class="mt-4 flex flex-wrap gap-2"
        >
          <code class="metric-card__env">HABITIFY_API_KEY</code>
        </div>
      </div>

      <div
        :if={@habitify.cards != []}
        id="habitify-grid"
        class="grid gap-5 lg:grid-cols-3"
      >
        <.habit_card :for={card <- @habitify.cards} card={card} />
      </div>
    </section>
    """
  end

  attr :card, :map, required: true

  defp habit_card(assigns) do
    ~H"""
    <article id={"habit-card-#{@card.id}"} class="habit-card">
      <div class="habit-card__wash"></div>
      <div class="relative flex h-full flex-col gap-5">
        <div class="flex items-start justify-between gap-4">
          <div class="space-y-2">
            <p class="habit-card__eyebrow">Habit</p>
            <h3 class="habit-card__title">{@card.name}</h3>
            <p class="habit-card__goal">{@card.goal_label}</p>
          </div>

          <span class={habit_badge_class(@card.today_status)}>
            {habit_badge_label(@card.today_status)}
          </span>
        </div>

        <div class="habit-card__chart">
          <div class="habit-card__bars" aria-hidden="true">
            <span
              :for={{value, index} <- Enum.with_index(@card.series)}
              class={habit_bar_class(value)}
              title={"Day #{index + 1}: #{habit_bar_title(value)}"}
            />
          </div>
        </div>

        <div class="grid gap-3 sm:grid-cols-2">
          <div class="habit-card__stat">
            <span class="habit-card__stat-label">30d done</span>
            <strong class="habit-card__stat-value">
              {@card.completed_days}/{@card.total_days}
            </strong>
          </div>

          <div class="habit-card__stat">
            <span class="habit-card__stat-label">Today</span>
            <strong class="habit-card__stat-copy">{habit_today_copy(@card.today_status)}</strong>
          </div>
        </div>
      </div>
    </article>
    """
  end

  defp status_badge_class(:ok), do: "metric-card__badge metric-card__badge--ok"
  defp status_badge_class(:stale), do: "metric-card__badge metric-card__badge--stale"
  defp status_badge_class(:loading), do: "metric-card__badge metric-card__badge--loading"
  defp status_badge_class(:setup_required), do: "metric-card__badge metric-card__badge--setup"
  defp status_badge_class(:error), do: "metric-card__badge metric-card__badge--error"

  defp status_label(:ok), do: "Live"
  defp status_label(:stale), do: "Stale"
  defp status_label(:loading), do: "Loading"
  defp status_label(:setup_required), do: "Setup"
  defp status_label(:error), do: "Retrying"

  defp status_copy(%{status: :ok}), do: "Live from the source."
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

  defp habitify_status_copy(%{status: :ok}), do: "Live from Habitify."
  defp habitify_status_copy(%{status: :stale, status_message: message}), do: message
  defp habitify_status_copy(%{status: :loading, status_message: message}), do: message
  defp habitify_status_copy(%{status: :setup_required, status_message: message}), do: message
  defp habitify_status_copy(%{status: :error, status_message: message}), do: message

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

  defp habit_badge_class("completed"), do: "habit-card__badge habit-card__badge--done"
  defp habit_badge_class("in_progress"), do: "habit-card__badge habit-card__badge--progress"
  defp habit_badge_class(_status), do: "habit-card__badge habit-card__badge--idle"

  defp habit_badge_label("completed"), do: "Done"
  defp habit_badge_label("in_progress"), do: "Live"
  defp habit_badge_label(_status), do: "Idle"

  defp habit_bar_class(1), do: "habit-card__bar habit-card__bar--done"
  defp habit_bar_class(_value), do: "habit-card__bar habit-card__bar--miss"

  defp habit_bar_title(1), do: "done"
  defp habit_bar_title(_value), do: "not done"

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
end
