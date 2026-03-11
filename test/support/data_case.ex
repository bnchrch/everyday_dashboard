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

  @doc """
  A helper that transforms changeset errors into a map of messages.
  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
