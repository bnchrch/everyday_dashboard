defmodule EverydayDash.Accounts.UserIntegration do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @providers [:github, :strava, :habitify]
  @statuses [:disconnected, :connected, :error]

  schema "user_integrations" do
    field(:provider, Ecto.Enum, values: @providers)
    field(:status, Ecto.Enum, values: @statuses, default: :disconnected)
    field(:external_id, :string)
    field(:external_username, :string)
    field(:credential_ciphertext, :string, redact: true)
    field(:token_expires_at, :utc_datetime_usec)
    field(:backoff_until, :utc_datetime_usec)
    field(:rate_limit_headers, :map, default: %{})
    field(:cache_payload, :map, default: %{})
    field(:meta, :map, default: %{})
    field(:last_error, :string)
    field(:last_synced_at, :utc_datetime_usec)

    belongs_to(:user, EverydayDash.Accounts.User)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(integration, attrs) do
    integration
    |> cast(attrs, [
      :provider,
      :status,
      :external_id,
      :external_username,
      :credential_ciphertext,
      :token_expires_at,
      :backoff_until,
      :rate_limit_headers,
      :cache_payload,
      :meta,
      :last_error,
      :last_synced_at,
      :user_id
    ])
    |> validate_required([:provider, :status, :user_id])
    |> unique_constraint([:user_id, :provider])
  end

  def provider_options, do: @providers
end
