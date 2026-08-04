defmodule Flamingo.GameServerTest do
  use ExUnit.Case, async: true

  alias Flamingo.GameServer
  alias Flamingo.GameSupervisor

  setup do
    room_id = "test-#{System.unique_integer([:positive])}"
    {:ok, ^room_id} = GameSupervisor.start_game(room_id)
    %{room_id: room_id}
  end

  test "first player becomes host", %{room_id: room_id} do
    {:ok, player_id, state} = GameServer.join(room_id, "Alice")
    assert state.host_id == player_id
    assert map_size(state.players) == 1
    assert state.player_order == [player_id]
    assert state.players[player_id].avatar == Flamingo.Avatar.default()
  end

  test "join stores a normalized avatar", %{room_id: room_id} do
    avatar = %{
      "body" => "4",
      "neck" => "3",
      "beak" => "99",
      "eyes" => "0",
      "tuft" => "2",
      "accessory" => "5"
    }

    {:ok, player_id, state} = GameServer.join(room_id, "Alice", avatar)

    assert state.players[player_id].avatar == %{
             "body" => 4,
             "neck" => 3,
             "beak" => 2,
             "eyes" => 0,
             "tuft" => 2,
             "accessory" => 5
           }
  end

  test "second player does not change host", %{room_id: room_id} do
    {:ok, p1, _} = GameServer.join(room_id, "Alice")
    {:ok, p2, state} = GameServer.join(room_id, "Bob")
    assert state.host_id == p1
    assert state.player_order == [p1, p2]
  end

  test "leave reassigns host when host leaves", %{room_id: room_id} do
    {:ok, p1, _} = GameServer.join(room_id, "Alice")
    {:ok, p2, _} = GameServer.join(room_id, "Bob")

    :ok = GameServer.leave(room_id, p1)

    {:ok, state} = GameServer.get_state(room_id)
    assert state.host_id == p2
    assert state.player_order == [p2]
    refute Map.has_key?(state.players, p1)
  end

  test "leave does not change host when non-host leaves", %{room_id: room_id} do
    {:ok, p1, _} = GameServer.join(room_id, "Alice")
    {:ok, p2, _} = GameServer.join(room_id, "Bob")

    :ok = GameServer.leave(room_id, p2)

    {:ok, state} = GameServer.get_state(room_id)
    assert state.host_id == p1
  end

  test "join broadcasts players_updated", %{room_id: room_id} do
    Phoenix.PubSub.subscribe(Flamingo.PubSub, "game:#{room_id}")
    GameServer.join(room_id, "Alice")
    assert_receive {:players_updated, _players, _order, _host}
  end

  test "start_game fails if not host", %{room_id: room_id} do
    {:ok, _p1, _} = GameServer.join(room_id, "Alice")
    {:ok, p2, _} = GameServer.join(room_id, "Bob")
    assert {:error, :not_host} = GameServer.start_game(room_id, p2, %{})
  end

  test "start_game fails with fewer than 2 players", %{room_id: room_id} do
    {:ok, p1, _} = GameServer.join(room_id, "Alice")
    assert {:error, :not_enough_players} = GameServer.start_game(room_id, p1, %{})
  end

  test "start_game fails with invalid round_count", %{room_id: room_id} do
    {:ok, p1, _} = GameServer.join(room_id, "Alice")
    {:ok, _p2, _} = GameServer.join(room_id, "Bob")
    assert {:error, :invalid_round_count} = GameServer.start_game(room_id, p1, %{round_count: 0})
    assert {:error, :invalid_round_count} = GameServer.start_game(room_id, p1, %{round_count: 6})
  end

  test "start_game fails with invalid turn_length", %{room_id: room_id} do
    {:ok, p1, _} = GameServer.join(room_id, "Alice")
    {:ok, _p2, _} = GameServer.join(room_id, "Bob")

    assert {:error, :invalid_turn_length} =
             GameServer.start_game(room_id, p1, %{turn_length: 14})

    assert {:error, :invalid_turn_length} =
             GameServer.start_game(room_id, p1, %{turn_length: 121})
  end

  test "start_game accepts turn_length boundaries", %{room_id: room_id} do
    {:ok, p1, _} = GameServer.join(room_id, "Alice")
    {:ok, _p2, _} = GameServer.join(room_id, "Bob")

    assert :ok = GameServer.start_game(room_id, p1, %{turn_length: 15})

    {:ok, state} = GameServer.get_state(room_id)
    assert state.turn_length == 15

    assert :ok = GameServer.start_game(room_id, p1, %{turn_length: 120})

    {:ok, state} = GameServer.get_state(room_id)
    assert state.turn_length == 120
  end

  test "start_game succeeds and broadcasts", %{room_id: room_id} do
    Phoenix.PubSub.subscribe(Flamingo.PubSub, "game:#{room_id}")
    {:ok, p1, _} = GameServer.join(room_id, "Alice")
    {:ok, _p2, _} = GameServer.join(room_id, "Bob")

    assert :ok = GameServer.start_game(room_id, p1, %{round_count: 2, turn_length: 45})
    assert_receive {:word_choice_started, _drawer_id, word_choices, _turn_end_time, 2, 45, 0}
    assert length(word_choices) == 3

    {:ok, state} = GameServer.get_state(room_id)
    assert state.phase == :word_choice
  end

  test "start_game uses custom words exclusively", %{room_id: room_id} do
    {:ok, p1, _} = GameServer.join(room_id, "Alice")
    {:ok, _p2, _} = GameServer.join(room_id, "Bob")
    custom_words = ["orbital llama", "velvet cactus", "disco teapot"]

    assert :ok = GameServer.start_game(room_id, p1, %{custom_words: custom_words})

    {:ok, state} = GameServer.get_state(room_id)
    assert state.custom_words == custom_words
    assert Enum.sort(state.word_choices) == Enum.sort(custom_words)
  end

  test "start_game can include deduplicated default words with custom words", %{room_id: room_id} do
    {:ok, p1, _} = GameServer.join(room_id, "Alice")
    {:ok, _p2, _} = GameServer.join(room_id, "Bob")

    assert :ok =
             GameServer.start_game(room_id, p1, %{
               custom_words: ["apple", "orbital llama"],
               include_default_words: true
             })

    {:ok, state} = GameServer.get_state(room_id)

    assert state.include_default_words
    assert state.custom_words == ["apple", "orbital llama"]
    assert length(state.word_choices) == 3
  end

  test "start_game rejects invalid custom words", %{room_id: room_id} do
    {:ok, p1, _} = GameServer.join(room_id, "Alice")
    {:ok, _p2, _} = GameServer.join(room_id, "Bob")

    assert {:error, :invalid_custom_words} =
             GameServer.start_game(room_id, p1, %{custom_words: ["cat, dog"]})

    assert {:error, :too_many_custom_words} =
             GameServer.start_game(room_id, p1, %{custom_words: Enum.map(1..3001, &"word #{&1}")})
  end

  test "minimum turn length schedules hints before the turn ends", %{room_id: room_id} do
    {:ok, p1, _} = GameServer.join(room_id, "Alice")
    {:ok, _p2, _} = GameServer.join(room_id, "Bob")
    :ok = GameServer.start_game(room_id, p1, %{turn_length: 15})

    {:ok, state} = GameServer.get_state(room_id)
    word = List.first(state.word_choices)
    :ok = GameServer.select_word(room_id, state.drawer_id, word)

    {:ok, state} = GameServer.get_state(room_id)

    assert is_reference(state.hint_timer_ref)

    schedule = GameServer.hint_schedule(word, 15)
    assert schedule != []
    assert Enum.all?(schedule, &(&1 < 15_000))
  end

  test "hint schedule spreads reveals across the turn for every round length" do
    for turn_length <- [15, 30, 45, 120] do
      schedule = GameServer.hint_schedule("flamingo", turn_length)
      turn_ms = turn_length * 1000

      # 8 letters -> up to half revealed
      assert length(schedule) == 4
      assert schedule == Enum.sort(schedule)
      assert Enum.all?(schedule, &(&1 >= trunc(turn_ms * 0.3)))
      assert Enum.all?(schedule, &(&1 < turn_ms))
    end
  end

  test "hint schedule reveals at most half the letters" do
    assert length(GameServer.hint_schedule("cat", 45)) == 1
    assert length(GameServer.hint_schedule("Pac-Man", 45)) == 3
    assert GameServer.hint_schedule("a", 45) == []
  end

  test "hints reveal letters while playing", %{room_id: room_id} do
    Phoenix.PubSub.subscribe(Flamingo.PubSub, "game:#{room_id}")
    {_p1, _p2, word, state} = start_playing(room_id)

    pid = GameServer.whereis(room_id)
    send(pid, {:reveal_hint, state.hint_timer_ref})

    assert_receive {:hint_revealed, [index]}
    assert index in 0..(String.length(word) - 1)

    {:ok, state} = GameServer.get_state(room_id)
    assert state.revealed_indices == [index]
  end

  test "turn reveal clears pending hint timer", %{room_id: room_id} do
    {p1, p2, word, state} = start_playing(room_id, %{turn_length: 15})
    drawer = state.drawer_id
    guesser = if p1 == drawer, do: p2, else: p1

    assert is_reference(state.hint_timer_ref)

    :correct = GameServer.guess(room_id, guesser, word)

    {:ok, state} = GameServer.get_state(room_id)
    assert state.phase == :turn_reveal
    assert state.hint_timer_ref == nil
  end

  test "join returns not_found for nonexistent room" do
    assert {:error, :not_found} = GameServer.join("no-such-room", "Alice")
  end

  test "rejoin succeeds for existing player", %{room_id: room_id} do
    {:ok, player_id, _} = GameServer.join(room_id, "Alice")
    {:ok, state} = GameServer.rejoin(room_id, player_id)
    assert Map.has_key?(state.players, player_id)
  end

  test "rejoin fails for unknown player", %{room_id: room_id} do
    assert {:error, :not_found} = GameServer.rejoin(room_id, "nonexistent")
  end

  test "leave during a game marks the player disconnected instead of removing them", %{
    room_id: room_id
  } do
    {p1, p2, _word, state} = start_playing(room_id)
    guesser = if p1 == state.drawer_id, do: p2, else: p1

    :ok = GameServer.leave(room_id, guesser)

    {:ok, state} = GameServer.get_state(room_id)
    assert Map.has_key?(state.players, guesser)
    refute Map.get(state.players, guesser).connected
    assert guesser in state.player_order
    assert is_reference(Map.get(state.disconnect_timers, guesser))
  end

  test "rejoin reconnects a disconnected player", %{room_id: room_id} do
    {p1, p2, _word, state} = start_playing(room_id)
    guesser = if p1 == state.drawer_id, do: p2, else: p1

    :ok = GameServer.leave(room_id, guesser)
    {:ok, state} = GameServer.rejoin(room_id, guesser)

    assert Map.get(state.players, guesser).connected
    refute Map.has_key?(state.disconnect_timers, guesser)
  end

  test "disconnected players are removed once the grace period expires", %{room_id: room_id} do
    {:ok, p1, _} = GameServer.join(room_id, "Alice")
    {:ok, p2, _} = GameServer.join(room_id, "Bob")
    {:ok, p3, _} = GameServer.join(room_id, "Charlie")
    :ok = GameServer.start_game(room_id, p1, %{round_count: 1, turn_length: 30})

    {:ok, state} = GameServer.get_state(room_id)
    word = List.first(state.word_choices)
    :ok = GameServer.select_word(room_id, state.drawer_id, word)

    {:ok, state} = GameServer.get_state(room_id)
    guesser = Enum.find([p1, p2, p3], &(&1 != state.drawer_id))

    :ok = GameServer.leave(room_id, guesser)

    {:ok, state} = GameServer.get_state(room_id)
    ref = Map.fetch!(state.disconnect_timers, guesser)

    pid = GameServer.whereis(room_id)
    send(pid, {:remove_player, guesser, ref})
    _ = :sys.get_state(pid)

    {:ok, state} = GameServer.get_state(room_id)
    refute Map.has_key?(state.players, guesser)
    refute guesser in state.player_order
  end

  test "a reconnected player is not removed by the stale grace timer", %{room_id: room_id} do
    {p1, p2, _word, state} = start_playing(room_id)
    guesser = if p1 == state.drawer_id, do: p2, else: p1

    :ok = GameServer.leave(room_id, guesser)

    {:ok, state} = GameServer.get_state(room_id)
    ref = Map.fetch!(state.disconnect_timers, guesser)

    {:ok, _state} = GameServer.rejoin(room_id, guesser)

    pid = GameServer.whereis(room_id)
    send(pid, {:remove_player, guesser, ref})
    _ = :sys.get_state(pid)

    {:ok, state} = GameServer.get_state(room_id)
    assert Map.has_key?(state.players, guesser)
    assert Map.get(state.players, guesser).connected
  end

  test "a disconnected guesser keeps their earned score", %{room_id: room_id} do
    {:ok, p1, _} = GameServer.join(room_id, "Alice")
    {:ok, p2, _} = GameServer.join(room_id, "Bob")
    {:ok, p3, _} = GameServer.join(room_id, "Charlie")
    :ok = GameServer.start_game(room_id, p1, %{round_count: 1, turn_length: 30})

    {:ok, state} = GameServer.get_state(room_id)
    word = List.first(state.word_choices)
    :ok = GameServer.select_word(room_id, state.drawer_id, word)

    {:ok, state} = GameServer.get_state(room_id)
    [g1, g2] = Enum.reject([p1, p2, p3], &(&1 == state.drawer_id))

    :correct = GameServer.guess(room_id, g1, word)
    :ok = GameServer.leave(room_id, g1)
    :correct = GameServer.guess(room_id, g2, word)

    {:ok, state} = GameServer.get_state(room_id)
    assert state.phase == :turn_reveal
    assert Map.get(state.players, g1).score > 0

    {:ok, state} = GameServer.rejoin(room_id, g1)
    assert Map.get(state.players, g1).score > 0
    assert Map.get(state.players, g1).connected
  end

  test "next drawer skips disconnected players", %{room_id: room_id} do
    {:ok, p1, _} = GameServer.join(room_id, "Alice")
    {:ok, p2, _} = GameServer.join(room_id, "Bob")
    {:ok, p3, _} = GameServer.join(room_id, "Charlie")
    :ok = GameServer.start_game(room_id, p1, %{round_count: 1, turn_length: 30})

    {:ok, state} = GameServer.get_state(room_id)
    word = List.first(state.word_choices)
    :ok = GameServer.select_word(room_id, state.drawer_id, word)

    {:ok, state} = GameServer.get_state(room_id)
    [g1, g2] = Enum.reject([p1, p2, p3], &(&1 == state.drawer_id))

    :correct = GameServer.guess(room_id, g1, word)
    :correct = GameServer.guess(room_id, g2, word)

    {:ok, state} = GameServer.get_state(room_id)
    assert state.phase == :turn_reveal

    # The next drawer in order disconnects during the reveal
    next_in_order =
      Enum.find(state.player_order, fn pid ->
        not MapSet.member?(state.drawn_this_round, pid)
      end)

    :ok = GameServer.leave(room_id, next_in_order)

    pid = GameServer.whereis(room_id)
    {:ok, state} = GameServer.get_state(room_id)
    send(pid, {:turn_reveal_timeout, state.phase_timer_ref})
    _ = :sys.get_state(pid)

    {:ok, state} = GameServer.get_state(room_id)
    assert state.phase == :word_choice
    assert state.drawer_id != next_in_order
  end

  defp start_playing(room_id, settings \\ %{round_count: 1, turn_length: 30}) do
    {:ok, p1, _} = GameServer.join(room_id, "Alice")
    {:ok, p2, _} = GameServer.join(room_id, "Bob")
    :ok = GameServer.start_game(room_id, p1, settings)

    {:ok, state} = GameServer.get_state(room_id)
    word = List.first(state.word_choices)
    :ok = GameServer.select_word(room_id, state.drawer_id, word)

    {:ok, state} = GameServer.get_state(room_id)
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

    assert :correct = GameServer.guess(room_id, guesser, word)
    assert_receive {:correct_guess, ^guesser}
  end

  test "incorrect guess broadcasts", %{room_id: room_id} do
    Phoenix.PubSub.subscribe(Flamingo.PubSub, "game:#{room_id}")
    {p1, p2, _word, state} = start_playing(room_id)
    guesser = if p1 == state.drawer_id, do: p2, else: p1

    assert :incorrect = GameServer.guess(room_id, guesser, "wrong-answer")
    assert_receive {:incorrect_guess, ^guesser, "wrong-answer"}
  end

  test "close guess sends private feedback instead of public chat", %{room_id: room_id} do
    Phoenix.PubSub.subscribe(Flamingo.PubSub, "game:#{room_id}")
    {p1, p2, word, state} = start_playing(room_id)
    guesser = if p1 == state.drawer_id, do: p2, else: p1
    other_player = if guesser == p1, do: p2, else: p1
    close_guess = String.replace_suffix(word, String.last(word), "z")

    assert :close = GameServer.guess(room_id, guesser, close_guess)

    refute_receive {:incorrect_guess, ^guesser, ^close_guess}
    assert_receive {:feed_event, %{event: {:close_guess, ^guesser, ^close_guess}} = entry}

    assert Flamingo.Feed.format(entry, guesser) == %{
             id: entry.id,
             kind: :close,
             text: "#{close_guess} was close!"
           }

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

    assert :close = GameServer.guess(room_id, guesser, close_guess)

    refute_receive {:incorrect_guess, ^guesser, ^close_guess}
    assert_receive {:feed_event, %{event: {:close_guess, ^guesser, ^close_guess}}}
  end

  test "wrong-length guesses are normal incorrect guesses", %{room_id: room_id} do
    Phoenix.PubSub.subscribe(Flamingo.PubSub, "game:#{room_id}")
    {p1, p2, word, state} = start_playing(room_id)
    guesser = if p1 == state.drawer_id, do: p2, else: p1
    wrong_length_guess = word <> "zz"

    assert :incorrect = GameServer.guess(room_id, guesser, wrong_length_guess)

    assert_receive {:incorrect_guess, ^guesser, ^wrong_length_guess}
    refute_receive {:feed_event, %{event: {:close_guess, ^guesser, _guess}}}
  end

  test "one-character insertion is a close guess", %{room_id: room_id} do
    Phoenix.PubSub.subscribe(Flamingo.PubSub, "game:#{room_id}")
    {p1, p2, word, state} = start_playing(room_id)
    guesser = if p1 == state.drawer_id, do: p2, else: p1
    close_guess = word <> "z"

    assert :close = GameServer.guess(room_id, guesser, close_guess)

    refute_receive {:incorrect_guess, ^guesser, ^close_guess}
    assert_receive {:feed_event, %{event: {:close_guess, ^guesser, ^close_guess}}}
  end

  test "one-character deletion is a close guess", %{room_id: room_id} do
    Phoenix.PubSub.subscribe(Flamingo.PubSub, "game:#{room_id}")
    {p1, p2, word, state} = start_playing(room_id)
    guesser = if p1 == state.drawer_id, do: p2, else: p1
    close_guess = String.slice(word, 0, String.length(word) - 1)

    assert :close = GameServer.guess(room_id, guesser, close_guess)

    refute_receive {:incorrect_guess, ^guesser, ^close_guess}
    assert_receive {:feed_event, %{event: {:close_guess, ^guesser, ^close_guess}}}
  end

  test "drawer cannot guess", %{room_id: room_id} do
    {_p1, _p2, word, state} = start_playing(room_id)
    assert {:error, :drawer_cannot_guess} = GameServer.guess(room_id, state.drawer_id, word)
  end

  test "non-member cannot guess", %{room_id: room_id} do
    {_p1, _p2, word, _state} = start_playing(room_id)
    assert {:error, :not_found} = GameServer.guess(room_id, "not-a-player", word)
  end

  test "all guessed triggers turn_reveal", %{room_id: room_id} do
    Phoenix.PubSub.subscribe(Flamingo.PubSub, "game:#{room_id}")
    {p1, p2, word, state} = start_playing(room_id)
    guesser = if p1 == state.drawer_id, do: p2, else: p1

    assert :correct = GameServer.guess(room_id, guesser, word)

    {:ok, state} = GameServer.get_state(room_id)
    assert state.phase == :turn_reveal
    assert_receive {:turn_reveal, ^word, _turn_end_time, _score_gains, _players}
  end

  test "turn_reveal tracks drawn_this_round", %{room_id: room_id} do
    {p1, p2, word, state} = start_playing(room_id)
    drawer = state.drawer_id
    guesser = if p1 == drawer, do: p2, else: p1

    GameServer.guess(room_id, guesser, word)

    {:ok, state} = GameServer.get_state(room_id)
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

    GameServer.draw_event(room_id, drawer, start_event)
    GameServer.draw_event(room_id, drawer, draw_event)
    :correct = GameServer.guess(room_id, guesser, word)

    {:ok, state} = GameServer.get_state(room_id)

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

    :correct = GameServer.guess(room_id, guesser, word)

    {:ok, state} = GameServer.get_state(room_id)

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

    {:ok, p1, _} = GameServer.join(room_id, "Alice")
    {:ok, p2, _} = GameServer.join(room_id, "Bob")
    :ok = GameServer.start_game(room_id, p1, %{round_count: 1, turn_length: 30})

    play_turn = fn ->
      {:ok, state} = GameServer.get_state(room_id)
      word = List.first(state.word_choices)
      :ok = GameServer.select_word(room_id, state.drawer_id, word)

      {:ok, state} = GameServer.get_state(room_id)
      guesser = if p1 == state.drawer_id, do: p2, else: p1
      :correct = GameServer.guess(room_id, guesser, word)

      pid = GameServer.whereis(room_id)
      _ = :sys.get_state(pid)

      {:ok, state} = GameServer.get_state(room_id)
      assert state.phase == :turn_reveal

      send(pid, {:turn_reveal_timeout, state.phase_timer_ref})
      _ = :sys.get_state(pid)
    end

    play_turn.()

    {:ok, state} = GameServer.get_state(room_id)
    assert state.phase == :word_choice
    assert state.current_round == 0

    play_turn.()

    {:ok, state} = GameServer.get_state(room_id)
    assert state.phase == :game_ended
    assert_receive {:game_ended, _players, _final_drawings}
  end

  test "round increments after all players draw", %{room_id: room_id} do
    {:ok, p1, _} = GameServer.join(room_id, "Alice")
    {:ok, p2, _} = GameServer.join(room_id, "Bob")
    :ok = GameServer.start_game(room_id, p1, %{round_count: 2, turn_length: 30})

    pid = GameServer.whereis(room_id)

    play_turn = fn ->
      {:ok, state} = GameServer.get_state(room_id)
      word = List.first(state.word_choices)
      :ok = GameServer.select_word(room_id, state.drawer_id, word)

      {:ok, state} = GameServer.get_state(room_id)
      guesser = if p1 == state.drawer_id, do: p2, else: p1
      :correct = GameServer.guess(room_id, guesser, word)

      {:ok, state} = GameServer.get_state(room_id)
      send(pid, {:turn_reveal_timeout, state.phase_timer_ref})
      _ = :sys.get_state(pid)
    end

    play_turn.()
    play_turn.()

    {:ok, state} = GameServer.get_state(room_id)
    assert state.phase == :word_choice
    assert state.current_round == 1
    assert state.drawn_this_round == MapSet.new()
  end

  test "selected words are excluded from later choices in the same game", %{room_id: room_id} do
    {:ok, p1, _} = GameServer.join(room_id, "Alice")
    {:ok, p2, _} = GameServer.join(room_id, "Bob")
    :ok = GameServer.start_game(room_id, p1, %{round_count: 1, turn_length: 30})

    pid = GameServer.whereis(room_id)

    {:ok, state} = GameServer.get_state(room_id)
    word = List.first(state.word_choices)
    :ok = GameServer.select_word(room_id, state.drawer_id, word)

    {:ok, state} = GameServer.get_state(room_id)
    guesser = if p1 == state.drawer_id, do: p2, else: p1
    :correct = GameServer.guess(room_id, guesser, word)

    {:ok, state} = GameServer.get_state(room_id)
    assert MapSet.member?(state.used_words, word)

    send(pid, {:turn_reveal_timeout, state.phase_timer_ref})
    _ = :sys.get_state(pid)

    {:ok, state} = GameServer.get_state(room_id)
    refute word in state.word_choices
  end

  test "used word history resets when a new game starts", %{room_id: room_id} do
    {:ok, p1, _} = GameServer.join(room_id, "Alice")
    {:ok, p2, _} = GameServer.join(room_id, "Bob")
    :ok = GameServer.start_game(room_id, p1, %{round_count: 1, turn_length: 30})

    pid = GameServer.whereis(room_id)

    play_turn = fn ->
      {:ok, state} = GameServer.get_state(room_id)
      word = List.first(state.word_choices)
      :ok = GameServer.select_word(room_id, state.drawer_id, word)

      {:ok, state} = GameServer.get_state(room_id)
      guesser = if p1 == state.drawer_id, do: p2, else: p1
      :correct = GameServer.guess(room_id, guesser, word)

      {:ok, state} = GameServer.get_state(room_id)
      send(pid, {:turn_reveal_timeout, state.phase_timer_ref})
      _ = :sys.get_state(pid)

      word
    end

    first_word = play_turn.()
    play_turn.()

    {:ok, state} = GameServer.get_state(room_id)
    assert state.phase == :game_ended
    assert MapSet.member?(state.used_words, first_word)

    :ok = GameServer.start_game(room_id, p1, %{round_count: 1, turn_length: 30})

    {:ok, state} = GameServer.get_state(room_id)
    assert state.phase == :word_choice
    assert state.used_words == MapSet.new()
  end

  test "leave during playing reconciles turn completion", %{room_id: room_id} do
    {:ok, p1, _} = GameServer.join(room_id, "Alice")
    {:ok, p2, _} = GameServer.join(room_id, "Bob")
    {:ok, p3, _} = GameServer.join(room_id, "Charlie")
    :ok = GameServer.start_game(room_id, p1, %{round_count: 1, turn_length: 30})

    {:ok, state} = GameServer.get_state(room_id)
    word = List.first(state.word_choices)
    :ok = GameServer.select_word(room_id, state.drawer_id, word)

    {:ok, state} = GameServer.get_state(room_id)
    drawer = state.drawer_id
    [g1, g2] = Enum.reject([p1, p2, p3], &(&1 == drawer))

    :correct = GameServer.guess(room_id, g1, word)

    {:ok, state} = GameServer.get_state(room_id)
    assert state.phase == :playing

    :ok = GameServer.leave(room_id, g2)

    {:ok, state} = GameServer.get_state(room_id)
    assert state.phase == :turn_reveal
  end

  test "leave during playing does not trigger reveal if guessers remain", %{room_id: room_id} do
    {:ok, p1, _} = GameServer.join(room_id, "Alice")
    {:ok, p2, _} = GameServer.join(room_id, "Bob")
    {:ok, p3, _} = GameServer.join(room_id, "Charlie")
    :ok = GameServer.start_game(room_id, p1, %{round_count: 1, turn_length: 30})

    {:ok, state} = GameServer.get_state(room_id)
    word = List.first(state.word_choices)
    :ok = GameServer.select_word(room_id, state.drawer_id, word)

    {:ok, state} = GameServer.get_state(room_id)
    drawer = state.drawer_id
    [g1, _g2] = Enum.reject([p1, p2, p3], &(&1 == drawer))

    :ok = GameServer.leave(room_id, g1)

    {:ok, state} = GameServer.get_state(room_id)
    assert state.phase == :playing
  end
end
