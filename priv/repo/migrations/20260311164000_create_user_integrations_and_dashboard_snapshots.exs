defmodule EverydayDash.Repo.Migrations.CreateUserIntegrationsAndDashboardSnapshots do
  use Ecto.Migration

  def change do
    drop_if_exists table(:strava_cache_records)
    drop_if_exists table(:strava_token_records)

    create table(:user_integrations) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :status, :string, null: false, default: "disconnected"
      add :external_id, :string
      add :external_username, :string
      add :credential_ciphertext, :text
      add :token_expires_at, :utc_datetime_usec
      add :backoff_until, :utc_datetime_usec
      add :rate_limit_headers, :map, null: false, default: %{}
      add :cache_payload, :map, null: false, default: %{}
      add :meta, :map, null: false, default: %{}
      add :last_error, :text
      add :last_synced_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:user_integrations, [:user_id, :provider])
    create index(:user_integrations, [:provider, :status])

    create table(:dashboard_snapshots) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :payload, :map, null: false, default: %{}
      add :refreshed_at, :utc_datetime_usec
      add :refreshing, :boolean, null: false, default: false
      add :last_error, :text

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:dashboard_snapshots, [:user_id])
  end
end
