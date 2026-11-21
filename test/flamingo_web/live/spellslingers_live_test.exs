defmodule FlamingoWeb.SpellslingersLiveTest do
  use FlamingoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Flamingo.{RoomSupervisor, Rooms}

  defp join_connected(room_id, name) do
    parent = self()

    pid =
      start_supervised!(
        Supervisor.child_spec(
          {Task,
           fn ->
             {:ok, token, _} = Rooms.join(room_id, name)
             {:ok, _} = Rooms.connect(room_id, token)
             send(parent, {:connected, self(), token})
             receive do: (:stop -> :ok)
           end},
          id: {:spell_player, make_ref()}
        )
      )

    assert_receive {:connected, ^pid, token}, 1_000
    token
  end

  test "host picks Spells with an arena and turn length and lands in the arena", %{conn: conn} do
    room_id = "spellslingers-live-#{System.unique_integer([:positive])}"
    {:ok, ^room_id} = RoomSupervisor.start_room(room_id)
    host_token = join_connected(room_id, "Alice")
    _ = join_connected(room_id, "Bob")
    {:ok, lobby, _html} = live(conn, ~p"/game/#{room_id}?resume_token=#{host_token}")

    lobby |> element("#game-mode-spellslingers") |> render_click()
    assert has_element?(lobby, "#arena-map-select")
    refute has_element?(lobby, "#round-count-slider")

    lobby
    |> form("#settings-form", %{"settings" => %{"turn_length" => "25", "arena_map" => "castles"}})
    |> render_submit()

    path = "/game/#{room_id}/spellslingers?resume_token=#{host_token}"
    assert_redirect(lobby, path)

    %{game_mode: :spellslingers, game: game} =
      :sys.get_state(:global.whereis_name({:flamingo_room, room_id}))

    assert %{map_id: "castles", turn_length: 25} = game

    {:ok, arena, _html} = live(conn, path)
    assert has_element?(arena, "#arena-canvas")
  end
end
