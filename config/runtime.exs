import Config

parse_integer = fn env_var, default ->
  case System.get_env(env_var, Integer.to_string(default)) |> Integer.parse() do
    {value, ""} -> value
    _ -> default
  end
end

parse_csv = fn env_var ->
  env_var
  |> System.get_env("")
  |> String.split(",", trim: true)
  |> Enum.map(&String.trim/1)
  |> Enum.reject(&(&1 == ""))
end

config :everyday_dash, EverydayDash.Dashboard,
  refresh_ttl_ms: parse_integer.("DASHBOARD_REFRESH_TTL_MS", 900_000),
  graph_days: parse_integer.("DASHBOARD_GRAPH_DAYS", 30),
  average_window_days: 7,
  github: %{
    client_id: System.get_env("GITHUB_CLIENT_ID"),
    client_secret: System.get_env("GITHUB_CLIENT_SECRET"),
    authorize_url: "https://github.com/login/oauth/authorize",
    token_url: "https://github.com/login/oauth/access_token",
    api_url: "https://api.github.com/graphql"
  },
  habitify: %{
    base_url: System.get_env("HABITIFY_BASE_URL", "https://api.habitify.me")
  },
  strava: %{
    client_id: System.get_env("STRAVA_CLIENT_ID"),
    client_secret: System.get_env("STRAVA_CLIENT_SECRET"),
    cache_ttl_ms: parse_integer.("STRAVA_CACHE_TTL_MS", 900_000),
    authorize_url: "https://www.strava.com/oauth/authorize",
    token_url: "https://www.strava.com/oauth/token",
    activities_url: "https://www.strava.com/api/v3/athlete/activities"
  }

credentials_secret =
  System.get_env("CREDENTIALS_ENCRYPTION_SECRET") ||
    if(config_env() == :prod, do: nil, else: "dev-credentials-secret-0123456789")

if is_nil(credentials_secret) do
  raise "environment variable CREDENTIALS_ENCRYPTION_SECRET is missing"
end

config :everyday_dash, EverydayDash.Credentials, secret: credentials_secret

database_url = System.get_env("DATABASE_URL")

if database_url do
  ssl? = System.get_env("ECTO_SSL", "true") not in ["false", "0"]

  config :everyday_dash, EverydayDash.Repo,
    url: database_url,
    ssl: ssl?,
    ssl_opts:
      if(ssl?,
        do: [verify: :verify_none, cacerts: :public_key.cacerts_get()],
        else: []
      ),
    pool_size: parse_integer.("POOL_SIZE", 2),
    socket_options:
      if(System.get_env("ECTO_IPV6", "false") in ["true", "1"], do: [:inet6], else: [])
else
  if config_env() == :prod do
    raise "environment variable DATABASE_URL is missing"
  end
end

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/everyday_dash start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :everyday_dash, EverydayDashWeb.Endpoint, server: true
end

config :everyday_dash, EverydayDashWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  additional_hosts = parse_csv.("PHX_ADDITIONAL_HOSTS")
  allowed_hosts = [host | additional_hosts] |> Enum.uniq()

  config :everyday_dash, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :everyday_dash, EverydayDashWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    check_origin: Enum.map(allowed_hosts, &"//#{&1}"),
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :everyday_dash, EverydayDashWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :everyday_dash, EverydayDashWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :everyday_dash, EverydayDash.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
