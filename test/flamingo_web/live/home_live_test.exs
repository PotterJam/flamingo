defmodule FlamingoWeb.HomeLiveTest do
  use FlamingoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Flamingo.AccountsFixtures

  alias Flamingo.{Accounts, Rooms, RoomSupervisor}

  test "signed-in avatar changes persist across mounts including changing back", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)
    {:ok, view, _} = live(conn, ~p"/")

    render_hook(view, "save_avatar", %{avatar: %{"head" => 3, "body" => 1}})
    render_hook(view, "save_avatar", %{avatar: %{"head" => 0, "body" => 2}})
    assert Accounts.get_user!(user.id).avatar["head"] == 0
    assert Accounts.get_user!(user.id).avatar["body"] == 2

    {:ok, restored, _} = live(conn, ~p"/")
    assert has_element?(restored, "#avatar-body-input[value='2']")
    assert has_element?(restored, "#avatar-customizer[data-saved-avatar='true']")
  end

  test "guest cannot save an avatar to someone else's account", %{conn: conn} do
    user = user_fixture()
    {:ok, view, _} = live(conn, ~p"/")
    render_hook(view, "save_avatar", %{avatar: %{"head" => 3}, user_id: user.id})
    assert Accounts.get_user!(user.id).avatar == nil
  end

  test "submitting the lobby form joins when a room name is present", %{conn: conn} do
    room_id = "home-#{System.unique_integer([:positive])}"
    {:ok, ^room_id} = RoomSupervisor.start_room(room_id)

    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#lobby-form", lobby: %{name: "Alice", room_code: room_id})
    |> render_submit()

    {path, _flash} = assert_redirect(view)
    uri = URI.parse(path)

    assert uri.path == ~p"/game/#{room_id}"
    assert %{"resume_token" => resume_token} = URI.decode_query(uri.query)
    assert resume_token != ""

    assert {:ok, _state} = Rooms.connect(room_id, resume_token)
  end

  test "submitting the lobby form creates when room name is empty", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#lobby-form", lobby: %{name: "Alice", room_code: ""})
    |> render_submit()

    {path, _flash} = assert_redirect(view)
    uri = URI.parse(path)

    assert uri.path =~ ~r(^/game/.+)
    assert %{"resume_token" => resume_token} = URI.decode_query(uri.query)
    assert resume_token != ""
  end
end
