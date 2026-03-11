defmodule EverydayDash.Dashboard.SnapshotRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  schema "dashboard_snapshots" do
    field(:payload, :map, default: %{})
    field(:refreshed_at, :utc_datetime_usec)
    field(:refreshing, :boolean, default: false)
    field(:last_error, :string)

    belongs_to(:user, EverydayDash.Accounts.User)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [:payload, :refreshed_at, :refreshing, :last_error, :user_id])
    |> validate_required([:payload, :refreshing, :user_id])
    |> unique_constraint(:user_id)
  end
end
