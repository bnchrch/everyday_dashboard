defmodule EverydayDash.Repo.Migrations.CreateStravaTokenRecords do
  use Ecto.Migration

  def change do
    create table(:strava_token_records, primary_key: false) do
      add :service, :string, primary_key: true
      add :access_token, :text, null: false
      add :refresh_token, :text, null: false
      add :expires_at, :bigint, null: false

      timestamps(type: :utc_datetime_usec)
    end
  end
end
