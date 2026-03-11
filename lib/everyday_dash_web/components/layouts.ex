defmodule EverydayDashWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use EverydayDashWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :show_header, :boolean, default: true, doc: "whether to render the default header"
  attr :main_class, :string, default: "px-4 py-20 sm:px-6 lg:px-8", doc: "main element classes"
  attr :inner_class, :string, default: "mx-auto max-w-2xl space-y-4", doc: "inner wrapper classes"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header
      :if={@show_header}
      class="mx-auto flex w-full max-w-6xl items-center justify-between px-4 py-6 sm:px-6 lg:px-8"
    >
      <.link href={~p"/"} class="flex items-center gap-3">
        <img src={~p"/images/logo.svg"} width="32" />
        <div>
          <p class="text-xs font-semibold uppercase tracking-[0.24em] text-black/45">Everyday Dash</p>
          <p class="text-sm font-semibold text-black/75">
            Build a public dashboard from private systems
          </p>
        </div>
      </.link>

      <div class="flex items-center gap-3">
        <.theme_toggle />
        <%= if @current_scope && @current_scope.user do %>
          <.link
            navigate={~p"/app"}
            class="rounded-full border border-black/10 px-4 py-2 text-sm font-semibold text-black/70 transition hover:bg-black/5"
          >
            App
          </.link>
        <% else %>
          <.link
            href={~p"/users/log-in"}
            class="rounded-full border border-black/10 px-4 py-2 text-sm font-semibold text-black/70 transition hover:bg-black/5"
          >
            Log in
          </.link>
          <.link
            href={~p"/users/register"}
            class="rounded-full bg-black px-4 py-2 text-sm font-semibold text-white transition hover:bg-black/85"
          >
            Create account
          </.link>
        <% end %>
      </div>
    </header>

    <main class={@main_class}>
      <div class={@inner_class}>
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
