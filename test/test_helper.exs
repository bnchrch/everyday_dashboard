ExUnit.start()

if Process.whereis(EverydayDash.Repo) do
  Ecto.Adapters.SQL.Sandbox.mode(EverydayDash.Repo, :manual)
end
