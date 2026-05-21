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
             GameServer.start_game(room_id, p1, %{turn_length: 10})
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

  defp start_playing(room_id) do
    {:ok, p1, _} = GameServer.join(room_id, "Alice")
    {:ok, p2, _} = GameServer.join(room_id, "Bob")
    :ok = GameServer.start_game(room_id, p1, %{round_count: 1, turn_length: 30})

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
    assert_receive {:feed_event, {:close_guess, ^guesser} = event}

    assert {:close, "You were close"} = Flamingo.Feed.format(event, guesser)
    assert nil == Flamingo.Feed.format(event, other_player)
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
    assert_receive {:feed_event, {:close_guess, ^guesser}}
  end

  test "wrong-length guesses are normal incorrect guesses", %{room_id: room_id} do
    Phoenix.PubSub.subscribe(Flamingo.PubSub, "game:#{room_id}")
    {p1, p2, word, state} = start_playing(room_id)
    guesser = if p1 == state.drawer_id, do: p2, else: p1
    wrong_length_guess = word <> "z"

    assert :incorrect = GameServer.guess(room_id, guesser, wrong_length_guess)

    assert_receive {:incorrect_guess, ^guesser, ^wrong_length_guess}
    refute_receive {:feed_event, {:close_guess, ^guesser}}
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

    assert [
             %{
               drawer_id: ^drawer,
               word: ^word,
               round_number: 1,
               events: [^start_event, ^draw_event]
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
               events: []
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

      pid = GenServer.whereis({:via, Registry, {Flamingo.GameRegistry, room_id}})
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

    pid = GenServer.whereis({:via, Registry, {Flamingo.GameRegistry, room_id}})

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
