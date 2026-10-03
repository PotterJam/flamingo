defmodule FlamingoWeb.UserLive.LoginTest do
  use FlamingoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Flamingo.AccountsFixtures

  alias Flamingo.Accounts

  describe "user login - magic link" do
    test "sends magic link email when user exists", %{conn: conn} do
      user = user_fixture()

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      lv |> form("#login_form_magic", user: %{email: user.email}) |> render_submit()

      assert has_element?(lv, "#login-email-sent h1", "Check your email")
      assert has_element?(lv, "#login-email-sent", user.email)
      refute has_element?(lv, "#login_form_magic")
      refute has_element?(lv, "#flash-info")

      assert Flamingo.Repo.get_by!(Flamingo.Accounts.UserToken, user_id: user.id).context ==
               "login"

      assert_receive {:email, %Swoosh.Email{subject: "Log in instructions"}}
      assert Accounts.get_user_by_email(user.email).id == user.id
    end

    test "new emails receive a link and must confirm it before logging in", %{conn: conn} do
      email = unique_user_email()
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      lv |> form("#login_form_magic", user: %{email: email}) |> render_submit()

      assert has_element?(lv, "#login-email-sent", email)
      refute has_element?(lv, "#login_form_magic")
      refute has_element?(lv, "#flash-info")
      user = Accounts.get_user_by_email(email)
      assert is_nil(user.confirmed_at)
      refute Flamingo.Repo.get_by(Accounts.UserToken, user_id: user.id, context: "session")

      assert_receive {:email, %Swoosh.Email{to: [{_, ^email}], text_body: body}}
      [_, token] = Regex.run(~r{/users/log-in/([^\s]+)}, body)
      {:ok, confirmation, _html} = live(conn, ~p"/users/log-in/#{token}")
      logged_in = confirmation |> form("#magic-link-login") |> follow_trigger_action(conn)

      assert redirected_to(logged_in) == ~p"/"
      assert get_session(logged_in, :user_token)
      assert logged_in.resp_cookies["_flamingo_web_user_remember_me"]
      assert Accounts.get_user!(user.id).confirmed_at
    end

    test "shows validation errors rather than sending to invalid email", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")
      lv |> form("#login_form_magic", user: %{email: "with spaces"}) |> render_submit()

      assert has_element?(lv, "#login_form_magic", "must have the @ sign and no spaces")
      refute has_element?(lv, "#login-email-sent")
      refute Accounts.get_user_by_email("with spaces")
      refute_receive {:email, _}
    end
  end

  describe "login navigation" do
    test "old registration links redirect guests to the unified login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/users/register")
    end

    test "old registration links still redirect signed-in users home", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/users/register")
    end
  end

  describe "re-authentication (sudo mode)" do
    setup %{conn: conn} do
      user = user_fixture()
      %{user: user, conn: log_in_user(conn, user)}
    end

    test "shows login page with email filled in", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")
      refute has_element?(lv, "#account-register")

      assert has_element?(
               lv,
               "#login_form_magic input[name='user[email]'][readonly][value='#{user.email}']"
             )
    end
  end
end
