defmodule EverydayDash.Dashboard.StravaTokenRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:service, :string, autogenerate: false}
  schema "strava_token_records" do
    field(:access_token, :string)
    field(:refresh_token, :string)
    field(:expires_at, :integer)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:service, :access_token, :refresh_token, :expires_at])
    |> validate_required([:service, :access_token, :refresh_token, :expires_at])
  end
end
