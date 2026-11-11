defmodule Flamingo.AccountsTest do
  use Flamingo.DataCase

  alias Flamingo.Accounts

  import Flamingo.AccountsFixtures
  alias Flamingo.Accounts.{Scope, User, UserToken}

  test "avatar saves are normalized, preserve drawings, and only update the scoped user" do
    user = user_fixture()
    other = user_fixture()
    drawing = "M 13 4 L 28 9"

    assert {:ok, updated} =
             Accounts.update_avatar(Scope.for_user(user), %{
               "head" => "3",
               "body" => 2,
               "legs" => 99,
               "feet" => 1,
               "head_color" => 6,
               "head_drawing" => drawing,
               "body_drawing" => "<script>",
               "feet_drawing" => String.duplicate("M", 24_001),
               "email" => other.email,
               "user_id" => other.id
             })

    assert updated.avatar == %{
             "head" => 3,
             "body" => 2,
             "legs" => 0,
             "feet" => 1,
             "head_color" => 6,
             "body_color" => 0,
             "legs_color" => 0,
             "feet_color" => 0,
             "head_drawing" => drawing,
             "body_drawing" => "",
             "legs_drawing" => "",
             "feet_drawing" => ""
           }

    assert Repo.get!(User, user.id).avatar == updated.avatar
    assert Repo.get!(User, user.id).email == user.email
    assert Repo.get!(User, other.id).avatar == nil
  end

  describe "sign_in_with_google/1" do
    test "creates one account per Google account and refreshes its email" do
      claims = google_claims()
      assert {:ok, user} = Accounts.sign_in_with_google(claims)
      assert user.google_sub == claims["sub"]

      new_email = unique_user_email()

      assert {:ok, again} =
               Accounts.sign_in_with_google(%{claims | "email" => new_email})

      assert again.id == user.id
      assert again.email == new_email
      assert Repo.aggregate(User, :count) == 1
    end

    test "keeps accounts that share an email apart" do
      email = unique_user_email()
      {:ok, first} = Accounts.sign_in_with_google(google_claims(%{"email" => email}))
      {:ok, second} = Accounts.sign_in_with_google(google_claims(%{"email" => email}))
      assert first.id != second.id
    end

    test "refuses emails Google has not verified" do
      claims = google_claims(%{"email_verified" => false})
      assert {:error, :unverified_email} = Accounts.sign_in_with_google(claims)
      assert {:error, :unverified_email} = Accounts.sign_in_with_google(%{"sub" => "x"})
      assert Repo.aggregate(User, :count) == 0
    end
  end

  describe "sudo_mode?/2" do
    test "validates the authenticated_at time" do
      now = DateTime.utc_now()

      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.utc_now()})
      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -19, :minute)})
      refute Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -21, :minute)})

      # minute override
      refute Accounts.sudo_mode?(
               %User{authenticated_at: DateTime.add(now, -11, :minute)},
               -10
             )

      # not authenticated
      refute Accounts.sudo_mode?(%User{})
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "generates a token", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "session"
      assert user_token.authenticated_at != nil
    end

    test "duplicates the authenticated_at of given user in new token", %{user: user} do
      user = %{user | authenticated_at: DateTime.add(DateTime.utc_now(:second), -3600)}
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.authenticated_at == user.authenticated_at
      assert DateTime.compare(user_token.inserted_at, user.authenticated_at) == :gt
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert {session_user, token_inserted_at} = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
      assert session_user.authenticated_at != nil
      assert token_inserted_at != nil
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_session_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      dt = ~N[2020-01-01 00:00:00]
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: dt, authenticated_at: dt])
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "delete_user_session_token/1" do
    test "deletes the token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert Accounts.delete_user_session_token(token) == :ok
      refute Accounts.get_user_by_session_token(token)
    end
  end
end
