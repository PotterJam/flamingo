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

    drawing =
      Jason.encode!([
        %{path: "M 30 20 L 45 35", width: 2},
        %{path: "M 60 40 L 85 50", width: 10}
      ])

    view
    |> form("#lobby-form", lobby: %{name: "Alice", room_code: ""})
    |> render_submit(%{lobby: %{head_drawing: drawing}})

    {path, _flash} = assert_redirect(view)
    uri = URI.parse(path)

    assert uri.path =~ ~r(^/game/.+)
    assert %{"resume_token" => resume_token} = URI.decode_query(uri.query)
    assert resume_token != ""

    {:ok, lobby, _html} = live(conn, path)

    assert has_element?(
             lobby,
             "[id^='lobby-player-row-'] [data-avatar-part-root='head'] path[stroke-width='2'][d='M 30 20 L 45 35']"
           )

    assert has_element?(
             lobby,
             "[id^='lobby-player-row-'] [data-avatar-part-root='head'] path[stroke-width='10'][d='M 60 40 L 85 50']"
           )
  end
end
