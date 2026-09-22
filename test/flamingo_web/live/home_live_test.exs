defmodule FlamingoWeb.HomeLiveTest do
  use FlamingoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Flamingo.{Rooms, RoomSupervisor}

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
