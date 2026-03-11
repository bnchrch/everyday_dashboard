defmodule EverydayDash.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false

  alias EverydayDash.Accounts.{User, UserIntegration, UserNotifier, UserToken}
  alias EverydayDash.Credentials
  alias EverydayDash.Repo

  ## Database getters

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  def get_user!(id), do: Repo.get!(User, id)

  def get_user_with_dashboard!(%User{id: id}), do: get_user_with_dashboard!(id)

  def get_user_with_dashboard!(id) do
    id
    |> get_user!()
    |> preload_dashboard_data()
  end

  def get_user_by_slug(slug) when is_binary(slug) do
    Repo.get_by(User, slug: normalize_slug(slug))
  end

  def get_published_user_by_slug(slug) when is_binary(slug) do
    User
    |> where([user], user.slug == ^normalize_slug(slug))
    |> where([user], not is_nil(user.dashboard_published_at))
    |> Repo.one()
    |> maybe_preload_dashboard_data()
  end

  ## User registration

  def change_user_registration(user \\ %User{}, attrs \\ %{}, opts \\ []) do
    User.registration_changeset(user, attrs, opts)
  end

  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  ## Settings

  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  def change_dashboard_settings(user, attrs \\ %{}, opts \\ []) do
    publish? = Keyword.get(opts, :publish?, publish_param(attrs))
    validate_unique = Keyword.get(opts, :validate_unique, true)

    user
    |> User.dashboard_settings_changeset(attrs,
      publish?: publish?,
      validate_unique: validate_unique
    )
  end

  def update_dashboard_settings(user, attrs) do
    user
    |> change_dashboard_settings(attrs)
    |> Repo.update()
  end

  ## Integrations

  def list_integrations(%User{id: user_id}) do
    Repo.all(
      from(integration in UserIntegration,
        where: integration.user_id == ^user_id,
        order_by: [asc: integration.provider]
      )
    )
  end

  def integrations_by_provider(%User{} = user) do
    user
    |> list_integrations()
    |> Map.new(&{&1.provider, &1})
  end

  def get_integration(%User{id: user_id}, provider) do
    Repo.get_by(UserIntegration, user_id: user_id, provider: provider)
  end

  def update_integration(%UserIntegration{} = integration, attrs) do
    integration
    |> UserIntegration.changeset(attrs)
    |> Repo.update()
  end

  def upsert_integration(%User{} = user, provider, attrs) when is_atom(provider) do
    integration =
      get_integration(user, provider) ||
        %UserIntegration{user_id: user.id, provider: provider}

    attrs =
      attrs
      |> Map.new()
      |> Map.put(:user_id, user.id)
      |> Map.put(:provider, provider)

    integration
    |> UserIntegration.changeset(attrs)
    |> Repo.insert_or_update()
  end

  def connect_integration(%User{} = user, provider, attrs \\ %{}, credentials \\ %{}) do
    with {:ok, credential_ciphertext} <- encrypt_credentials(credentials) do
      attrs =
        attrs
        |> Map.new()
        |> Map.put(:status, :connected)
        |> Map.put(:credential_ciphertext, credential_ciphertext)
        |> Map.put(:last_error, nil)

      upsert_integration(user, provider, attrs)
    end
  end

  def disconnect_integration(%User{} = user, provider) do
    upsert_integration(user, provider, %{
      status: :disconnected,
      external_id: nil,
      external_username: nil,
      credential_ciphertext: nil,
      token_expires_at: nil,
      backoff_until: nil,
      rate_limit_headers: %{},
      cache_payload: %{},
      meta: %{},
      last_error: nil,
      last_synced_at: nil
    })
  end

  def decrypt_integration_credentials(%UserIntegration{credential_ciphertext: nil}),
    do: {:ok, %{}}

  def decrypt_integration_credentials(%UserIntegration{credential_ciphertext: ciphertext}) do
    Credentials.decrypt(ciphertext)
  end

  ## Session

  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Helpers

  def preload_dashboard_data(%User{} = user) do
    Repo.preload(user, [:integrations, :dashboard_snapshot])
  end

  defp maybe_preload_dashboard_data(nil), do: nil
  defp maybe_preload_dashboard_data(%User{} = user), do: preload_dashboard_data(user)

  defp encrypt_credentials(credentials) when map_size(credentials) == 0, do: {:ok, nil}
  defp encrypt_credentials(credentials), do: Credentials.encrypt(credentials)

  defp publish_param(attrs) do
    value = Map.get(attrs, "publish", Map.get(attrs, :publish, false))
    truthy?(value)
  end

  defp truthy?(value) when value in [true, "true", "on", "1", 1], do: true
  defp truthy?(_value), do: false

  defp normalize_slug(slug) do
    slug
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire =
          Repo.all(from(token in UserToken, where: token.user_id == ^user.id))

        Repo.delete_all(
          from(token in UserToken, where: token.id in ^Enum.map(tokens_to_expire, & &1.id))
        )

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
