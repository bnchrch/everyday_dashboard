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
  def mount(%{"slug" => slug}, _session, socket) do
    case Dashboard.public_dashboard_by_slug(slug) do
      {:ok, user, snapshot} ->
        if connected?(socket) do
          Dashboard.subscribe(user)
          Dashboard.maybe_refresh(user)
        end

        {:ok,
         socket
         |> assign(:page_title, "#{user.slug} - Everyday Dash")
         |> assign(:owner, user)
         |> assign(:snapshot, snapshot)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "That dashboard is not published.")
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_info({:dashboard_snapshot, snapshot}, socket) do
    {:noreply, assign(socket, snapshot: snapshot)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      show_header={false}
      main_class="mx-auto flex min-h-screen w-full max-w-[92rem] items-center px-6 py-8 sm:px-10 lg:px-12 lg:py-14"
      inner_class="w-full"
    >
      <div class="dashboard-stage">
        <div class="dashboard-orb dashboard-orb--warm"></div>
        <div class="dashboard-orb dashboard-orb--cool"></div>

        <section class="dashboard-shell w-full">
          <div class="flex flex-col gap-10">
            <div class="flex flex-col gap-8 lg:flex-row lg:items-end lg:justify-between">
              <div class="max-w-3xl space-y-5">
                <p class="dashboard-kicker">Life metrics, refreshed from the source</p>
                <h1 class="dashboard-title text-balance text-5xl leading-none sm:text-6xl">
                  One page for the signals that matter every day.
                </h1>
                <p class="text-sm font-semibold uppercase tracking-[0.2em] text-[color:var(--dashboard-muted)]">
                  /u/{@owner.slug}
                </p>
                <div
                  id="hero-message-rotator"
                  phx-hook="HeroMessageRotator"
                  phx-update="ignore"
                  data-messages={hero_messages_json()}
                  class="dashboard-hero-copy max-w-2xl text-base leading-7 text-[color:var(--dashboard-muted)] sm:text-lg"
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

              <div class="flex flex-col gap-3 self-start lg:items-end">
                <div class="text-sm leading-6 text-[color:var(--dashboard-muted)] lg:text-right">
                  <p>{snapshot_status(@snapshot)}</p>
                  <p>{@snapshot.range_label}</p>
                </div>
              </div>
            </div>

            <div
              :if={show_empty_state?(@snapshot)}
              id="dashboard-empty-state"
              class="rounded-[1.6rem] border border-[color:var(--dashboard-border)] bg-white/45 px-6 py-12 text-center"
            >
              <p class="dashboard-kicker">Nothing public yet</p>
              <h2 class="mt-3 text-3xl font-semibold text-[color:var(--dashboard-ink)]">
                This dashboard is published, but no providers are connected.
              </h2>
              <p class="mx-auto mt-4 max-w-2xl text-base leading-7 text-[color:var(--dashboard-muted)]">
                Connect GitHub, Strava, or Habitify from the authenticated app to start filling this page with live signals.
              </p>
            </div>

            <div :if={@snapshot.metrics != []} class="mx-auto w-full max-w-5xl">
              <div id="dashboard-metrics-grid" class="grid gap-6 lg:grid-cols-2">
                <DashboardComponents.metric_card
                  :for={metric <- @snapshot.metrics}
                  metric={metric}
                  range_label={@snapshot.range_label}
                />
              </div>
            </div>

            <DashboardComponents.habitify_section
              :if={!Map.get(@snapshot.habitify, :hidden?, false)}
              habitify={@snapshot.habitify}
              range_label={@snapshot.range_label}
            />
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

  defp show_empty_state?(snapshot) do
    snapshot.metrics == [] and Map.get(snapshot.habitify, :hidden?, false)
  end

  defp hero_messages_json do
    Jason.encode!(@hero_messages)
  end

  defp first_hero_message, do: List.first(@hero_messages)

  defp longest_hero_message do
    Enum.max_by(@hero_messages, &String.length/1)
  end
end
