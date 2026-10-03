defmodule FlamingoWeb.UserSessionControllerTest do
  use FlamingoWeb.ConnCase, async: true

  import Flamingo.AccountsFixtures
  alias Flamingo.Accounts

  setup do
    %{unconfirmed_user: unconfirmed_user_fixture(), user: user_fixture()}
  end

  describe "DELETE /users/account" do
    test "deletes only the current account and revokes all its tokens and sessions", %{
      conn: conn,
      user: user
    } do
      other = user_fixture()
      other_token = Accounts.generate_user_session_token(other)
      {magic_link, _} = generate_user_magic_link_token(user)
      session_token = Accounts.generate_user_session_token(user)
      topic = "users_sessions:#{Base.url_encode64(session_token)}"
      FlamingoWeb.Endpoint.subscribe(topic)

      conn =
        conn
        |> log_in_user(user)
        |> delete(~p"/users/account", %{confirm: "true", user_id: other.id})

      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      refute Accounts.get_user_by_email(user.email)
      refute Accounts.get_user_by_session_token(session_token)
      refute Accounts.get_user_by_magic_link_token(magic_link)
      refute Flamingo.Repo.get_by(Accounts.UserToken, user_id: user.id)
      assert Accounts.get_user_by_session_token(other_token)
      assert_receive %Phoenix.Socket.Broadcast{topic: ^topic, event: "disconnect"}
    end

    test "requires both a confirmation and a recent sign-in", %{conn: conn, user: user} do
      missing_confirmation =
        conn |> log_in_user(user) |> delete(~p"/users/account", %{confirm: "false"})

      assert redirected_to(missing_confirmation) == ~p"/users/settings"
      assert Accounts.get_user_by_email(user.email)

      stale =
        conn
        |> log_in_user(user,
          token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)
        )
        |> delete(~p"/users/account", %{confirm: "true"})

      assert redirected_to(stale) == ~p"/users/log-in"
      assert Accounts.get_user_by_email(user.email)
    end

    test "rejects guests", %{conn: conn} do
      assert conn |> delete(~p"/users/account", %{confirm: "true"}) |> redirected_to() ==
               ~p"/users/log-in"
    end
  end

  describe "POST /users/log-in without a magic token" do
    test "rejects email and password credentials", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => "password"}
        })

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Use an email link to log in."
      refute get_session(conn, :user_token)
    end
  end

  describe "POST /users/log-in - magic link" do
    test "logs the user in", %{conn: conn, user: user} do
      {token, _hashed_token} = generate_user_magic_link_token(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => token}
        })

      assert get_session(conn, :user_token)
      assert conn.resp_cookies["_flamingo_web_user_remember_me"]
      assert redirected_to(conn) == ~p"/"

      # The next request resolves the authenticated account from the session.
      conn = get(conn, ~p"/")
      assert conn.status == 200
      assert conn.assigns.current_scope.user.id == user.id
    end

    test "cannot opt out of remembered login with an old parameter", %{conn: conn, user: user} do
      {token, _hashed_token} = generate_user_magic_link_token(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => token, "remember_me" => "false"}
        })

      assert conn.resp_cookies["_flamingo_web_user_remember_me"]
      assert redirected_to(conn) == ~p"/"
    end

    test "returns home even if an old return path is stored", %{conn: conn, user: user} do
      {token, _hashed_token} = generate_user_magic_link_token(user)

      conn =
        conn
        |> init_test_session(user_return_to: "/foo/bar")
        |> post(~p"/users/log-in", %{"user" => %{"token" => token}})

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :success) == "Logged in."
    end

    test "confirms unconfirmed user", %{conn: conn, unconfirmed_user: user} do
      {token, _hashed_token} = generate_user_magic_link_token(user)
      refute user.confirmed_at

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => token}
        })

      assert get_session(conn, :user_token)
      assert conn.resp_cookies["_flamingo_web_user_remember_me"]
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :success) == "Logged in."

      assert Accounts.get_user!(user.id).confirmed_at

      # The next request resolves the authenticated account from the session.
      conn = get(conn, ~p"/")
      assert conn.status == 200
      assert conn.assigns.current_scope.user.id == user.id
    end

    test "redirects to login page when magic link is invalid", %{conn: conn} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => "invalid"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "The link is invalid or it has expired."

      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "rejects malformed token encoding without creating a session", %{conn: conn} do
      conn = post(conn, ~p"/users/log-in", %{"user" => %{"token" => "not+base64!"}})

      assert redirected_to(conn) == ~p"/users/log-in"
      refute get_session(conn, :user_token)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "The link is invalid or it has expired."
    end
  end

  describe "DELETE /users/log-out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :success) =~ "Logged out successfully"
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :success) =~ "Logged out successfully"
    end
  end
end
