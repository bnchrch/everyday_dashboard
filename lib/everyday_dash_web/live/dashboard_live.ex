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
     |> assign(:snapshot, Dashboard.snapshot())}
  end

  @impl true
  def handle_info({:dashboard_snapshot, snapshot}, socket) do
    {:noreply, assign(socket, :snapshot, snapshot)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      show_header={false}
      main_class={dashboard_main_class(@live_action)}
      inner_class="w-full"
    >
      <div id="dashboard-stage" class="dashboard-stage">
        <div class="dashboard-orb dashboard-orb--warm"></div>
        <div class="dashboard-orb dashboard-orb--cool"></div>

        <section id="dashboard-shell" class="dashboard-shell w-full">
          <div id="dashboard-layout" class="dashboard-layout">
            <header id="dashboard-header" class="dashboard-header">
              <div class="dashboard-header__main max-w-3xl space-y-5">
                <p class="dashboard-kicker dashboard-header__kicker">
                  Life metrics, refreshed from the source
                </p>
                <div
                  id="hero-message-rotator"
                  phx-hook="HeroMessageRotator"
                  phx-update="ignore"
                  data-messages={hero_messages_json()}
                  class="dashboard-hero-copy dashboard-header__hero-copy max-w-2xl text-base leading-7 text-[color:var(--dashboard-muted)] sm:text-lg"
                >
                  <p class="dashboard-hero-copy__line">
                    <span class="dashboard-hero-copy__label">Remember:</span>
                    <span class="dashboard-hero-copy__viewport" aria-live="polite">
                      <span class="dashboard-hero-copy__sizer" aria-hidden="true">
                        {longest_hero_message()}
                      </span>
                      <span
                        class="dashboard-hero-copy__text dashboard-hero-copy__text--current"
                        data-role="current"
                      >
                        {first_hero_message()}
                      </span>
                      <span
                        class="dashboard-hero-copy__text dashboard-hero-copy__text--incoming"
                        data-role="incoming"
                        aria-hidden="true"
                      >
                      </span>
                    </span>
                  </p>
                </div>
              </div>

              <div class="dashboard-header__status flex flex-col gap-3 self-start lg:items-end">
                <div
                  id="dashboard-status"
                  class="dashboard-header__status-copy text-sm leading-6 text-[color:var(--dashboard-muted)] lg:text-right"
                >
                  <p>{snapshot_status(@snapshot)}</p>
                  <p class="dashboard-header__range">{@snapshot.range_label}</p>
                </div>
              </div>
            </header>

            <section id="dashboard-primary" class="dashboard-primary">
              <div class="dashboard-primary__inner mx-auto w-full max-w-5xl">
                <div
                  id="dashboard-metrics-grid"
                  class="dashboard-metrics-grid grid gap-6 lg:grid-cols-2"
                >
                  <DashboardComponents.metric_card
                    :for={metric <- @snapshot.metrics}
                    metric={metric}
                    range_label={@snapshot.range_label}
                  />
                </div>
              </div>
            </section>

            <section id="dashboard-habitify-rail" class="dashboard-habitify-rail">
              <DashboardComponents.habitify_section
                habitify={@snapshot.habitify}
                range_label={@snapshot.range_label}
              />
            </section>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp snapshot_status(snapshot) do
    cond do
      snapshot.refreshing? ->
        "Refreshing data..."

      is_nil(snapshot.updated_at) ->
        "Preparing the first snapshot..."

      true ->
        "Last updated #{relative_time(snapshot.updated_at)}"
    end
  end

  defp relative_time(updated_at) do
    seconds = DateTime.diff(DateTime.utc_now(), updated_at, :second)

    cond do
      seconds < 60 -> "moments ago"
      seconds < 3_600 -> "#{div(seconds, 60)} minutes ago"
      true -> "#{div(seconds, 3_600)} hours ago"
    end
  end

  defp hero_messages_json do
    Jason.encode!(@hero_messages)
  end

  defp dashboard_main_class(live_action) do
    [
      "dashboard-page",
      live_action == :trmnl && "dashboard-page--trmnl",
      "mx-auto flex min-h-screen w-full max-w-[92rem] items-center px-6 py-8 sm:px-10 lg:px-12 lg:py-14"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp first_hero_message, do: List.first(@hero_messages)

  defp longest_hero_message do
    Enum.max_by(@hero_messages, &String.length/1)
  end
end
