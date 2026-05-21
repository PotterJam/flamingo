defmodule FlamingoWeb.GameLiveTest do
  use FlamingoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Flamingo.{GameServer, GameSupervisor}

  setup do
    room_id = "live-#{System.unique_integer([:positive])}"
    {:ok, ^room_id} = GameSupervisor.start_game(room_id)
    %{room_id: room_id}
  end

  test "game end screen keeps final scores visible after a player leaves", %{
    conn: conn,
    room_id: room_id
  } do
    {:ok, p1, _} = GameServer.join(room_id, "Alice")
    {:ok, p2, _} = GameServer.join(room_id, "Bob")

    {:ok, view, _html} = live(conn, ~p"/game/#{room_id}?player_id=#{p1}")

    :ok = GameServer.start_game(room_id, p1, %{round_count: 1, turn_length: 30})

    play_turn(room_id, p1, p2)
    play_turn(room_id, p1, p2)

    html = render(view)
    assert html =~ "Game finished"
    assert html =~ "Alice"
    assert html =~ "Bob"

    :ok = GameServer.leave(room_id, p2)

    html = render(view)
    assert html =~ "Game finished"
    assert html =~ "Alice"
    assert html =~ "Bob"
  end

  test "game end screen shows the winning player's drawings", %{conn: conn, room_id: room_id} do
    {:ok, p1, _} = GameServer.join(room_id, "Alice")
    {:ok, p2, _} = GameServer.join(room_id, "Bob")

    {:ok, view, _html} = live(conn, ~p"/game/#{room_id}?player_id=#{p1}")

    :ok = GameServer.start_game(room_id, p1, %{round_count: 1, turn_length: 30})

    words_by_player =
      play_turn(room_id, p1, p2, [
        %{
          "event_type" => "start",
          "x" => 10,
          "y" => 20,
          "color" => "#000000",
          "line_width" => 9
        }
      ])
      |> then(&%{p1 => &1})

    words_by_player = Map.put(words_by_player, p2, play_turn(room_id, p1, p2, []))

    {:ok, state} = GameServer.get_state(room_id)
    winner_id = Enum.max_by(state.player_order, fn pid -> Map.get(state.players, pid).score end)
    winner = Map.get(state.players, winner_id)
    winner_word = Map.get(words_by_player, winner_id)

    html = render(view)

    assert html =~ "Game finished"
    assert html =~ winner.name
    assert html =~ "aria-label=\"Round 1\""
    assert html =~ winner_word
    assert html =~ "data-final-drawing-events="
  end

  test "final score rows select the drawing showcase", %{
    conn: conn,
    room_id: room_id
  } do
    {:ok, p1, _} = GameServer.join(room_id, "Alice")
    {:ok, p2, _} = GameServer.join(room_id, "Bob")

    {:ok, view, _html} = live(conn, ~p"/game/#{room_id}?player_id=#{p1}")

    :ok = GameServer.start_game(room_id, p1, %{round_count: 1, turn_length: 30})

    alice_word =
      play_turn(room_id, p1, p2, [
        %{
          "event_type" => "start",
          "x" => 10,
          "y" => 20,
          "color" => "#000000",
          "line_width" => 9
        }
      ])

    bob_word =
      play_turn(room_id, p1, p2, [
        %{
          "event_type" => "start",
          "x" => 30,
          "y" => 40,
          "color" => "#EF120B",
          "line_width" => 9
        }
      ])

    html = render(view)
    assert html =~ alice_word
    assert html =~ "final-drawing-#{p1}-round-1"

    html =
      view
      |> element("[data-player-id='#{p2}']")
      |> render_click()

    assert html =~ bob_word
    assert html =~ "final-drawing-#{p2}-round-1"
    assert html =~ "data-selected=\"true\""
  end

  test "final score row with no drawings remains selectable and shows an empty state", %{
    conn: conn,
    room_id: room_id
  } do
    {:ok, p1, _} = GameServer.join(room_id, "Alice")
    {:ok, p2, _} = GameServer.join(room_id, "Bob")

    {:ok, view, _html} = live(conn, ~p"/game/#{room_id}?player_id=#{p1}")

    players = %{
      p1 => %{id: p1, name: "Alice", score: 100},
      p2 => %{id: p2, name: "Bob", score: 50}
    }

    send(view.pid, {:game_ended, players, []})

    html =
      view
      |> element("[data-player-id='#{p2}']")
      |> render_click()

    assert html =~ "Bob"
    assert html =~ "No drawings to show"
    assert html =~ "data-selected=\"true\""
  end

  test "pushes round audio lifecycle events as phases change", %{conn: conn, room_id: room_id} do
    {:ok, p1, _} = GameServer.join(room_id, "Alice")
    {:ok, p2, _} = GameServer.join(room_id, "Bob")

    {:ok, view, _html} = live(conn, ~p"/game/#{room_id}?player_id=#{p1}")

    :ok = GameServer.start_game(room_id, p1, %{round_count: 1, turn_length: 30})

    assert_push_event(view, "sync_round_audio", %{
      phase: "word_choice",
      end_time: word_choice_end_time
    })

    assert is_binary(word_choice_end_time)

    {:ok, state} = GameServer.get_state(room_id)
    word = List.first(state.word_choices)
    :ok = GameServer.select_word(room_id, state.drawer_id, word)

    assert_push_event(view, "sync_round_audio", %{
      phase: "playing",
      end_time: playing_end_time
    })

    assert is_binary(playing_end_time)

    {:ok, state} = GameServer.get_state(room_id)
    guesser = if(p1 == state.drawer_id, do: p2, else: p1)
    :correct = GameServer.guess(room_id, guesser, word)

    assert_push_event(view, "sync_round_audio", %{
      phase: "turn_reveal",
      end_time: reveal_end_time
    })

    assert is_binary(reveal_end_time)
  end

  defp play_turn(room_id, p1, p2, drawing_events \\ []) do
    {:ok, state} = GameServer.get_state(room_id)
    word = List.first(state.word_choices)
    :ok = GameServer.select_word(room_id, state.drawer_id, word)

    {:ok, state} = GameServer.get_state(room_id)
    Enum.each(drawing_events, &GameServer.draw_event(room_id, state.drawer_id, &1))
    guesser = if(p1 == state.drawer_id, do: p2, else: p1)
    :correct = GameServer.guess(room_id, guesser, word)

    pid = GenServer.whereis({:via, Registry, {Flamingo.GameRegistry, room_id}})
    _ = :sys.get_state(pid)

    {:ok, state} = GameServer.get_state(room_id)
    send(pid, {:turn_reveal_timeout, state.phase_timer_ref})
    _ = :sys.get_state(pid)

    word
  end
end
