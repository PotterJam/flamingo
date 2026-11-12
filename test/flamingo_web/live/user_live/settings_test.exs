defmodule FlamingoWeb.UserLive.SettingsTest do
  use FlamingoWeb.ConnCase, async: true

  alias Flamingo.Accounts
  import Phoenix.LiveViewTest
  import Flamingo.AccountsFixtures

  test "account deletion can be cancelled and confirmed through the protected form", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)
    {:ok, view, _} = live(conn, ~p"/users/settings")
    view |> element("#delete-account") |> render_click()
    assert has_element?(view, "#delete-account-confirmation")
    view |> element("#cancel-delete-account") |> render_click()
    refute has_element?(view, "#delete-account-confirmation")
    assert Flamingo.Repo.get(Accounts.User, user.id)

    view |> element("#delete-account") |> render_click()
    conn = view |> form("#delete-account-form", %{confirm: "true"}) |> submit_form(conn)
    assert redirected_to(conn) == ~p"/"
    refute Flamingo.Repo.get(Accounts.User, user.id)
  end

  describe "Settings page" do
    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/users/settings")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end
  end
end
