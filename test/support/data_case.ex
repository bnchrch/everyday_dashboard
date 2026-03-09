defmodule EverydayDash.DataCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      alias EverydayDash.Repo
      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import EverydayDash.DataCase
    end
  end

  setup tags do
    if Process.whereis(EverydayDash.Repo) do
      pid = Ecto.Adapters.SQL.Sandbox.start_owner!(EverydayDash.Repo, shared: not tags[:async])
      on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    end

    :ok
  end
end
