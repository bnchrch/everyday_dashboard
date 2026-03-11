import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :everyday_dash, EverydayDashWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "qezWIKOkaLzmBNb0fb9tGI933IaESakb8yjj9uMt9pxrdoEgzaL5IhG8kthMTMnh",
  server: false

# In test we don't send emails
config :everyday_dash, EverydayDash.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

config :everyday_dash, EverydayDash.Repo,
  username: System.get_env("PGUSER") || System.get_env("USER", "postgres"),
  password: System.get_env("PGPASSWORD", ""),
  hostname: System.get_env("PGHOST", "127.0.0.1"),
  database: System.get_env("PGDATABASE", "everyday_dash_test"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :everyday_dash, EverydayDash.Dashboard,
  async_refresh?: false,
  auto_refresh_on_mount?: false
