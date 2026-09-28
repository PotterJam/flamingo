defmodule FlamingoWeb.UserLive.LoginTest do
  use FlamingoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Flamingo.AccountsFixtures

  describe "user login - magic link" do
    test "sends magic link email when user exists", %{conn: conn} do
      user = user_fixture()

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      {:ok, login, _html} =
        form(lv, "#login_form_magic", user: %{email: user.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert has_element?(login, "#flash-info", "If your email is in our system")

      assert Flamingo.Repo.get_by!(Flamingo.Accounts.UserToken, user_id: user.id).context ==
               "login"
    end

    test "does not disclose if user is registered", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      {:ok, login, _html} =
        form(lv, "#login_form_magic", user: %{email: "idonotexist@example.com"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert has_element?(login, "#flash-info", "If your email is in our system")
    end
  end

  describe "login navigation" do
    test "redirects to registration page when the Register button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      {:ok, registration, _html} =
        lv
        |> element("#account-register")
        |> render_click()
        |> follow_redirect(conn, ~p"/users/register")

      assert has_element?(registration, "#registration_form")
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
