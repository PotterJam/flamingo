defmodule FlamingoWeb.UserLive.ConfirmationTest do
  use FlamingoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Flamingo.AccountsFixtures

  alias Flamingo.Accounts

  setup do
    %{unconfirmed_user: unconfirmed_user_fixture(), confirmed_user: user_fixture()}
  end

  describe "Confirm user" do
    test "a plain link preview does not consume the token or log in", %{
      conn: conn,
      unconfirmed_user: user
    } do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      conn = get(conn, ~p"/users/log-in/#{token}")
      assert conn.status == 200
      refute get_session(conn, :user_token)
      refute conn.resp_cookies["_flamingo_web_user_remember_me"]
      assert Accounts.get_user_by_magic_link_token(token).id == user.id
      refute Accounts.get_user!(user.id).confirmed_at
    end

    test "connected browser automatically submits without session choices", %{
      conn: conn,
      confirmed_user: user
    } do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      {:ok, lv, _html} = live(conn, ~p"/users/log-in/#{token}")
      assert has_element?(lv, "#magic-link-login[hidden][phx-trigger-action]")
      refute has_element?(lv, "#magic-link-login button")
      refute has_element?(lv, "[name='user[remember_me]']")
    end

    test "reauthentication also returns home with a remembered session", %{
      conn: conn,
      confirmed_user: user
    } do
      conn = log_in_user(conn, user)

      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      {:ok, lv, _html} = live(conn, ~p"/users/log-in/#{token}")
      conn = lv |> form("#magic-link-login") |> follow_trigger_action(conn)
      assert redirected_to(conn) == ~p"/"
      assert conn.resp_cookies["_flamingo_web_user_remember_me"]
    end

    test "confirms the given token once", %{conn: conn, unconfirmed_user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      {:ok, lv, _html} = live(conn, ~p"/users/log-in/#{token}")

      conn = lv |> form("#magic-link-login") |> follow_trigger_action(conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :success) =~
               "Logged in."

      assert Accounts.get_user!(user.id).confirmed_at
      # we are logged in now
      assert get_session(conn, :user_token)
      assert conn.resp_cookies["_flamingo_web_user_remember_me"]
      assert redirected_to(conn) == ~p"/"

      # log out, new conn
      conn = build_conn()

      {:ok, login, _html} =
        live(conn, ~p"/users/log-in/#{token}")
        |> follow_redirect(conn, ~p"/users/log-in")

      assert has_element?(login, "#flash-error", "Magic link is invalid or it has expired")
    end

    test "logs confirmed user in without changing confirmed_at", %{
      conn: conn,
      confirmed_user: user
    } do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      {:ok, lv, _html} = live(conn, ~p"/users/log-in/#{token}")

      conn = lv |> form("#magic-link-login") |> follow_trigger_action(conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :success) =~
               "Logged in."

      assert Accounts.get_user!(user.id).confirmed_at == user.confirmed_at
      assert conn.resp_cookies["_flamingo_web_user_remember_me"]

      # log out, new conn
      conn = build_conn()

      {:ok, login, _html} =
        live(conn, ~p"/users/log-in/#{token}")
        |> follow_redirect(conn, ~p"/users/log-in")

      assert has_element?(login, "#flash-error", "Magic link is invalid or it has expired")
    end

    test "raises error for invalid token", %{conn: conn} do
      {:ok, login, _html} =
        live(conn, ~p"/users/log-in/invalid-token")
        |> follow_redirect(conn, ~p"/users/log-in")

      assert has_element?(login, "#flash-error", "Magic link is invalid or it has expired")
    end
  end
end
