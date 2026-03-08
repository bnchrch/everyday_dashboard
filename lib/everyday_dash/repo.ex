defmodule EverydayDash.Repo do
  use Ecto.Repo,
    otp_app: :everyday_dash,
    adapter: Ecto.Adapters.Postgres
end
