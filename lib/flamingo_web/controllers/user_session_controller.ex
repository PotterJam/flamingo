defmodule FlamingoWeb.UserSessionController do
  use FlamingoWeb, :controller

  alias Flamingo.Accounts
  alias FlamingoWeb.UserAuth

  # magic link login
  def create(conn, %{"user" => %{"token" => token}}) do
    case Accounts.login_user_by_magic_link(token) do
      {:ok, {user, tokens_to_disconnect}} ->
        UserAuth.disconnect_sessions(tokens_to_disconnect)

        conn
        |> put_flash(:success, "Logged in.")
        |> UserAuth.log_in_user(user)

      _ ->
        conn
        |> put_flash(:error, "The link is invalid or it has expired.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "Use an email link to log in.")
    |> redirect(to: ~p"/users/log-in")
  end

  def delete_account(conn, %{"confirm" => "true"}) do
    case Accounts.delete_user(conn.assigns.current_scope) do
      {:ok, tokens} ->
        UserAuth.disconnect_sessions(tokens)

        conn
        |> put_flash(:success, "Your account has been deleted. You can still play as a guest.")
        |> UserAuth.log_out_user()

      {:error, :reauthenticate} ->
        conn
        |> put_flash(
          :error,
          "Please sign in with a fresh email link before deleting your account."
        )
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
end
