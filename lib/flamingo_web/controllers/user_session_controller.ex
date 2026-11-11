defmodule FlamingoWeb.UserSessionController do
  use FlamingoWeb, :controller

  alias Flamingo.Accounts
  alias FlamingoWeb.UserAuth

  @doc "Sends the player to Google to sign in."
  def google_request(conn, _params) do
    with {:ok, config} <- google_config(),
         {:ok, %{url: url, session_params: session_params}} <-
           google_strategy().authorize_url(config) do
      conn
      |> put_session(:google_session_params, session_params)
      |> redirect(external: url)
    else
      _ -> sign_in_failed(conn)
    end
  end

  @doc "Handles Google sending the player back after they sign in."
  def google_callback(conn, params) do
    session_params = get_session(conn, :google_session_params)
    conn = delete_session(conn, :google_session_params)

    with %{} <- session_params,
         {:ok, config} <- google_config(),
         {:ok, %{user: claims}} <-
           google_strategy().callback(
             Keyword.put(config, :session_params, session_params),
             params
           ),
         {:ok, user} <- Accounts.sign_in_with_google(claims) do
      conn
      |> put_flash(:success, "Signed in.")
      |> UserAuth.log_in_user(user)
    else
      _ -> sign_in_failed(conn)
    end
  end

  @doc """
  Development only: signs in as the test account for `email` without Google,
  creating it on first use, then returns to `return_to` if it is a local path.
  """
  def dev_log_in(conn, %{"email" => email} = params) do
    {:ok, user} =
      Accounts.sign_in_with_google(%{
        "sub" => "dev:" <> email,
        "email" => email,
        "email_verified" => true
      })

    conn
    |> put_flash(:success, "Signed in as #{email}.")
    |> UserAuth.log_in_user(user, local_path(params["return_to"]))
  end

  # Only same-site paths, so the route can't be used to redirect elsewhere.
  defp local_path("/" <> rest = path) do
    if String.starts_with?(rest, ["/", "\\"]), do: ~p"/", else: path
  end

  defp local_path(_), do: ~p"/"

  def delete_account(conn, %{"confirm" => "true"}) do
    case Accounts.delete_user(conn.assigns.current_scope) do
      {:ok, tokens} ->
        UserAuth.disconnect_sessions(tokens)

        conn
        |> put_flash(:success, "Your account has been deleted. You can still play as a guest.")
        |> UserAuth.log_out_user()

      {:error, :reauthenticate} ->
        conn
        |> put_flash(:error, "Please sign in again before deleting your account.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  def delete_account(conn, _params) do
    conn
    |> put_flash(:error, "Please confirm that you want to delete your account.")
    |> redirect(to: ~p"/users/settings")
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:success, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end

  defp google_config do
    case Application.get_env(:flamingo, :google_oauth) do
      nil ->
        :not_configured

      config ->
        {:ok,
         Keyword.merge(config,
           redirect_uri: url(~p"/auth/google/callback"),
           code_verifier: true,
           nonce: true
         )}
    end
  end

  defp google_strategy,
    do: Application.get_env(:flamingo, :google_strategy, Assent.Strategy.Google)

  defp sign_in_failed(conn) do
    conn
    |> put_flash(:error, "Google sign-in didn't complete. Please try again.")
    |> redirect(to: ~p"/users/log-in")
  end
end
