defmodule EverydayDashWeb.IntegrationAuthController do
  use EverydayDashWeb, :controller

  alias EverydayDash.Accounts
  alias EverydayDash.Dashboard
  alias EverydayDash.Dashboard.Sources.{GitHub, Strava}

  def github(conn, _params) do
    state = random_state()

    case GitHub.authorization_url(state, url(~p"/auth/github/callback")) do
      {:ok, authorize_url} ->
        conn
        |> put_session(:github_oauth_state, state)
        |> redirect(external: authorize_url)

      {:error, message} ->
        conn
        |> put_flash(:error, message)
        |> redirect(to: ~p"/app")
    end
  end

  def github_callback(conn, %{"error" => error}) do
    conn
    |> put_flash(:error, "GitHub authorization failed: #{error}.")
    |> redirect(to: ~p"/app")
  end

  def github_callback(conn, %{"code" => code, "state" => state}) do
    user = current_user!(conn)

    with :ok <- validate_state(get_session(conn, :github_oauth_state), state),
         {:ok, auth} <- GitHub.exchange_code(code, url(~p"/auth/github/callback")),
         {:ok, profile} <- GitHub.fetch_profile(auth.access_token),
         {:ok, _integration} <-
           Accounts.connect_integration(
             user,
             :github,
             %{
               external_id: profile.id,
               external_username: profile.login
             },
             %{"access_token" => auth.access_token}
           ) do
      Dashboard.request_refresh(user.id, force: true)

      conn
      |> delete_session(:github_oauth_state)
      |> put_flash(:info, "GitHub connected.")
      |> redirect(to: ~p"/app")
    else
      {:error, message} ->
        conn
        |> put_flash(:error, message)
        |> redirect(to: ~p"/app")
    end
  end

  def strava(conn, _params) do
    state = random_state()

    case Strava.authorization_url(state, url(~p"/auth/strava/callback")) do
      {:ok, authorize_url} ->
        conn
        |> put_session(:strava_oauth_state, state)
        |> redirect(external: authorize_url)

      {:error, message} ->
        conn
        |> put_flash(:error, message)
        |> redirect(to: ~p"/app")
    end
  end

  def strava_callback(conn, %{"error" => error}) do
    conn
    |> put_flash(:error, "Strava authorization failed: #{error}.")
    |> redirect(to: ~p"/app")
  end

  def strava_callback(conn, %{"code" => code, "state" => state}) do
    user = current_user!(conn)

    with :ok <- validate_state(get_session(conn, :strava_oauth_state), state),
         {:ok, auth} <- Strava.exchange_code(code, url(~p"/auth/strava/callback")),
         {:ok, _integration} <-
           Accounts.connect_integration(
             user,
             :strava,
             %{
               external_id: to_string(get_in(auth, [:athlete, "id"])),
               external_username: athlete_label(auth.athlete),
               meta: %{athlete: auth.athlete},
               token_expires_at: unix_to_datetime(auth.expires_at)
             },
             %{
               "access_token" => auth.access_token,
               "refresh_token" => auth.refresh_token,
               "expires_at" => auth.expires_at
             }
           ) do
      Dashboard.request_refresh(user.id, force: true)

      conn
      |> delete_session(:strava_oauth_state)
      |> put_flash(:info, "Strava connected.")
      |> redirect(to: ~p"/app")
    else
      {:error, message} ->
        conn
        |> put_flash(:error, message)
        |> redirect(to: ~p"/app")
    end
  end

  defp validate_state(expected_state, actual_state)
       when is_binary(expected_state) and is_binary(actual_state) and
              expected_state == actual_state,
       do: :ok

  defp validate_state(_expected_state, _actual_state),
    do: {:error, "OAuth state validation failed."}

  defp random_state do
    24
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp athlete_label(athlete) do
    athlete["username"] ||
      [athlete["firstname"], athlete["lastname"]]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(" ")
      |> case do
        "" -> "Strava athlete"
        label -> label
      end
  end

  defp unix_to_datetime(nil), do: nil
  defp unix_to_datetime(unix) when is_integer(unix), do: DateTime.from_unix!(unix)

  defp current_user!(conn) do
    %Accounts.User{} = conn.assigns.current_scope.user
  end
end
