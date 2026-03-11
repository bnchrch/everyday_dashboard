defmodule EverydayDashWeb.AppLive do
  use EverydayDashWeb, :live_view

  alias EverydayDash.Accounts
  alias EverydayDash.Accounts.User
  alias EverydayDash.Dashboard
  alias EverydayDash.Dashboard.Sources.Habitify

  @impl true
  def mount(_params, _session, socket) do
    user = load_user(socket)

    if connected?(socket) do
      Dashboard.subscribe(user)
      Dashboard.maybe_refresh(user)
    end

    {:ok, assign_state(socket, user, Dashboard.snapshot_from_record(user.dashboard_snapshot))}
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
          <div class="flex flex-col gap-8">
            <div class="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
              <div class="max-w-3xl space-y-4">
                <p class="dashboard-kicker">Everyday Dash</p>
                <h1 class="dashboard-title text-balance text-4xl leading-none sm:text-5xl">
                  Connect your systems, publish your dashboard, and keep the public view fresh.
                </h1>
                <p class="max-w-2xl text-base leading-7 text-[color:var(--dashboard-muted)] sm:text-lg">
                  Your public dashboard lives at a stable slug. GitHub and Strava connect through OAuth. Habitify stays manual with an API key.
                </p>
              </div>

              <div class="flex flex-col gap-3 self-start lg:items-end">
                <div class="text-sm leading-6 text-[color:var(--dashboard-muted)] lg:text-right">
                  <p>{app_snapshot_copy(@snapshot)}</p>
                  <p>{@snapshot.range_label}</p>
                </div>

                <button
                  id="dashboard-manual-refresh"
                  type="button"
                  phx-click="refresh_dashboard"
                  class="dashboard-refresh-button"
                >
                  Refresh dashboard
                </button>
              </div>
            </div>

            <div class="grid gap-6 lg:grid-cols-[minmax(0,1.15fr)_minmax(0,0.85fr)]">
              <section class="rounded-[1.6rem] border border-white/20 bg-white/40 p-6 shadow-[0_24px_60px_rgba(36,27,15,0.08)] backdrop-blur">
                <div class="space-y-2">
                  <p class="dashboard-kicker">Public dashboard</p>
                  <h2 class="text-2xl font-semibold text-[color:var(--dashboard-ink)]">
                    Choose the slug and publish state.
                  </h2>
                </div>

                <.form
                  for={@dashboard_form}
                  id="dashboard-settings-form"
                  phx-change="validate_dashboard"
                  phx-submit="save_dashboard"
                  class="mt-6 space-y-5"
                >
                  <.input
                    field={@dashboard_form[:slug]}
                    type="text"
                    label="Dashboard slug"
                    placeholder="your-name"
                  />

                  <div class="rounded-2xl border border-[color:var(--dashboard-border)] bg-white/55 px-4 py-4">
                    <input type="hidden" name="dashboard[publish]" value="false" />
                    <label for="dashboard-publish" class="flex items-center justify-between gap-4">
                      <div>
                        <p class="font-semibold text-[color:var(--dashboard-ink)]">
                          Publish publicly
                        </p>
                        <p class="text-sm leading-6 text-[color:var(--dashboard-muted)]">
                          Keep your slug reserved while controlling when the public page goes live.
                        </p>
                      </div>
                      <input
                        id="dashboard-publish"
                        type="checkbox"
                        name="dashboard[publish]"
                        value="true"
                        checked={User.published?(@user)}
                        class="size-5 rounded border-[color:var(--dashboard-border)] text-[color:var(--dashboard-ink)]"
                      />
                    </label>
                  </div>

                  <div class="rounded-2xl border border-[color:var(--dashboard-border)] bg-white/55 px-4 py-4">
                    <p class="text-sm font-semibold uppercase tracking-[0.2em] text-[color:var(--dashboard-muted)]">
                      Preview
                    </p>
                    <%= if @user.slug do %>
                      <.link
                        id="dashboard-preview-link"
                        navigate={~p"/u/#{@user.slug}"}
                        class="mt-2 inline-flex text-lg font-semibold text-[color:var(--dashboard-ink)] underline decoration-[color:var(--dashboard-border)] underline-offset-4"
                      >
                        /u/{@user.slug}
                      </.link>
                    <% else %>
                      <p class="mt-2 text-sm leading-6 text-[color:var(--dashboard-muted)]">
                        Save a slug to generate the public URL.
                      </p>
                    <% end %>
                  </div>

                  <button
                    id="dashboard-settings-submit"
                    type="submit"
                    class="dashboard-refresh-button"
                  >
                    Save dashboard settings
                  </button>
                </.form>
              </section>

              <section class="rounded-[1.6rem] border border-white/20 bg-[rgba(20,24,18,0.78)] p-6 text-white shadow-[0_24px_60px_rgba(18,22,14,0.22)]">
                <div class="space-y-2">
                  <p class="dashboard-kicker text-white/60">Account</p>
                  <h2 class="text-2xl font-semibold">Signed in as {@user.email}</h2>
                </div>

                <div class="mt-6 space-y-4 text-sm leading-6 text-white/74">
                  <p>
                    Dashboard status:
                    <strong class="ml-2 text-white">
                      {if(User.published?(@user), do: "Published", else: "Private")}
                    </strong>
                  </p>
                  <p>
                    Connected providers:
                    <strong class="ml-2 text-white">
                      {connected_provider_count(@integrations)}/3
                    </strong>
                  </p>
                  <p>
                    Last refresh:
                    <strong class="ml-2 text-white">{refresh_time_copy(@snapshot.updated_at)}</strong>
                  </p>
                </div>

                <div class="mt-6 flex flex-wrap gap-3">
                  <.link
                    id="account-settings-link"
                    navigate={~p"/users/settings"}
                    class="inline-flex items-center rounded-full border border-white/20 px-4 py-2 text-sm font-semibold text-white transition hover:bg-white/10"
                  >
                    Account settings
                  </.link>
                  <.link
                    id="log-out-link"
                    href={~p"/users/log-out"}
                    method="delete"
                    class="inline-flex items-center rounded-full border border-white/20 px-4 py-2 text-sm font-semibold text-white transition hover:bg-white/10"
                  >
                    Log out
                  </.link>
                </div>
              </section>
            </div>

            <div class="grid gap-6 lg:grid-cols-3">
              <section id="provider-card-github" class="provider-card">
                <div class="space-y-2">
                  <p class="dashboard-kicker">GitHub</p>
                  <h3 class="text-xl font-semibold text-[color:var(--dashboard-ink)]">
                    Commit history
                  </h3>
                  <p class="text-sm leading-6 text-[color:var(--dashboard-muted)]">
                    OAuth connection for commit contributions and public profile identity.
                  </p>
                </div>

                <div class="mt-5 space-y-3 text-sm leading-6 text-[color:var(--dashboard-muted)]">
                  <p>{provider_summary(@integrations[:github], "No GitHub account connected.")}</p>
                  <p :if={provider_error(@integrations[:github])} class="text-[#9a4223]">
                    {provider_error(@integrations[:github])}
                  </p>
                </div>

                <div class="mt-6 flex gap-3">
                  <.link
                    id="github-connect-button"
                    href={~p"/auth/github"}
                    class="dashboard-refresh-button"
                  >
                    {provider_connect_label(@integrations[:github], "GitHub")}
                  </.link>
                  <button
                    :if={provider_connected?(@integrations[:github])}
                    id="github-disconnect-button"
                    type="button"
                    phx-click="disconnect"
                    phx-value-provider="github"
                    class="inline-flex items-center rounded-full border border-[color:var(--dashboard-border)] px-4 py-2 text-sm font-semibold text-[color:var(--dashboard-ink)] transition hover:bg-white/60"
                  >
                    Disconnect
                  </button>
                </div>
              </section>

              <section id="provider-card-strava" class="provider-card">
                <div class="space-y-2">
                  <p class="dashboard-kicker">Strava</p>
                  <h3 class="text-xl font-semibold text-[color:var(--dashboard-ink)]">
                    Activity history
                  </h3>
                  <p class="text-sm leading-6 text-[color:var(--dashboard-muted)]">
                    OAuth connection for activities, token refresh, and rate-limit-aware caching.
                  </p>
                </div>

                <div class="mt-5 space-y-3 text-sm leading-6 text-[color:var(--dashboard-muted)]">
                  <p>{provider_summary(@integrations[:strava], "No Strava account connected.")}</p>
                  <p :if={provider_error(@integrations[:strava])} class="text-[#9a4223]">
                    {provider_error(@integrations[:strava])}
                  </p>
                </div>

                <div class="mt-6 flex gap-3">
                  <.link
                    id="strava-connect-button"
                    href={~p"/auth/strava"}
                    class="dashboard-refresh-button"
                  >
                    {provider_connect_label(@integrations[:strava], "Strava")}
                  </.link>
                  <button
                    :if={provider_connected?(@integrations[:strava])}
                    id="strava-disconnect-button"
                    type="button"
                    phx-click="disconnect"
                    phx-value-provider="strava"
                    class="inline-flex items-center rounded-full border border-[color:var(--dashboard-border)] px-4 py-2 text-sm font-semibold text-[color:var(--dashboard-ink)] transition hover:bg-white/60"
                  >
                    Disconnect
                  </button>
                </div>
              </section>

              <section id="provider-card-habitify" class="provider-card">
                <div class="space-y-2">
                  <p class="dashboard-kicker">Habitify</p>
                  <h3 class="text-xl font-semibold text-[color:var(--dashboard-ink)]">
                    Habit completion
                  </h3>
                  <p class="text-sm leading-6 text-[color:var(--dashboard-muted)]">
                    Save or rotate your Habitify API key to show daily habit completion cards.
                  </p>
                </div>

                <div class="mt-5 space-y-3 text-sm leading-6 text-[color:var(--dashboard-muted)]">
                  <p>{provider_summary(@integrations[:habitify], "No Habitify API key saved.")}</p>
                  <p :if={provider_error(@integrations[:habitify])} class="text-[#9a4223]">
                    {provider_error(@integrations[:habitify])}
                  </p>
                </div>

                <.form
                  for={@habitify_form}
                  id="habitify-settings-form"
                  phx-submit="save_habitify"
                  class="mt-6 space-y-4"
                >
                  <.input
                    field={@habitify_form[:api_key]}
                    type="password"
                    label="Habitify API key"
                    value=""
                  />

                  <div class="flex gap-3">
                    <button
                      id="habitify-save-button"
                      type="submit"
                      class="dashboard-refresh-button"
                    >
                      Save Habitify key
                    </button>
                    <button
                      :if={provider_connected?(@integrations[:habitify])}
                      id="habitify-disconnect-button"
                      type="button"
                      phx-click="disconnect"
                      phx-value-provider="habitify"
                      class="inline-flex items-center rounded-full border border-[color:var(--dashboard-border)] px-4 py-2 text-sm font-semibold text-[color:var(--dashboard-ink)] transition hover:bg-white/60"
                    >
                      Disconnect
                    </button>
                  </div>
                </.form>
              </section>
            </div>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("validate_dashboard", %{"dashboard" => dashboard_params}, socket) do
    user = load_user(socket)

    dashboard_form =
      user
      |> Accounts.change_dashboard_settings(dashboard_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form(as: :dashboard)

    {:noreply, assign(socket, :dashboard_form, dashboard_form)}
  end

  def handle_event("save_dashboard", %{"dashboard" => dashboard_params}, socket) do
    user = load_user(socket)

    case Accounts.update_dashboard_settings(user, dashboard_params) do
      {:ok, user} ->
        user = Accounts.get_user_with_dashboard!(user.id)

        {:noreply,
         socket
         |> put_flash(:info, "Dashboard settings saved.")
         |> assign_state(user, Dashboard.snapshot_from_record(user.dashboard_snapshot))}

      {:error, changeset} ->
        {:noreply, assign(socket, :dashboard_form, to_form(changeset, as: :dashboard))}
    end
  end

  def handle_event("save_habitify", %{"habitify" => %{"api_key" => api_key}}, socket) do
    user = load_user(socket)

    case Habitify.verify_api_key(api_key) do
      {:ok, _habits} ->
        {:ok, _integration} =
          Accounts.connect_integration(
            user,
            :habitify,
            %{external_username: "Habitify"},
            %{"api_key" => api_key}
          )

        Dashboard.request_refresh(user.id, force: true)
        fresh_user = Accounts.get_user_with_dashboard!(user.id)

        {:noreply,
         socket
         |> put_flash(:info, "Habitify connected.")
         |> assign_state(
           fresh_user,
           Dashboard.snapshot_from_record(fresh_user.dashboard_snapshot)
         )}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("disconnect", %{"provider" => provider}, socket) do
    user = load_user(socket)
    provider_atom = String.to_existing_atom(provider)

    {:ok, _integration} = Accounts.disconnect_integration(user, provider_atom)
    Dashboard.request_refresh(user.id, force: true)
    fresh_user = Accounts.get_user_with_dashboard!(user.id)

    {:noreply,
     socket
     |> put_flash(:info, "#{String.capitalize(provider)} disconnected.")
     |> assign_state(fresh_user, Dashboard.snapshot_from_record(fresh_user.dashboard_snapshot))}
  end

  def handle_event("refresh_dashboard", _params, socket) do
    user = load_user(socket)
    Dashboard.request_refresh(user.id, force: true)

    {:noreply, put_flash(socket, :info, "Dashboard refresh started.")}
  end

  @impl true
  def handle_info({:dashboard_snapshot, snapshot}, socket) do
    user = Accounts.get_user_with_dashboard!(socket.assigns.user.id)
    {:noreply, assign_state(socket, user, snapshot)}
  end

  defp assign_state(socket, user, snapshot) do
    assign(socket,
      page_title: "Dashboard settings",
      user: user,
      snapshot: snapshot,
      integrations: user.integrations |> Map.new(&{&1.provider, &1}),
      dashboard_form:
        user
        |> Accounts.change_dashboard_settings(
          %{
            "slug" => user.slug,
            "publish" => User.published?(user)
          },
          validate_unique: false
        )
        |> to_form(as: :dashboard),
      habitify_form: to_form(%{"api_key" => ""}, as: :habitify)
    )
  end

  defp load_user(socket) do
    Accounts.get_user_with_dashboard!(socket.assigns.current_scope.user.id)
  end

  defp connected_provider_count(integrations) do
    Enum.count(integrations, fn {_provider, integration} -> provider_connected?(integration) end)
  end

  defp provider_connected?(nil), do: false
  defp provider_connected?(integration), do: integration.status == :connected

  defp provider_connect_label(nil, provider), do: "Connect #{provider}"

  defp provider_connect_label(integration, provider) do
    if(provider_connected?(integration), do: "Reconnect #{provider}", else: "Connect #{provider}")
  end

  defp provider_summary(nil, fallback), do: fallback

  defp provider_summary(integration, fallback) do
    cond do
      provider_connected?(integration) and integration.external_username ->
        "Connected as #{integration.external_username}."

      provider_connected?(integration) ->
        "Connected."

      true ->
        fallback
    end
  end

  defp provider_error(nil), do: nil
  defp provider_error(%{last_error: nil}), do: nil
  defp provider_error(%{last_error: message}), do: message

  defp refresh_time_copy(nil), do: "Waiting for first sync"

  defp refresh_time_copy(%DateTime{} = updated_at),
    do: Calendar.strftime(updated_at, "%b %-d, %H:%M UTC")

  defp app_snapshot_copy(%{refreshing?: true}), do: "Refreshing live data..."
  defp app_snapshot_copy(%{updated_at: nil}), do: "Waiting for the first snapshot..."

  defp app_snapshot_copy(%{updated_at: updated_at}),
    do: "Last synced #{refresh_time_copy(updated_at)}"
end
