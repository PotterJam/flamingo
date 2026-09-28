defmodule FlamingoWeb.UserLive.RegistrationTest do
  use FlamingoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Flamingo.AccountsFixtures

  describe "Registration page" do
    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/register")
        |> follow_redirect(conn, ~p"/")

      assert {:ok, _conn} = result
    end

    test "renders errors for invalid data", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      lv |> element("#registration_form") |> render_change(user: %{"email" => "with spaces"})
      assert has_element?(lv, "#registration_form", "must have the @ sign and no spaces")
    end
  end

  describe "register user" do
    test "creates account but does not log in", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()
      form = form(lv, "#registration_form", user: valid_user_attributes(email: email))

      {:ok, login, _html} =
        render_submit(form)
        |> follow_redirect(conn, ~p"/users/log-in")

      assert has_element?(login, "#flash-info", "An email was sent to #{email}")
      assert is_nil(Flamingo.Accounts.get_user_by_email(email).confirmed_at)
      assert has_element?(login, "#account-log-in")
    end

    test "renders errors for duplicated email", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      user = user_fixture(%{email: "test@email.com"})

      lv |> form("#registration_form", user: %{"email" => user.email}) |> render_submit()
      assert has_element?(lv, "#registration_form", "has already been taken")
    end
  end

  describe "registration navigation" do
    test "redirects to login page when the Log in button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      {:ok, login_live, _html} =
        lv
        |> element("#account-log-in")
        |> render_click()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert has_element?(login_live, "#login_form_magic")
    end
  end
end
