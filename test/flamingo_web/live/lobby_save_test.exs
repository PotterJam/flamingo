defmodule FlamingoWeb.LobbySaveTest do
  use FlamingoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Flamingo.AccountsFixtures

  alias Flamingo.{Rooms, RoomSupervisor, SavedLobbies}

  setup %{conn: conn} do
    room_id = "lobby-save-#{System.unique_integer([:positive])}"
    {:ok, ^room_id} = RoomSupervisor.start_room(room_id)
    {:ok, host_token, _} = Rooms.join(room_id, "Alice")
    {:ok, guest_token, _} = Rooms.join(room_id, "Bob")
    user = user_fixture()

    %{
      room_id: room_id,
      conn: conn,
      signed_in_conn: log_in_user(conn, user),
      user: user,
      host_path: ~p"/game/#{room_id}?resume_token=#{host_token}",
      guest_path: ~p"/game/#{room_id}?resume_token=#{guest_token}"
    }
  end

  defp unique_name, do: "crew-#{System.unique_integer([:positive])}"

  test "a signed-in host saves the lobby and everyone keeps playing in it", context do
    %{signed_in_conn: signed_in_conn, conn: conn, room_id: room_id, user: user} = context
    name = unique_name()
    {:ok, host, _} = live(signed_in_conn, context.host_path)
    {:ok, guest, _} = live(conn, context.guest_path)

    host |> element("#save-lobby-button") |> render_click()
    host |> form("#save-lobby-form", saved_lobby: %{name: String.upcase(name)}) |> render_change()
    assert has_element?(host, "#saved-lobby-link-preview", name)

    host |> form("#save-lobby-form", saved_lobby: %{name: name}) |> render_submit()

    assert has_element?(host, "#saved-lobby-name", name)
    refute has_element?(host, "#save-lobby-form")
    assert SavedLobbies.get_saved_lobby_by_name(name).creator_id == user.id
    assert Rooms.open_saved_lobby(name) == {:ok, room_id}
    assert render(guest) =~ "The host is configuring the game"
  end

  test "a taken name is explained without saving the lobby", context do
    taken = unique_name()
    other_room = "lobby-save-other-#{System.unique_integer([:positive])}"
    {:ok, ^other_room} = RoomSupervisor.start_room(other_room)
    {:ok, other_token, _} = Rooms.join(other_room, "Dana")
    {:ok, _} = Rooms.connect(other_room, other_token)
    {:ok, _} = SavedLobbies.save_room(user_scope_fixture(), other_room, %{name: taken})

    {:ok, host, _} = live(context.signed_in_conn, context.host_path)
    host |> element("#save-lobby-button") |> render_click()

    assert host
           |> form("#save-lobby-form", saved_lobby: %{name: taken})
           |> render_change() =~ "is already taken"

    assert has_element?(host, "#confirm-save-lobby-button[disabled]")

    assert host
           |> form("#save-lobby-form", saved_lobby: %{name: taken})
           |> render_submit() =~ "is already taken"

    refute has_element?(host, "#saved-lobby-name")
  end

  test "only a signed-in host is offered saving, and others cannot force it", context do
    {:ok, guest_host, _} = live(context.conn, context.host_path)
    refute has_element?(guest_host, "#save-lobby-button")

    {:ok, signed_in_guest, _} = live(context.signed_in_conn, context.guest_path)
    refute has_element?(signed_in_guest, "#save-lobby-button")

    name = unique_name()
    render_hook(guest_host, "save_lobby", %{saved_lobby: %{name: name}})
    render_hook(signed_in_guest, "save_lobby", %{saved_lobby: %{name: name}})
    assert SavedLobbies.get_saved_lobby_by_name(name) == nil
  end
end
