defmodule EverydayDash.Repo.Migrations.CreateStravaCacheRecords do
  use Ecto.Migration

  def change do
    create table(:strava_cache_records, primary_key: false) do
      add(:service, :string, primary_key: true)
      add(:counts, :map, null: false, default: %{})
      add(:graph_days, :integer, null: false)
      add(:window_days, :integer, null: false)
      add(:fetched_at, :utc_datetime_usec, null: false)
      add(:backoff_until, :utc_datetime_usec)
      add(:rate_limit_headers, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end
  end
end
