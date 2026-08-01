defmodule Flamingo.RoomServerTest do
  use ExUnit.Case, async: true

  alias Flamingo.RoomServer
  alias Flamingo.RoomSupervisor

  setup do
    room_id = "test-#{System.unique_integer([:positive])}"
    {:ok, ^room_id} = RoomSupervisor.start_room(room_id)
    %{room_id: room_id}
  end

  defp resume_token_for(state, seat_id) do
    Enum.find_value(state.resume_tokens, fn
      {resume_token, ^seat_id} -> resume_token
      _ -> nil
    end)
  end

  test "first player becomes host", %{room_id: room_id} do
    {:ok, _resume_token, %{viewer_id: player_id} = state} = RoomServer.join(room_id, "Alice")
    assert state.mode == :scribble
    assert state.host_id == player_id
    assert map_size(state.players) == 1
    assert state.player_order == [player_id]
  end

  test "second player does not change host", %{room_id: room_id} do
    {:ok, _p1_token, %{viewer_id: p1}} = RoomServer.join(room_id, "Alice")
    {:ok, _p2_token, %{viewer_id: p2} = state} = RoomServer.join(room_id, "Bob")
    assert state.host_id == p1
    assert state.player_order == [p1, p2]
  end

  test "leave reassigns host when host leaves", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = RoomServer.join(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = RoomServer.join(room_id, "Bob")

    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    :ok = RoomServer.leave(room_id, Map.fetch!(resume_tokens, p1))

    {:ok, state} = RoomServer.get_state(room_id)
    assert state.host_id == p2
    assert state.player_order == [p2]
    refute Map.has_key?(state.players, p1)
  end

  test "leave does not change host when non-host leaves", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = RoomServer.join(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = RoomServer.join(room_id, "Bob")

    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    :ok = RoomServer.leave(room_id, Map.fetch!(resume_tokens, p2))

    {:ok, state} = RoomServer.get_state(room_id)
    assert state.host_id == p1
  end

  test "join broadcasts players_updated", %{room_id: room_id} do
    Phoenix.PubSub.subscribe(Flamingo.PubSub, "game:#{room_id}")
    RoomServer.join(room_id, "Alice")
    assert_receive {:players_updated, _players, _order, _host}
  end

  test "start_game fails if not host", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = RoomServer.join(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = RoomServer.join(room_id, "Bob")
    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    assert {:error, :not_host} =
             RoomServer.start_game(room_id, Map.fetch!(resume_tokens, p2), %{})
  end

  test "start_game fails with fewer than 2 players", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = RoomServer.join(room_id, "Alice")
    resume_tokens = %{p1 => p1_token}

    assert {:error, :not_enough_players} =
             RoomServer.start_game(room_id, Map.fetch!(resume_tokens, p1), %{})
  end

  test "start_game fails with invalid round_count", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = RoomServer.join(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = RoomServer.join(room_id, "Bob")
    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    assert {:error, :invalid_round_count} =
             RoomServer.start_game(room_id, Map.fetch!(resume_tokens, p1), %{round_count: 0})

    assert {:error, :invalid_round_count} =
             RoomServer.start_game(room_id, Map.fetch!(resume_tokens, p1), %{round_count: 6})
  end

  test "start_game fails with invalid turn_length", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = RoomServer.join(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = RoomServer.join(room_id, "Bob")

    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    assert {:error, :invalid_turn_length} =
             RoomServer.start_game(room_id, Map.fetch!(resume_tokens, p1), %{turn_length: 14})

    assert {:error, :invalid_turn_length} =
             RoomServer.start_game(room_id, Map.fetch!(resume_tokens, p1), %{turn_length: 121})
  end

  test "start_game accepts turn_length boundaries", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = RoomServer.join(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = RoomServer.join(room_id, "Bob")

    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    assert :ok = RoomServer.start_game(room_id, Map.fetch!(resume_tokens, p1), %{turn_length: 15})

    {:ok, state} = RoomServer.get_state(room_id)
    assert state.turn_length == 15

    assert :ok =
             RoomServer.start_game(room_id, Map.fetch!(resume_tokens, p1), %{turn_length: 120})

    {:ok, state} = RoomServer.get_state(room_id)
    assert state.turn_length == 120
  end

  test "start_game succeeds and broadcasts", %{room_id: room_id} do
    Phoenix.PubSub.subscribe(Flamingo.PubSub, "game:#{room_id}")
    {:ok, p1_token, %{viewer_id: p1}} = RoomServer.join(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = RoomServer.join(room_id, "Bob")

    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    assert :ok =
             RoomServer.start_game(room_id, Map.fetch!(resume_tokens, p1), %{
               round_count: 2,
               turn_length: 45
             })

    assert_receive {:word_choice_started, _drawer_id, _turn_end_time, 2, 45, 0}

    {:ok, state} = RoomServer.get_state(room_id)
    assert state.phase == :word_choice
    assert length(state.word_choices) == 3
  end

  test "snapshot projects word choices and words for the requesting player", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = RoomServer.join(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = RoomServer.join(room_id, "Bob")
    {:ok, p3_token, %{viewer_id: p3}} = RoomServer.join(room_id, "Charlie")

    resume_tokens = %{p1 => p1_token, p2 => p2_token, p3 => p3_token}

    :ok =
      RoomServer.start_game(room_id, Map.fetch!(resume_tokens, p1), %{
        custom_words: ["secret", "other", "third"],
        round_count: 1,
        turn_length: 30
      })

    {:ok, state} = RoomServer.get_state(room_id)
    drawer_id = state.drawer_id
    guesser_ids = Enum.reject(state.player_order, &(&1 == drawer_id))
    [first_guesser_id, second_guesser_id] = guesser_ids

    {:ok, drawer_snapshot} = RoomServer.snapshot(room_id, Map.fetch!(resume_tokens, drawer_id))

    {:ok, guesser_snapshot} =
      RoomServer.snapshot(room_id, Map.fetch!(resume_tokens, first_guesser_id))

    assert drawer_snapshot.mode == :scribble
    assert drawer_snapshot.word_choices == state.word_choices
    assert guesser_snapshot.word_choices == []
    refute Map.has_key?(guesser_snapshot, :phase_timer_ref)
    refute Map.has_key?(guesser_snapshot, :used_words)

    word = List.first(state.word_choices)
    :ok = RoomServer.select_word(room_id, Map.fetch!(resume_tokens, drawer_id), word)

    {:ok, drawer_snapshot} = RoomServer.snapshot(room_id, Map.fetch!(resume_tokens, drawer_id))

    {:ok, hidden_snapshot} =
      RoomServer.snapshot(room_id, Map.fetch!(resume_tokens, second_guesser_id))

    assert drawer_snapshot.word == word
    assert drawer_snapshot.word_visible?
    assert hidden_snapshot.word == String.replace(word, ~r/[^ ]/u, "_")
    refute hidden_snapshot.word_visible?

    assert :correct = RoomServer.guess(room_id, Map.fetch!(resume_tokens, first_guesser_id), word)

    {:ok, correct_guesser_snapshot} =
      RoomServer.snapshot(room_id, Map.fetch!(resume_tokens, first_guesser_id))

    {:ok, still_hidden_snapshot} =
      RoomServer.snapshot(room_id, Map.fetch!(resume_tokens, second_guesser_id))

    assert correct_guesser_snapshot.word == word
    assert correct_guesser_snapshot.word_visible?
    refute still_hidden_snapshot.word_visible?

    assert p2 in guesser_ids
    assert p3 in guesser_ids
  end

  test "snapshot rejects an unknown player", %{room_id: room_id} do
    assert {:error, :not_found} = RoomServer.snapshot(room_id, "unknown")
  end

  test "join separates the opaque credential from the public seat identity", %{room_id: room_id} do
    {:ok, seat_id_token, %{viewer_id: seat_id} = snapshot} = RoomServer.join(room_id, "Alice")
    token = seat_id_token

    assert is_binary(token)
    assert byte_size(token) >= 32
    assert snapshot.viewer_id == seat_id
    refute token == seat_id
    refute inspect(snapshot) =~ token
    refute Map.has_key?(snapshot, :resume_tokens)
  end

  test "unknown tokens cannot inspect or mutate a game", %{room_id: room_id} do
    {:ok, _alice_token, %{viewer_id: alice}} = RoomServer.join(room_id, "Alice")
    {:ok, _bob_token, _bob_snapshot} = RoomServer.join(room_id, "Bob")
    unknown = "unknown-token"

    assert {:error, :not_found} = RoomServer.snapshot(room_id, unknown)
    assert {:error, :not_found} = RoomServer.start_game(room_id, unknown, %{})
    assert {:error, :not_found} = RoomServer.select_word(room_id, unknown, "cat")
    assert {:error, :not_found} = RoomServer.guess(room_id, unknown, "cat")

    {:ok, before_draw} = RoomServer.get_state(room_id)
    :ok = RoomServer.draw_event(room_id, unknown, %{"event_type" => "clear"})
    _ = :sys.get_state(RoomServer.whereis(room_id))
    assert {:ok, ^before_draw} = RoomServer.get_state(room_id)

    assert before_draw.host_id == alice
  end

  test "credentials resolve only their own seat and cannot borrow authorization", %{
    room_id: room_id
  } do
    {:ok, alice_token, %{viewer_id: alice}} = RoomServer.join(room_id, "Alice")
    {:ok, bob_token, %{viewer_id: bob}} = RoomServer.join(room_id, "Bob")

    assert {:ok, %{viewer_id: ^alice}} = RoomServer.snapshot(room_id, alice_token)

    assert {:ok, %{viewer_id: ^bob}} = RoomServer.snapshot(room_id, bob_token)
    assert {:error, :not_host} = RoomServer.start_game(room_id, bob_token, %{})

    :ok = RoomServer.start_game(room_id, alice_token, %{})
    {:ok, state} = RoomServer.get_state(room_id)
    word = List.first(state.word_choices)

    if state.drawer_id == alice do
      assert {:error, :not_drawer} =
               RoomServer.select_word(room_id, bob_token, word)
    end
  end

  test "permanent lobby removal invalidates the removed credential", %{room_id: room_id} do
    {:ok, alice_token, %{viewer_id: alice}} = RoomServer.join(room_id, "Alice")
    token = alice_token

    resume_tokens = %{alice => alice_token}

    :ok = RoomServer.leave(room_id, Map.fetch!(resume_tokens, alice))

    assert {:error, :not_found} = RoomServer.snapshot(room_id, token)
    assert {:error, :not_found} = RoomServer.rejoin(room_id, token)
  end

  test "start_game uses custom words exclusively", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = RoomServer.join(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = RoomServer.join(room_id, "Bob")
    custom_words = ["orbital llama", "velvet cactus", "disco teapot"]

    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    assert :ok =
             RoomServer.start_game(room_id, Map.fetch!(resume_tokens, p1), %{
               custom_words: custom_words
             })

    {:ok, state} = RoomServer.get_state(room_id)
    assert state.custom_words == custom_words
    assert Enum.sort(state.word_choices) == Enum.sort(custom_words)
  end

  test "start_game can include deduplicated default words with custom words", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = RoomServer.join(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = RoomServer.join(room_id, "Bob")

    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    assert :ok =
             RoomServer.start_game(room_id, Map.fetch!(resume_tokens, p1), %{
               custom_words: ["apple", "orbital llama"],
               include_default_words: true
             })

    {:ok, state} = RoomServer.get_state(room_id)

    assert state.include_default_words
    assert state.custom_words == ["apple", "orbital llama"]
    assert length(state.word_choices) == 3
  end

  test "start_game rejects invalid custom words", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = RoomServer.join(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = RoomServer.join(room_id, "Bob")

    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    assert {:error, :invalid_custom_words} =
             RoomServer.start_game(room_id, Map.fetch!(resume_tokens, p1), %{
               custom_words: ["cat, dog"]
             })

    assert {:error, :too_many_custom_words} =
             RoomServer.start_game(room_id, Map.fetch!(resume_tokens, p1), %{
               custom_words: Enum.map(1..3001, &"word #{&1}")
             })
  end

  test "minimum turn length schedules hints before the turn ends", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = RoomServer.join(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = RoomServer.join(room_id, "Bob")
    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    :ok = RoomServer.start_game(room_id, Map.fetch!(resume_tokens, p1), %{turn_length: 15})

    {:ok, state} = RoomServer.get_state(room_id)
    word = List.first(state.word_choices)
    :ok = RoomServer.select_word(room_id, Map.fetch!(resume_tokens, state.drawer_id), word)

    {:ok, state} = RoomServer.get_state(room_id)

    assert is_reference(state.hint_timer_ref)

    schedule = RoomServer.hint_schedule(word, 15)
    assert schedule != []
    assert Enum.all?(schedule, &(&1 < 15_000))
  end

  test "hint schedule spreads reveals across the turn for every round length" do
    for turn_length <- [15, 30, 45, 120] do
      schedule = RoomServer.hint_schedule("flamingo", turn_length)
      turn_ms = turn_length * 1000

      # 8 letters -> up to half revealed
      assert length(schedule) == 4
      assert schedule == Enum.sort(schedule)
      assert Enum.all?(schedule, &(&1 >= trunc(turn_ms * 0.3)))
      assert Enum.all?(schedule, &(&1 < turn_ms))
    end
  end

  test "hint schedule reveals at most half the letters" do
    assert length(RoomServer.hint_schedule("cat", 45)) == 1
    assert length(RoomServer.hint_schedule("Pac-Man", 45)) == 3
    assert RoomServer.hint_schedule("a", 45) == []
  end

  test "hints reveal letters while playing", %{room_id: room_id} do
    Phoenix.PubSub.subscribe(Flamingo.PubSub, "game:#{room_id}")
    {_p1, _p2, word, state} = start_playing(room_id)

    pid = RoomServer.whereis(room_id)
    send(pid, {:reveal_hint, state.hint_timer_ref})

    assert_receive {:hint_revealed, [index]}
    assert index in 0..(String.length(word) - 1)

    {:ok, state} = RoomServer.get_state(room_id)
    assert state.revealed_indices == [index]
  end

  test "turn reveal clears pending hint timer", %{room_id: room_id} do
    {p1, p2, word, state} = start_playing(room_id, %{turn_length: 15})
    drawer = state.drawer_id
    guesser = if p1 == drawer, do: p2, else: p1

    assert is_reference(state.hint_timer_ref)

    :correct = RoomServer.guess(room_id, resume_token_for(state, guesser), word)

    {:ok, state} = RoomServer.get_state(room_id)
    assert state.phase == :turn_reveal
    assert state.hint_timer_ref == nil
  end

  test "join returns not_found for nonexistent room" do
    assert {:error, :not_found} = RoomServer.join("no-such-room", "Alice")
  end

  test "rejoin succeeds for existing player", %{room_id: room_id} do
    {:ok, player_id_token, %{viewer_id: player_id}} = RoomServer.join(room_id, "Alice")
    resume_tokens = %{player_id => player_id_token}

    {:ok, state} = RoomServer.rejoin(room_id, Map.fetch!(resume_tokens, player_id))
    assert Map.has_key?(state.players, player_id)
  end

  test "rejoin fails for unknown player", %{room_id: room_id} do
    assert {:error, :not_found} = RoomServer.rejoin(room_id, "nonexistent")
  end

  test "leave during a game marks the player disconnected instead of removing them", %{
    room_id: room_id
  } do
    {p1, p2, _word, state} = start_playing(room_id)
    guesser = if p1 == state.drawer_id, do: p2, else: p1

    :ok = RoomServer.leave(room_id, resume_token_for(state, guesser))

    {:ok, state} = RoomServer.get_state(room_id)
    assert Map.has_key?(state.players, guesser)
    refute Map.get(state.players, guesser).connected
    assert guesser in state.player_order
    assert is_reference(Map.get(state.disconnect_timers, guesser))
  end

  test "rejoin reconnects a disconnected player", %{room_id: room_id} do
    {p1, p2, _word, state} = start_playing(room_id)
    guesser = if p1 == state.drawer_id, do: p2, else: p1

    :ok = RoomServer.leave(room_id, resume_token_for(state, guesser))
    {:ok, _snapshot} = RoomServer.rejoin(room_id, resume_token_for(state, guesser))
    {:ok, state} = RoomServer.get_state(room_id)

    assert Map.get(state.players, guesser).connected
    refute Map.has_key?(state.disconnect_timers, guesser)
  end

  test "disconnected players are removed once the grace period expires", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = RoomServer.join(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = RoomServer.join(room_id, "Bob")
    {:ok, p3_token, %{viewer_id: p3}} = RoomServer.join(room_id, "Charlie")
    resume_tokens = %{p1 => p1_token, p2 => p2_token, p3 => p3_token}

    :ok =
      RoomServer.start_game(room_id, Map.fetch!(resume_tokens, p1), %{
        round_count: 1,
        turn_length: 30
      })

    {:ok, state} = RoomServer.get_state(room_id)
    word = List.first(state.word_choices)
    :ok = RoomServer.select_word(room_id, Map.fetch!(resume_tokens, state.drawer_id), word)

    {:ok, state} = RoomServer.get_state(room_id)
    guesser = Enum.find([p1, p2, p3], &(&1 != state.drawer_id))

    :ok = RoomServer.leave(room_id, Map.fetch!(resume_tokens, guesser))

    {:ok, state} = RoomServer.get_state(room_id)
    ref = Map.fetch!(state.disconnect_timers, guesser)

    pid = RoomServer.whereis(room_id)
    send(pid, {:remove_player, guesser, ref})
    _ = :sys.get_state(pid)

    {:ok, state} = RoomServer.get_state(room_id)
    refute Map.has_key?(state.players, guesser)
    refute guesser in state.player_order
  end

  test "a reconnected player is not removed by the stale grace timer", %{room_id: room_id} do
    {p1, p2, _word, state} = start_playing(room_id)
    guesser = if p1 == state.drawer_id, do: p2, else: p1

    :ok = RoomServer.leave(room_id, resume_token_for(state, guesser))

    {:ok, state} = RoomServer.get_state(room_id)
    ref = Map.fetch!(state.disconnect_timers, guesser)

    {:ok, _state} = RoomServer.rejoin(room_id, resume_token_for(state, guesser))

    pid = RoomServer.whereis(room_id)
    send(pid, {:remove_player, guesser, ref})
    _ = :sys.get_state(pid)

    {:ok, state} = RoomServer.get_state(room_id)
    assert Map.has_key?(state.players, guesser)
    assert Map.get(state.players, guesser).connected
  end

  test "a disconnected guesser keeps their earned score", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = RoomServer.join(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = RoomServer.join(room_id, "Bob")
    {:ok, p3_token, %{viewer_id: p3}} = RoomServer.join(room_id, "Charlie")
    resume_tokens = %{p1 => p1_token, p2 => p2_token, p3 => p3_token}

    :ok =
      RoomServer.start_game(room_id, Map.fetch!(resume_tokens, p1), %{
        round_count: 1,
        turn_length: 30
      })

    {:ok, state} = RoomServer.get_state(room_id)
    word = List.first(state.word_choices)
    :ok = RoomServer.select_word(room_id, Map.fetch!(resume_tokens, state.drawer_id), word)

    {:ok, state} = RoomServer.get_state(room_id)
    [g1, g2] = Enum.reject([p1, p2, p3], &(&1 == state.drawer_id))

    :correct = RoomServer.guess(room_id, Map.fetch!(resume_tokens, g1), word)
    :ok = RoomServer.leave(room_id, Map.fetch!(resume_tokens, g1))
    :correct = RoomServer.guess(room_id, Map.fetch!(resume_tokens, g2), word)

    {:ok, state} = RoomServer.get_state(room_id)
    assert state.phase == :turn_reveal
    assert Map.get(state.players, g1).score > 0

    {:ok, state} = RoomServer.rejoin(room_id, Map.fetch!(resume_tokens, g1))
    assert Map.get(state.players, g1).score > 0
    assert Map.get(state.players, g1).connected
  end

  test "next drawer skips disconnected players", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = RoomServer.join(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = RoomServer.join(room_id, "Bob")
    {:ok, p3_token, %{viewer_id: p3}} = RoomServer.join(room_id, "Charlie")
    resume_tokens = %{p1 => p1_token, p2 => p2_token, p3 => p3_token}

    :ok =
      RoomServer.start_game(room_id, Map.fetch!(resume_tokens, p1), %{
        round_count: 1,
        turn_length: 30
      })

    {:ok, state} = RoomServer.get_state(room_id)
    word = List.first(state.word_choices)
    :ok = RoomServer.select_word(room_id, Map.fetch!(resume_tokens, state.drawer_id), word)

    {:ok, state} = RoomServer.get_state(room_id)
    [g1, g2] = Enum.reject([p1, p2, p3], &(&1 == state.drawer_id))

    :correct = RoomServer.guess(room_id, Map.fetch!(resume_tokens, g1), word)
    :correct = RoomServer.guess(room_id, Map.fetch!(resume_tokens, g2), word)

    {:ok, state} = RoomServer.get_state(room_id)
    assert state.phase == :turn_reveal

    # The next drawer in order disconnects during the reveal
    next_in_order =
      Enum.find(state.player_order, fn pid ->
        not MapSet.member?(state.drawn_this_round, pid)
      end)

    :ok = RoomServer.leave(room_id, Map.fetch!(resume_tokens, next_in_order))

    pid = RoomServer.whereis(room_id)
    {:ok, state} = RoomServer.get_state(room_id)
    send(pid, {:turn_reveal_timeout, state.phase_timer_ref})
    _ = :sys.get_state(pid)

    {:ok, state} = RoomServer.get_state(room_id)
    assert state.phase == :word_choice
    assert state.drawer_id != next_in_order
  end

  defp start_playing(room_id, settings \\ %{round_count: 1, turn_length: 30}) do
    {:ok, p1_token, %{viewer_id: p1}} = RoomServer.join(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = RoomServer.join(room_id, "Bob")
    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    :ok = RoomServer.start_game(room_id, Map.fetch!(resume_tokens, p1), settings)

    {:ok, state} = RoomServer.get_state(room_id)
    word = List.first(state.word_choices)
    :ok = RoomServer.select_word(room_id, Map.fetch!(resume_tokens, state.drawer_id), word)

    {:ok, state} = RoomServer.get_state(room_id)
    {p1, p2, word, state}
  end

  test "select_word transitions to playing with timer", %{room_id: room_id} do
    {_p1, _p2, _word, state} = start_playing(room_id)
    assert state.phase == :playing
    assert state.turn_end_time != nil
    assert state.phase_timer_ref != nil
  end

  test "correct guess records and broadcasts", %{room_id: room_id} do
    Phoenix.PubSub.subscribe(Flamingo.PubSub, "game:#{room_id}")
    {_p1, p2, word, state} = start_playing(room_id)

    guesser = if p2 == state.drawer_id, do: elem(start_playing(room_id), 0), else: p2
    guesser = if guesser == state.drawer_id, do: p2, else: guesser

    assert :correct = RoomServer.guess(room_id, resume_token_for(state, guesser), word)
    assert_receive {:correct_guess, ^guesser}
  end

  test "incorrect guess broadcasts", %{room_id: room_id} do
    Phoenix.PubSub.subscribe(Flamingo.PubSub, "game:#{room_id}")
    {p1, p2, _word, state} = start_playing(room_id)
    guesser = if p1 == state.drawer_id, do: p2, else: p1

    assert :incorrect =
             RoomServer.guess(room_id, resume_token_for(state, guesser), "wrong-answer")

    assert_receive {:incorrect_guess, ^guesser, "wrong-answer"}
  end

  test "close guess sends private feedback instead of public chat", %{room_id: room_id} do
    Phoenix.PubSub.subscribe(Flamingo.PubSub, "game:#{room_id}")
    {p1, p2, word, state} = start_playing(room_id)
    guesser = if p1 == state.drawer_id, do: p2, else: p1
    other_player = if guesser == p1, do: p2, else: p1
    close_guess = String.replace_suffix(word, String.last(word), "z")

    assert :close =
             RoomServer.guess(room_id, resume_token_for(state, guesser), close_guess)

    refute_receive {:incorrect_guess, ^guesser, ^close_guess}
    assert_receive {:feed_event, %{event: {:close_guess, ^guesser}} = entry}

    assert %{kind: :close, text: "You were close"} = Flamingo.Feed.format(entry, guesser)
    assert nil == Flamingo.Feed.format(entry, other_player)
  end

  test "close guess ignores case spacing and punctuation for same-length typos", %{
    room_id: room_id
  } do
    Phoenix.PubSub.subscribe(Flamingo.PubSub, "game:#{room_id}")
    {p1, p2, word, state} = start_playing(room_id)
    guesser = if p1 == state.drawer_id, do: p2, else: p1

    close_guess =
      word
      |> String.replace_suffix(String.last(word), "z")
      |> String.upcase()
      |> String.graphemes()
      |> Enum.join(" ")
      |> Kernel.<>("!")

    assert :close =
             RoomServer.guess(room_id, resume_token_for(state, guesser), close_guess)

    refute_receive {:incorrect_guess, ^guesser, ^close_guess}
    assert_receive {:feed_event, %{event: {:close_guess, ^guesser}}}
  end

  test "wrong-length guesses are normal incorrect guesses", %{room_id: room_id} do
    Phoenix.PubSub.subscribe(Flamingo.PubSub, "game:#{room_id}")
    {p1, p2, word, state} = start_playing(room_id)
    guesser = if p1 == state.drawer_id, do: p2, else: p1
    wrong_length_guess = word <> "zz"

    assert :incorrect =
             RoomServer.guess(
               room_id,
               resume_token_for(state, guesser),
               wrong_length_guess
             )

    assert_receive {:incorrect_guess, ^guesser, ^wrong_length_guess}
    refute_receive {:feed_event, %{event: {:close_guess, ^guesser}}}
  end

  test "one-character insertion is a close guess", %{room_id: room_id} do
    Phoenix.PubSub.subscribe(Flamingo.PubSub, "game:#{room_id}")
    {p1, p2, word, state} = start_playing(room_id)
    guesser = if p1 == state.drawer_id, do: p2, else: p1
    close_guess = word <> "z"

    assert :close =
             RoomServer.guess(room_id, resume_token_for(state, guesser), close_guess)

    refute_receive {:incorrect_guess, ^guesser, ^close_guess}
    assert_receive {:feed_event, %{event: {:close_guess, ^guesser}}}
  end

  test "one-character deletion is a close guess", %{room_id: room_id} do
    Phoenix.PubSub.subscribe(Flamingo.PubSub, "game:#{room_id}")
    {p1, p2, word, state} = start_playing(room_id)
    guesser = if p1 == state.drawer_id, do: p2, else: p1
    close_guess = String.slice(word, 0, String.length(word) - 1)

    assert :close =
             RoomServer.guess(room_id, resume_token_for(state, guesser), close_guess)

    refute_receive {:incorrect_guess, ^guesser, ^close_guess}
    assert_receive {:feed_event, %{event: {:close_guess, ^guesser}}}
  end

  test "drawer cannot guess", %{room_id: room_id} do
    {_p1, _p2, word, state} = start_playing(room_id)

    assert {:error, :drawer_cannot_guess} =
             RoomServer.guess(room_id, resume_token_for(state, state.drawer_id), word)
  end

  test "non-member cannot guess", %{room_id: room_id} do
    {_p1, _p2, word, _state} = start_playing(room_id)
    assert {:error, :not_found} = RoomServer.guess(room_id, "not-a-player", word)
  end

  test "all guessed triggers turn_reveal", %{room_id: room_id} do
    Phoenix.PubSub.subscribe(Flamingo.PubSub, "game:#{room_id}")
    {p1, p2, word, state} = start_playing(room_id)
    guesser = if p1 == state.drawer_id, do: p2, else: p1

    assert :correct = RoomServer.guess(room_id, resume_token_for(state, guesser), word)

    {:ok, state} = RoomServer.get_state(room_id)
    assert state.phase == :turn_reveal
    assert_receive {:turn_reveal, ^word, _turn_end_time, _score_gains, _players}
  end

  test "turn_reveal tracks drawn_this_round", %{room_id: room_id} do
    {p1, p2, word, state} = start_playing(room_id)
    drawer = state.drawer_id
    guesser = if p1 == drawer, do: p2, else: p1

    RoomServer.guess(room_id, resume_token_for(state, guesser), word)

    {:ok, state} = RoomServer.get_state(room_id)
    assert MapSet.member?(state.drawn_this_round, drawer)
  end

  test "completed turn records drawing history", %{room_id: room_id} do
    {p1, p2, word, state} = start_playing(room_id)
    drawer = state.drawer_id
    guesser = if p1 == drawer, do: p2, else: p1

    start_event = %{
      "event_type" => "start",
      "x" => 10,
      "y" => 20,
      "color" => "#000000",
      "line_width" => 9
    }

    draw_event = %{
      "event_type" => "draw",
      "start_x" => 10,
      "start_y" => 20,
      "end_x" => 30,
      "end_y" => 40,
      "color" => "#000000",
      "line_width" => 9
    }

    RoomServer.draw_event(room_id, resume_token_for(state, drawer), start_event)
    RoomServer.draw_event(room_id, resume_token_for(state, drawer), draw_event)
    :correct = RoomServer.guess(room_id, resume_token_for(state, guesser), word)

    {:ok, state} = RoomServer.get_state(room_id)

    # Drawings are kept as compact ops (delta-encoded polylines), not raw
    # events.
    assert [
             %{
               drawer_id: ^drawer,
               word: ^word,
               round_number: 1,
               ops: [["p", "#000000", 9, [10, 20, 20, 20]]]
             }
           ] = state.final_drawings
  end

  test "completed turn records empty drawing history", %{room_id: room_id} do
    {p1, p2, word, state} = start_playing(room_id)
    drawer = state.drawer_id
    guesser = if p1 == drawer, do: p2, else: p1

    :correct = RoomServer.guess(room_id, resume_token_for(state, guesser), word)

    {:ok, state} = RoomServer.get_state(room_id)

    assert [
             %{
               drawer_id: ^drawer,
               word: ^word,
               round_number: 1,
               ops: []
             }
           ] = state.final_drawings
  end

  test "game ends after all players draw in all rounds", %{room_id: room_id} do
    Phoenix.PubSub.subscribe(Flamingo.PubSub, "game:#{room_id}")

    {:ok, p1_token, %{viewer_id: p1}} = RoomServer.join(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = RoomServer.join(room_id, "Bob")
    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    :ok =
      RoomServer.start_game(room_id, Map.fetch!(resume_tokens, p1), %{
        round_count: 1,
        turn_length: 30
      })

    play_turn = fn ->
      {:ok, state} = RoomServer.get_state(room_id)
      word = List.first(state.word_choices)
      :ok = RoomServer.select_word(room_id, Map.fetch!(resume_tokens, state.drawer_id), word)

      {:ok, state} = RoomServer.get_state(room_id)
      guesser = if p1 == state.drawer_id, do: p2, else: p1
      :correct = RoomServer.guess(room_id, Map.fetch!(resume_tokens, guesser), word)

      pid = RoomServer.whereis(room_id)
      _ = :sys.get_state(pid)

      {:ok, state} = RoomServer.get_state(room_id)
      assert state.phase == :turn_reveal

      send(pid, {:turn_reveal_timeout, state.phase_timer_ref})
      _ = :sys.get_state(pid)
    end

    play_turn.()

    {:ok, state} = RoomServer.get_state(room_id)
    assert state.phase == :word_choice
    assert state.current_round == 0

    play_turn.()

    {:ok, state} = RoomServer.get_state(room_id)
    assert state.phase == :game_ended
    assert_receive {:game_ended, _players, _final_drawings}
  end

  test "round increments after all players draw", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = RoomServer.join(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = RoomServer.join(room_id, "Bob")
    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    :ok =
      RoomServer.start_game(room_id, Map.fetch!(resume_tokens, p1), %{
        round_count: 2,
        turn_length: 30
      })

    pid = RoomServer.whereis(room_id)

    play_turn = fn ->
      {:ok, state} = RoomServer.get_state(room_id)
      word = List.first(state.word_choices)
      :ok = RoomServer.select_word(room_id, Map.fetch!(resume_tokens, state.drawer_id), word)

      {:ok, state} = RoomServer.get_state(room_id)
      guesser = if p1 == state.drawer_id, do: p2, else: p1
      :correct = RoomServer.guess(room_id, Map.fetch!(resume_tokens, guesser), word)

      {:ok, state} = RoomServer.get_state(room_id)
      send(pid, {:turn_reveal_timeout, state.phase_timer_ref})
      _ = :sys.get_state(pid)
    end

    play_turn.()
    play_turn.()

    {:ok, state} = RoomServer.get_state(room_id)
    assert state.phase == :word_choice
    assert state.current_round == 1
    assert state.drawn_this_round == MapSet.new()
  end

  test "selected words are excluded from later choices in the same game", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = RoomServer.join(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = RoomServer.join(room_id, "Bob")
    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    :ok =
      RoomServer.start_game(room_id, Map.fetch!(resume_tokens, p1), %{
        round_count: 1,
        turn_length: 30
      })

    pid = RoomServer.whereis(room_id)

    {:ok, state} = RoomServer.get_state(room_id)
    word = List.first(state.word_choices)
    :ok = RoomServer.select_word(room_id, Map.fetch!(resume_tokens, state.drawer_id), word)

    {:ok, state} = RoomServer.get_state(room_id)
    guesser = if p1 == state.drawer_id, do: p2, else: p1
    :correct = RoomServer.guess(room_id, Map.fetch!(resume_tokens, guesser), word)

    {:ok, state} = RoomServer.get_state(room_id)
    assert MapSet.member?(state.used_words, word)

    send(pid, {:turn_reveal_timeout, state.phase_timer_ref})
    _ = :sys.get_state(pid)

    {:ok, state} = RoomServer.get_state(room_id)
    refute word in state.word_choices
  end

  test "used word history resets when a new game starts", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = RoomServer.join(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = RoomServer.join(room_id, "Bob")
    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    :ok =
      RoomServer.start_game(room_id, Map.fetch!(resume_tokens, p1), %{
        round_count: 1,
        turn_length: 30
      })

    pid = RoomServer.whereis(room_id)

    play_turn = fn ->
      {:ok, state} = RoomServer.get_state(room_id)
      word = List.first(state.word_choices)
      :ok = RoomServer.select_word(room_id, Map.fetch!(resume_tokens, state.drawer_id), word)

      {:ok, state} = RoomServer.get_state(room_id)
      guesser = if p1 == state.drawer_id, do: p2, else: p1
      :correct = RoomServer.guess(room_id, Map.fetch!(resume_tokens, guesser), word)

      {:ok, state} = RoomServer.get_state(room_id)
      send(pid, {:turn_reveal_timeout, state.phase_timer_ref})
      _ = :sys.get_state(pid)

      word
    end

    first_word = play_turn.()
    play_turn.()

    {:ok, state} = RoomServer.get_state(room_id)
    assert state.phase == :game_ended
    assert MapSet.member?(state.used_words, first_word)

    :ok =
      RoomServer.start_game(room_id, Map.fetch!(resume_tokens, p1), %{
        round_count: 1,
        turn_length: 30
      })

    {:ok, state} = RoomServer.get_state(room_id)
    assert state.phase == :word_choice
    assert state.used_words == MapSet.new()
  end

  test "leave during playing reconciles turn completion", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = RoomServer.join(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = RoomServer.join(room_id, "Bob")
    {:ok, p3_token, %{viewer_id: p3}} = RoomServer.join(room_id, "Charlie")
    resume_tokens = %{p1 => p1_token, p2 => p2_token, p3 => p3_token}

    :ok =
      RoomServer.start_game(room_id, Map.fetch!(resume_tokens, p1), %{
        round_count: 1,
        turn_length: 30
      })

    {:ok, state} = RoomServer.get_state(room_id)
    word = List.first(state.word_choices)
    :ok = RoomServer.select_word(room_id, Map.fetch!(resume_tokens, state.drawer_id), word)

    {:ok, state} = RoomServer.get_state(room_id)
    drawer = state.drawer_id
    [g1, g2] = Enum.reject([p1, p2, p3], &(&1 == drawer))

    :correct = RoomServer.guess(room_id, Map.fetch!(resume_tokens, g1), word)

    {:ok, state} = RoomServer.get_state(room_id)
    assert state.phase == :playing

    :ok = RoomServer.leave(room_id, Map.fetch!(resume_tokens, g2))

    {:ok, state} = RoomServer.get_state(room_id)
    assert state.phase == :turn_reveal
  end

  test "leave during playing does not trigger reveal if guessers remain", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = RoomServer.join(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = RoomServer.join(room_id, "Bob")
    {:ok, p3_token, %{viewer_id: p3}} = RoomServer.join(room_id, "Charlie")
    resume_tokens = %{p1 => p1_token, p2 => p2_token, p3 => p3_token}

    :ok =
      RoomServer.start_game(room_id, Map.fetch!(resume_tokens, p1), %{
        round_count: 1,
        turn_length: 30
      })

    {:ok, state} = RoomServer.get_state(room_id)
    word = List.first(state.word_choices)
    :ok = RoomServer.select_word(room_id, Map.fetch!(resume_tokens, state.drawer_id), word)

    {:ok, state} = RoomServer.get_state(room_id)
    drawer = state.drawer_id
    [g1, _g2] = Enum.reject([p1, p2, p3], &(&1 == drawer))

    :ok = RoomServer.leave(room_id, Map.fetch!(resume_tokens, g1))

    {:ok, state} = RoomServer.get_state(room_id)
    assert state.phase == :playing
  end
end
