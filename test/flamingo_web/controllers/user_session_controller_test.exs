defmodule FlamingoWeb.UserSessionControllerTest do
  use FlamingoWeb.ConnCase, async: true

  import Flamingo.AccountsFixtures
  alias Flamingo.Accounts

  setup do
    %{user: user_fixture()}
  end

  # Starts a sign-in and returns the conn holding its session, plus its state.
  defp start_google_sign_in(conn) do
    conn = get(conn, ~p"/auth/google")
    %URI{query: query} = URI.parse(redirected_to(conn))
    {conn, URI.decode_query(query)["state"]}
  end

  defp google_callback(conn, state, claims),
    do: get(conn, ~p"/auth/google/callback", %{state: state, code: JSON.encode!(claims)})

  describe "DELETE /users/account" do
    test "deletes only the current account and revokes all its tokens and sessions", %{
      conn: conn,
      user: user
    } do
      other = user_fixture()
      other_token = Accounts.generate_user_session_token(other)
      session_token = Accounts.generate_user_session_token(user)
      topic = "users_sessions:#{Base.url_encode64(session_token)}"
      FlamingoWeb.Endpoint.subscribe(topic)

      conn =
        conn
        |> log_in_user(user)
        |> delete(~p"/users/account", %{confirm: "true", user_id: other.id})

      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      refute Flamingo.Repo.get(Accounts.User, user.id)
      refute Accounts.get_user_by_session_token(session_token)
      refute Flamingo.Repo.get_by(Accounts.UserToken, user_id: user.id)
      assert Accounts.get_user_by_session_token(other_token)
      assert_receive %Phoenix.Socket.Broadcast{topic: ^topic, event: "disconnect"}
    end

    test "requires both a confirmation and a recent sign-in", %{conn: conn, user: user} do
      missing_confirmation =
        conn |> log_in_user(user) |> delete(~p"/users/account", %{confirm: "false"})

      assert redirected_to(missing_confirmation) == ~p"/users/settings"
      assert Flamingo.Repo.get(Accounts.User, user.id)

      stale =
        conn
        |> log_in_user(user,
          token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)
        )
        |> delete(~p"/users/account", %{confirm: "true"})

      assert redirected_to(stale) == ~p"/users/log-in"
      assert Flamingo.Repo.get(Accounts.User, user.id)
    end

    test "rejects guests", %{conn: conn} do
      assert conn |> delete(~p"/users/account", %{confirm: "true"}) |> redirected_to() ==
               ~p"/users/log-in"
    end
  end

  describe "Google sign-in" do
    test "creates the account on first sign-in and logs the player in", %{conn: conn} do
      {conn, state} = start_google_sign_in(conn)
      assert redirected_to(conn) =~ "https://accounts.google.test/"

      claims = google_claims()
      conn = google_callback(conn, state, claims)

      assert redirected_to(conn) == ~p"/"
      assert {user, _} = Accounts.get_user_by_session_token(get_session(conn, :user_token))
      assert user.google_sub == claims["sub"]
      assert user.email == claims["email"]
      refute get_session(conn, :google_session_params)
    end

    test "returns to the same account and picks up a changed email", %{conn: conn, user: user} do
      {:ok, user} = Accounts.update_avatar(Flamingo.Accounts.Scope.for_user(user), %{})
      {conn, state} = start_google_sign_in(conn)
      conn = google_callback(conn, state, google_claims(%{"sub" => user.google_sub}))

      assert {signed_in, _} = Accounts.get_user_by_session_token(get_session(conn, :user_token))
      assert signed_in.id == user.id
      assert signed_in.email != user.email
      assert signed_in.avatar == user.avatar
    end

    test "refuses forged, cancelled, unverified and unstarted sign-ins", %{conn: conn} do
      count = Flamingo.Repo.aggregate(Accounts.User, :count)

      {started, state} = start_google_sign_in(conn)

      for conn <- [
            google_callback(started, "forged-state", google_claims()),
            get(started, ~p"/auth/google/callback", %{state: state, error: "access_denied"}),
            google_callback(started, state, google_claims(%{"email_verified" => false})),
            google_callback(conn, state, google_claims())
          ] do
        assert redirected_to(conn) == ~p"/users/log-in"
        refute get_session(conn, :user_token)
        assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "didn't complete"
      end

      assert Flamingo.Repo.aggregate(Accounts.User, :count) == count
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
