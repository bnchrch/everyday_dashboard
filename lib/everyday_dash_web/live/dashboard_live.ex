defmodule EverydayDashWeb.DashboardLive do
  use EverydayDashWeb, :live_view

  alias EverydayDash.Dashboard
  alias EverydayDashWeb.DashboardComponents

  @hero_messages [
    "You are the base",
    "Roadwork makes the brain work",
    "Want to achieve your dreams? sleep.",
    "Systems not goals",
    "Delegate dont do",
    "Are you hunting antelope? or field mice?",
    "Dont spend your dreams",
    "Consistency compounds",
    "How cheap is your happiness?",
    "Life short, have fun"
  ]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Dashboard.subscribe()

    {:ok,
     socket
     |> assign(:page_title, "Everyday Dash")
     |> assign(:snapshot, Dashboard.snapshot())
     |> assign(:refresh_requested?, false)}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    Dashboard.refresh_now()
    {:noreply, assign(socket, :refresh_requested?, true)}
  end

  @impl true
  def handle_info({:dashboard_snapshot, snapshot}, socket) do
    {:noreply, assign(socket, snapshot: snapshot, refresh_requested?: false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="dashboard-stage">
      <div class="dashboard-orb dashboard-orb--warm"></div>
      <div class="dashboard-orb dashboard-orb--cool"></div>

      <main class="mx-auto flex min-h-screen w-full max-w-7xl items-center px-6 py-8 sm:px-10 lg:px-12 lg:py-14">
        <section class="dashboard-shell w-full">
          <div class="flex flex-col gap-10">
            <div class="flex flex-col gap-8 lg:flex-row lg:items-end lg:justify-between">
              <div class="max-w-3xl space-y-5">
                <p class="dashboard-kicker">Life metrics, refreshed from the source</p>
                <h1 class="dashboard-title text-balance text-5xl leading-none sm:text-6xl">
                  One page for the signals that matter every day.
                </h1>
                <div
                  id="hero-message-rotator"
                  phx-hook="HeroMessageRotator"
                  phx-update="ignore"
                  data-messages={hero_messages_json()}
                  class="dashboard-hero-copy max-w-2xl text-base leading-7 text-[color:var(--dashboard-muted)] sm:text-lg"
                >
                  <div class="dashboard-hero-copy__viewport" aria-live="polite">
                    <p class="dashboard-hero-copy__sizer" aria-hidden="true">
                      {hero_message_copy(longest_hero_message())}
                    </p>
                    <p
                      class="dashboard-hero-copy__text dashboard-hero-copy__text--current"
                      data-role="current"
                    >
                      {hero_message_copy(first_hero_message())}
                    </p>
                    <p
                      class="dashboard-hero-copy__text dashboard-hero-copy__text--incoming"
                      data-role="incoming"
                      aria-hidden="true"
                    >
                    </p>
                  </div>
                </div>
              </div>

              <div class="flex flex-col gap-3 self-start lg:items-end">
                <div class="text-sm leading-6 text-[color:var(--dashboard-muted)] lg:text-right">
                  <p>{snapshot_status(@snapshot, @refresh_requested?)}</p>
                  <p>{@snapshot.range_label}</p>
                </div>

                <button
                  type="button"
                  phx-click="refresh"
                  class="dashboard-refresh-button"
                >
                  {refresh_label(@snapshot, @refresh_requested?)}
                </button>
              </div>
            </div>

            <div class="grid gap-6 lg:grid-cols-2">
              <DashboardComponents.metric_card
                :for={metric <- @snapshot.metrics}
                metric={metric}
                range_label={@snapshot.range_label}
              />
            </div>
          </div>
        </section>
      </main>
    </div>
    """
  end

  defp snapshot_status(snapshot, refresh_requested?) do
    cond do
      snapshot.refreshing? or refresh_requested? ->
        "Refreshing data..."

      is_nil(snapshot.updated_at) ->
        "Preparing the first snapshot..."

      true ->
        "Last updated #{relative_time(snapshot.updated_at)}"
    end
  end

  defp refresh_label(snapshot, refresh_requested?) do
    if snapshot.refreshing? or refresh_requested?, do: "Refreshing...", else: "Refresh now"
  end

  defp relative_time(updated_at) do
    seconds = DateTime.diff(DateTime.utc_now(), updated_at, :second)

    cond do
      seconds < 60 -> "moments ago"
      seconds < 3_600 -> "#{div(seconds, 60)} minutes ago"
      true -> "#{div(seconds, 3_600)} hours ago"
    end
  end

  defp hero_message_copy(message), do: "Remember: #{message}"

  defp hero_messages_json do
    @hero_messages
    |> Enum.map(&hero_message_copy/1)
    |> Jason.encode!()
  end

  defp first_hero_message, do: List.first(@hero_messages)

  defp longest_hero_message do
    Enum.max_by(@hero_messages, &String.length/1)
  end
end
