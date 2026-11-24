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

    # Malformed client payloads are ignored rather than crashing the arena.
    render_hook(arena, "walk", %{"dir" => "sideways"})
    render_hook(arena, "cast", %{"angle" => 40})
    render_hook(arena, "place", %{"spell" => "golem", "x" => "a", "y" => 1})
    assert has_element?(arena, "#arena-canvas")
  end

  test "a spell picked on someone else's turn waits, unwarned, for yours", %{conn: conn} do
    room_id = "spellslingers-pick-#{System.unique_integer([:positive])}"
    {:ok, ^room_id} = RoomSupervisor.start_room(room_id)
    tokens = [join_connected(room_id, "Alice"), join_connected(room_id, "Bob")]
    {:ok, lobby, _html} = live(conn, ~p"/game/#{room_id}?resume_token=#{hd(tokens)}")
    lobby |> element("#game-mode-spellslingers") |> render_click()
    lobby |> form("#settings-form") |> render_submit()

    views =
      for token <- tokens do
        {:ok, view, _html} = live(conn, ~p"/game/#{room_id}/spellslingers?resume_token=#{token}")
        render_hook(view, "arena_loaded", %{})
        view
      end

    room = :global.whereis_name({:flamingo_room, room_id})
    %{phase_timer: %{key: :arena_intro, generation: intro}} = :sys.get_state(room)
    send(room, {:game_timeout, :phase, :arena_intro, intro})
    game = fn -> :sys.get_state(room).game end
    %{phase: :arena_aim, current_id: first} = game.()

    {[waiting], [playing]} =
      Enum.split_with(views, &has_element?(&1, "#arena-pass[disabled]"))

    # Picking the broom would cast it on your own turn; off it, it is only selected.
    render_hook(waiting, "select_spell", %{"spell" => "broom"})
    assert has_element?(waiting, "#arena-selected-spell", "Take Flight")
    refute has_element?(waiting, "#flash-error")
    assert %{current_id: ^first, quick_used: false, cast_count: 0} = game.()

    render_hook(playing, "pass", %{})
    refute game.().current_id == first
    assert has_element?(waiting, "#arena-selected-spell", "Take Flight")

    # Casting off your turn is still refused.
    render_hook(playing, "cast", %{"spell" => "firebolt", "angle" => 45, "power" => 50})
    assert %{cast_count: 0} = game.()

    # On your turn it goes off, and the used-up quick spell lets go of the selection.
    render_hook(waiting, "select_spell", %{"spell" => "broom"})
    assert %{quick_used: true} = game.()
    assert has_element?(waiting, "#arena-selected-spell", "Mud Pie")
    refute has_element?(waiting, "#flash-error")
  end

  test "a lone host can start a duel against AI wizards from the lobby", %{conn: conn} do
    room_id = "spellslingers-bots-#{System.unique_integer([:positive])}"
    {:ok, ^room_id} = RoomSupervisor.start_room(room_id)
    host_token = join_connected(room_id, "Alice")
    {:ok, lobby, _html} = live(conn, ~p"/game/#{room_id}?resume_token=#{host_token}")

    lobby |> element("#game-mode-spellslingers") |> render_click()
    refute has_element?(lobby, "#start-game-button[disabled]")

    lobby
    |> form("#settings-form", %{"settings" => %{"bots" => "2"}})
    |> render_submit()

    assert_redirect(lobby, "/game/#{room_id}/spellslingers?resume_token=#{host_token}")

    %{game: game} = :sys.get_state(:global.whereis_name({:flamingo_room, room_id}))
    assert length(game.turn_order) == 3
    assert Enum.count(game.turn_order, &String.starts_with?(&1, "bot-")) == 2
  end

  test "only allowlisted players get the dev tuning panel", %{conn: conn} do
    room_id = "spellslingers-tuning-#{System.unique_integer([:positive])}"
    {:ok, ^room_id} = RoomSupervisor.start_room(room_id)
    token = join_connected(room_id, "Alice")
    {:ok, lobby, _html} = live(conn, ~p"/game/#{room_id}?resume_token=#{token}")
    lobby |> element("#game-mode-spellslingers") |> render_click()
    lobby |> form("#settings-form", %{"settings" => %{"bots" => "1"}}) |> render_submit()
    path = ~p"/game/#{room_id}/spellslingers?resume_token=#{token}"
    assert_redirect(lobby, path)
    tuning = fn -> :sys.get_state(:global.whereis_name({:flamingo_room, room_id})).game.tuning end

    {:ok, guest, _html} = live(conn, path)
    refute has_element?(guest, "#arena-dev-panel")

    render_hook(guest, "tune", %{
      "_target" => ["tuning", "gravity"],
      "tuning" => %{"gravity" => "9"}
    })

    assert tuning.().gravity == 38.0

    user = Flamingo.AccountsFixtures.user_fixture(%{"email" => "James@Gearset.com"})
    {:ok, dev, _html} = live(log_in_user(conn, user), path)

    dev
    |> form("#arena-tuning-form", %{"tuning" => %{"gravity" => "9"}})
    |> render_change(%{"_target" => ["tuning", "gravity"]})

    assert tuning.().gravity == 9.0
    assert has_element?(dev, "#arena-tuned")
  end
end
