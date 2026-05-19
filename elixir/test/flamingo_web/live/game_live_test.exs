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

  defp play_turn(room_id, p1, p2) do
    {:ok, state} = GameServer.get_state(room_id)
    word = List.first(state.word_choices)
    :ok = GameServer.select_word(room_id, state.drawer_id, word)

    {:ok, state} = GameServer.get_state(room_id)
    guesser = if(p1 == state.drawer_id, do: p2, else: p1)
    :correct = GameServer.guess(room_id, guesser, word)

    pid = GenServer.whereis({:via, Registry, {Flamingo.GameRegistry, room_id}})
    _ = :sys.get_state(pid)

    {:ok, state} = GameServer.get_state(room_id)
    send(pid, {:turn_reveal_timeout, state.phase_timer_ref})
    _ = :sys.get_state(pid)
  end
end
