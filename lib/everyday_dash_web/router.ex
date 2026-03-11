defmodule EverydayDashWeb.Router do
  use EverydayDashWeb, :router

  import EverydayDashWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {EverydayDashWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", EverydayDashWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", EverydayDashWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:everyday_dash, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: EverydayDashWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", EverydayDashWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/auth/github", IntegrationAuthController, :github
    get "/auth/github/callback", IntegrationAuthController, :github_callback
    get "/auth/strava", IntegrationAuthController, :strava
    get "/auth/strava/callback", IntegrationAuthController, :strava_callback

    live_session :require_authenticated_user,
      on_mount: [{EverydayDashWeb.UserAuth, :require_authenticated}] do
      live "/app", AppLive, :index
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", EverydayDashWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{EverydayDashWeb.UserAuth, :mount_current_scope}] do
      live "/u/:slug", DashboardLive, :show
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
