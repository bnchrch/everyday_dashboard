defmodule EverydayDash.Dashboard.StravaCacheRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:service, :string, autogenerate: false}
  schema "strava_cache_records" do
    field(:counts, :map, default: %{})
    field(:graph_days, :integer)
    field(:window_days, :integer)
    field(:fetched_at, :utc_datetime_usec)
    field(:backoff_until, :utc_datetime_usec)
    field(:rate_limit_headers, :map, default: %{})

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :service,
      :counts,
      :graph_days,
      :window_days,
      :fetched_at,
      :backoff_until,
      :rate_limit_headers
    ])
    |> validate_required([:service, :counts, :graph_days, :window_days, :fetched_at])
  end
end
