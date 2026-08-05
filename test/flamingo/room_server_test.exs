defmodule Flamingo.RoomServerTest do
  use ExUnit.Case, async: true

  alias Flamingo.RoomServer
  alias Flamingo.Room.Members
  alias Flamingo.RoomSupervisor

  setup do
    room_id = "test-#{System.unique_integer([:positive])}"
    {:ok, ^room_id} = RoomSupervisor.start_room(room_id)
    %{room_id: room_id}
  end

  defp resume_token_for(_state, seat_id), do: Process.get({:resume_token, seat_id})

  defp game_state(room_id), do: RoomServer.get_state(room_id)

  defp connection_count(state, player_id) do
    Enum.count(state.connections, fn {_pid, connection} ->
      connection.player_id == player_id
    end)
  end

  defp join_connected(room_id, player_name) do
    parent = self()
    child_id = {:player, make_ref()}

    pid =
      start_supervised!(
        Supervisor.child_spec(
          {Task, fn -> join_player(parent, room_id, player_name) end},
          id: child_id
        )
      )

    assert_receive {:player_connected, ^pid, {:ok, resume_token, snapshot}}
    Process.put({:player, resume_token}, pid)
    Process.put({:player_child, resume_token}, child_id)
    Process.put({:resume_token, snapshot.viewer_id}, resume_token)
    {:ok, resume_token, snapshot}
  end

  defp join_player(parent, room_id, player_name) do
    result =
      with {:ok, resume_token, _snapshot} <- RoomServer.join(room_id, player_name),
           {:ok, snapshot} <- RoomServer.connect(room_id, resume_token) do
        {:ok, resume_token, snapshot}
      end

    send(parent, {:player_connected, self(), result})
    player_loop(parent)
  end

  defp player_loop(parent) do
    receive do
      {:call, caller, ref, operation} ->
        send(caller, {ref, operation.()})
        player_loop(parent)

      {:room_snapshot, snapshot} ->
        send(parent, {:room_snapshot, snapshot})
        player_loop(parent)

      {:draw_event, event} ->
        send(parent, {:draw_event, self(), event})
        player_loop(parent)
    end
  end

  defp as_player(resume_token, operation) do
    pid = Process.get({:player, resume_token})
    ref = make_ref()
    send(pid, {:call, self(), ref, operation})
    assert_receive {^ref, result}
    result
  end

  defp snapshot_as(room_id, token), do: as_player(token, fn -> RoomServer.snapshot(room_id) end)

  defp start_game_as(room_id, token, settings),
    do: as_player(token, fn -> RoomServer.start_game(room_id, settings) end)

  defp select_word_as(room_id, token, word),
    do: as_player(token, fn -> RoomServer.select_word(room_id, word) end)

  defp guess_as(room_id, token, guess),
    do: as_player(token, fn -> RoomServer.guess(room_id, guess) end)

  defp draw_event_as(room_id, token, event),
    do: as_player(token, fn -> RoomServer.draw_event(room_id, event) end)

  defp leave_as(room_id, token), do: as_player(token, fn -> RoomServer.leave(room_id) end)

  defp start_connection(room_id, resume_token) do
    parent = self()
    child_id = make_ref()

    pid =
      start_supervised!(
        Supervisor.child_spec(
          {Task,
           fn ->
             send(parent, {:connected, self(), RoomServer.connect(room_id, resume_token)})
             connection_loop(parent)
           end},
          id: child_id
        )
      )

    assert_receive {:connected, ^pid, {:ok, snapshot}}
    {child_id, pid, snapshot}
  end

  defp connection_loop(parent) do
    receive do
      {:draw_event, event} ->
        send(parent, {:draw_event, self(), event})
        connection_loop(parent)

      :stop ->
        :ok
    end
  end

  defp flush_room_snapshots do
    receive do
      {:room_snapshot, _snapshot} -> flush_room_snapshots()
    after
      0 -> :ok
    end
  end

  defp receive_room_snapshots(player_ids, phase, snapshots \\ %{}) do
    if map_size(snapshots) == length(player_ids) do
      snapshots
    else
      assert_receive {:room_snapshot, snapshot}

      snapshots =
        if snapshot.phase == phase and snapshot.viewer_id in player_ids do
          Map.put(snapshots, snapshot.viewer_id, snapshot)
        else
          snapshots
        end

      receive_room_snapshots(player_ids, phase, snapshots)
    end
  end

  test "first player becomes host", %{room_id: room_id} do
    {:ok, _resume_token, %{viewer_id: player_id} = state} = join_connected(room_id, "Alice")
    assert state.mode == :scribble
    assert state.host_id == player_id
    assert map_size(state.players) == 1
    assert state.player_order == [player_id]
  end

  test "second player does not change host", %{room_id: room_id} do
    {:ok, _p1_token, %{viewer_id: p1}} = join_connected(room_id, "Alice")
    {:ok, _p2_token, %{viewer_id: p2} = state} = join_connected(room_id, "Bob")
    assert state.host_id == p1
    assert state.player_order == [p1, p2]
  end

  test "leave reassigns host when host leaves", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = join_connected(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = join_connected(room_id, "Bob")

    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    :ok = leave_as(room_id, Map.fetch!(resume_tokens, p1))

    {:ok, state} = snapshot_as(room_id, p2_token)
    assert state.host_id == p2
    assert state.player_order == [p2]
    refute Map.has_key?(state.players, p1)
  end

  test "leave does not change host when non-host leaves", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = join_connected(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = join_connected(room_id, "Bob")

    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    :ok = leave_as(room_id, Map.fetch!(resume_tokens, p2))

    {:ok, state} = snapshot_as(room_id, p1_token)
    assert state.host_id == p1
  end

  test "start_game fails if not host", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = join_connected(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = join_connected(room_id, "Bob")
    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    assert {:error, :not_host} =
             start_game_as(room_id, Map.fetch!(resume_tokens, p2), %{})
  end

  test "start_game fails with fewer than 2 players", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = join_connected(room_id, "Alice")
    resume_tokens = %{p1 => p1_token}

    assert {:error, :not_enough_players} =
             start_game_as(room_id, Map.fetch!(resume_tokens, p1), %{})
  end

  test "start_game fails with invalid round_count", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = join_connected(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = join_connected(room_id, "Bob")
    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    assert {:error, :invalid_round_count} =
             start_game_as(room_id, Map.fetch!(resume_tokens, p1), %{round_count: 0})

    assert {:error, :invalid_round_count} =
             start_game_as(room_id, Map.fetch!(resume_tokens, p1), %{round_count: 6})
  end

  test "start_game fails with invalid turn_length", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = join_connected(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = join_connected(room_id, "Bob")

    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    assert {:error, :invalid_turn_length} =
             start_game_as(room_id, Map.fetch!(resume_tokens, p1), %{turn_length: 14})

    assert {:error, :invalid_turn_length} =
             start_game_as(room_id, Map.fetch!(resume_tokens, p1), %{turn_length: 121})
  end

  test "start_game accepts turn_length boundaries", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = join_connected(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = join_connected(room_id, "Bob")

    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    assert :ok = start_game_as(room_id, Map.fetch!(resume_tokens, p1), %{turn_length: 15})

    {:ok, state} = game_state(room_id)
    assert state.game.turn_length == 15

    assert :ok =
             start_game_as(room_id, Map.fetch!(resume_tokens, p1), %{turn_length: 120})

    {:ok, state} = game_state(room_id)
    assert state.game.turn_length == 120
  end

  test "start_game enters word choice", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = join_connected(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = join_connected(room_id, "Bob")

    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    assert :ok =
             start_game_as(room_id, Map.fetch!(resume_tokens, p1), %{
               round_count: 2,
               turn_length: 45
             })

    {:ok, state} = game_state(room_id)
    assert state.game.phase == :word_choice
    assert state.game.round_count == 2
    assert state.game.turn_length == 45
    assert length(state.game.word_choices) == 3
  end

  test "snapshot projects word choices and words for the requesting player", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = join_connected(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = join_connected(room_id, "Bob")
    {:ok, p3_token, %{viewer_id: p3}} = join_connected(room_id, "Charlie")

    resume_tokens = %{p1 => p1_token, p2 => p2_token, p3 => p3_token}

    :ok =
      start_game_as(room_id, Map.fetch!(resume_tokens, p1), %{
        custom_words: ["secret", "other", "third"],
        round_count: 1,
        turn_length: 30
      })

    {:ok, state} = game_state(room_id)
    drawer_id = state.game.drawer_id
    guesser_ids = Enum.reject([p1, p2, p3], &(&1 == drawer_id))
    [first_guesser_id, second_guesser_id] = guesser_ids

    {:ok, drawer_snapshot} = snapshot_as(room_id, Map.fetch!(resume_tokens, drawer_id))

    {:ok, guesser_snapshot} =
      snapshot_as(room_id, Map.fetch!(resume_tokens, first_guesser_id))

    assert drawer_snapshot.mode == :scribble
    assert drawer_snapshot.word_choices == state.game.word_choices
    assert guesser_snapshot.word_choices == []
    refute Map.has_key?(guesser_snapshot, :phase_timer_ref)
    refute Map.has_key?(guesser_snapshot, :used_words)

    word = List.first(state.game.word_choices)
    :ok = select_word_as(room_id, Map.fetch!(resume_tokens, drawer_id), word)

    {:ok, drawer_snapshot} = snapshot_as(room_id, Map.fetch!(resume_tokens, drawer_id))

    {:ok, hidden_snapshot} =
      snapshot_as(room_id, Map.fetch!(resume_tokens, second_guesser_id))

    assert drawer_snapshot.word == word
    assert drawer_snapshot.word_visible?
    assert hidden_snapshot.word == String.replace(word, ~r/[^ ]/u, "_")
    refute hidden_snapshot.word_visible?

    assert :correct = guess_as(room_id, Map.fetch!(resume_tokens, first_guesser_id), word)

    {:ok, correct_guesser_snapshot} =
      snapshot_as(room_id, Map.fetch!(resume_tokens, first_guesser_id))

    {:ok, still_hidden_snapshot} =
      snapshot_as(room_id, Map.fetch!(resume_tokens, second_guesser_id))

    assert correct_guesser_snapshot.word == word
    assert correct_guesser_snapshot.word_visible?
    refute still_hidden_snapshot.word_visible?

    assert p2 in guesser_ids
    assert p3 in guesser_ids
  end

  test "direct notifications do not share secret projections", %{
    room_id: room_id
  } do
    {:ok, alice_token, %{viewer_id: alice}} = join_connected(room_id, "Alice")
    {:ok, bob_token, %{viewer_id: bob}} = join_connected(room_id, "Bob")
    tokens = %{alice => alice_token, bob => bob_token}
    flush_room_snapshots()

    :ok =
      start_game_as(room_id, alice_token, %{
        custom_words: ["secret", "other", "third"]
      })

    snapshots = receive_room_snapshots([alice, bob], :word_choice)

    {:ok, state} = game_state(room_id)
    drawer_id = state.game.drawer_id
    guesser_id = if drawer_id == alice, do: bob, else: alice

    assert Map.fetch!(snapshots, drawer_id).word_choices == state.game.word_choices
    assert Map.fetch!(snapshots, guesser_id).word_choices == []

    flush_room_snapshots()
    word = List.first(state.game.word_choices)
    :ok = select_word_as(room_id, Map.fetch!(tokens, drawer_id), word)

    snapshots = receive_room_snapshots([alice, bob], :playing)

    assert Map.fetch!(snapshots, drawer_id).word == word
    assert Map.fetch!(snapshots, drawer_id).word_visible?
    refute Map.fetch!(snapshots, guesser_id).word_visible?
    refute Map.fetch!(snapshots, guesser_id).word == word
  end

  test "drawing operations send ordered deltas without full snapshots", %{room_id: room_id} do
    {p1, p2, _word, state} = start_playing(room_id)
    drawer = state.game.drawer_id
    guesser = if drawer == p1, do: p2, else: p1
    drawer_token = resume_token_for(state, drawer)
    guesser_pid = Process.get({:player, resume_token_for(state, guesser)})
    originating_pid = Process.get({:player, drawer_token})
    flush_room_snapshots()

    first_event = %{"event_type" => "clear"}
    second_event = %{"event_type" => "fill", "x" => 10, "y" => 20, "color" => "#000000"}

    :ok = draw_event_as(room_id, drawer_token, first_event)
    _ = :sys.get_state(RoomServer.whereis(room_id))

    assert_receive {:draw_event, ^guesser_pid, ^first_event}
    refute_receive {:draw_event, ^originating_pid, _event}
    refute_receive {:room_snapshot, _snapshot}

    :ok = draw_event_as(room_id, drawer_token, second_event)
    _ = :sys.get_state(RoomServer.whereis(room_id))

    assert_receive {:draw_event, ^guesser_pid, ^second_event}
    refute_receive {:room_snapshot, _snapshot}

    {:ok, state} = game_state(room_id)
    assert state.game.current_drawing == [first_event, second_event]
  end

  test "a duplicate drawer connection receives deltas and a reconnect baseline", %{
    room_id: room_id
  } do
    {p1, p2, _word, state} = start_playing(room_id)
    drawer = state.game.drawer_id
    guesser = if drawer == p1, do: p2, else: p1
    drawer_token = resume_token_for(state, drawer)
    guesser_pid = Process.get({:player, resume_token_for(state, guesser)})
    originating_pid = Process.get({:player, drawer_token})
    first_event = %{"event_type" => "clear"}

    :ok = draw_event_as(room_id, drawer_token, first_event)
    _ = :sys.get_state(RoomServer.whereis(room_id))
    assert_receive {:draw_event, ^guesser_pid, ^first_event}

    {_connection_id, duplicate_pid, snapshot} = start_connection(room_id, drawer_token)
    assert snapshot.current_drawing == [first_event]
    flush_room_snapshots()

    second_event = %{"event_type" => "fill", "x" => 10, "y" => 20, "color" => "#000000"}
    :ok = draw_event_as(room_id, drawer_token, second_event)
    _ = :sys.get_state(RoomServer.whereis(room_id))

    assert_receive {:draw_event, ^duplicate_pid, ^second_event}
    assert_receive {:draw_event, ^guesser_pid, ^second_event}
    refute_receive {:draw_event, ^originating_pid, _event}
  end

  test "undo and invalid drawing operations do not send snapshots", %{room_id: room_id} do
    {p1, p2, word, state} = start_playing(room_id)
    drawer = state.game.drawer_id
    guesser = if drawer == p1, do: p2, else: p1
    drawer_token = resume_token_for(state, drawer)
    guesser_token = resume_token_for(state, guesser)
    guesser_pid = Process.get({:player, guesser_token})
    flush_room_snapshots()

    start_event = %{"event_type" => "start", "x" => 10, "y" => 20}
    :ok = draw_event_as(room_id, drawer_token, start_event)
    _ = :sys.get_state(RoomServer.whereis(room_id))
    assert_receive {:draw_event, ^guesser_pid, ^start_event}

    undo_event = %{"event_type" => "undo"}
    :ok = draw_event_as(room_id, drawer_token, undo_event)
    _ = :sys.get_state(RoomServer.whereis(room_id))
    assert_receive {:draw_event, ^guesser_pid, ^undo_event}
    refute_receive {:room_snapshot, _snapshot}

    {:ok, state} = game_state(room_id)
    assert state.game.current_drawing == []

    :ok = draw_event_as(room_id, drawer_token, undo_event)
    :ok = draw_event_as(room_id, guesser_token, start_event)
    _ = :sys.get_state(RoomServer.whereis(room_id))
    refute_receive {:draw_event, _pid, _event}

    :correct = guess_as(room_id, guesser_token, word)
    flush_room_snapshots()
    :ok = draw_event_as(room_id, drawer_token, start_event)
    _ = :sys.get_state(RoomServer.whereis(room_id))
    refute_receive {:draw_event, _pid, _event}

    {:ok, state} = game_state(room_id)
    assert state.game.phase == :turn_reveal
    assert state.game.current_drawing == []
  end

  test "rejected commands and stale timers do not notify connections", %{room_id: room_id} do
    {:ok, alice_token, _snapshot} = join_connected(room_id, "Alice")

    assert {:error, :not_enough_players} = start_game_as(room_id, alice_token, %{})
    refute_receive {:room_snapshot, _snapshot}

    send(RoomServer.whereis(room_id), {:game_timeout, :phase, :word_choice, make_ref()})
    _ = :sys.get_state(RoomServer.whereis(room_id))

    refute_receive {:room_snapshot, _snapshot}
  end

  test "restarting a phase replaces its timer generation", %{room_id: room_id} do
    {:ok, alice_token, _snapshot} = join_connected(room_id, "Alice")
    {:ok, _bob_token, _snapshot} = join_connected(room_id, "Bob")

    :ok = start_game_as(room_id, alice_token, %{})
    {:ok, first_state} = game_state(room_id)
    first_generation = first_state.phase_timer.generation

    :ok = start_game_as(room_id, alice_token, %{})
    {:ok, restarted_state} = game_state(room_id)
    restarted_generation = restarted_state.phase_timer.generation

    assert restarted_generation != first_generation
    flush_room_snapshots()

    send(
      RoomServer.whereis(room_id),
      {:game_timeout, :phase, :word_choice, first_generation}
    )

    _ = :sys.get_state(RoomServer.whereis(room_id))
    refute_receive {:room_snapshot, _snapshot}

    {:ok, current_state} = game_state(room_id)
    assert current_state.game.phase == :word_choice
    assert current_state.phase_timer.generation == restarted_generation
  end

  test "snapshot rejects an unregistered caller", %{room_id: room_id} do
    assert {:error, :not_found} = RoomServer.snapshot(room_id)
  end

  test "join separates the opaque credential from the public seat identity", %{room_id: room_id} do
    {:ok, seat_id_token, %{viewer_id: seat_id} = snapshot} = join_connected(room_id, "Alice")
    token = seat_id_token

    assert is_binary(token)
    assert byte_size(token) >= 32
    assert snapshot.viewer_id == seat_id
    refute token == seat_id
    refute inspect(snapshot) =~ token
    refute Map.has_key?(snapshot, :resume_tokens)
  end

  test "unregistered callers cannot inspect or mutate a game", %{room_id: room_id} do
    {:ok, _alice_token, %{viewer_id: alice, host_id: alice}} = join_connected(room_id, "Alice")
    {:ok, _bob_token, _bob_snapshot} = join_connected(room_id, "Bob")

    assert {:error, :not_found} = RoomServer.snapshot(room_id)
    assert {:error, :not_found} = RoomServer.start_game(room_id, %{})
    assert {:error, :not_found} = RoomServer.select_word(room_id, "cat")
    assert {:error, :not_found} = RoomServer.guess(room_id, "cat")

    {:ok, before_draw} = game_state(room_id)
    :ok = RoomServer.draw_event(room_id, %{"event_type" => "clear"})
    _ = :sys.get_state(RoomServer.whereis(room_id))
    assert {:ok, ^before_draw} = game_state(room_id)
  end

  test "resume tokens resolve only their own seat and cannot borrow authorization", %{
    room_id: room_id
  } do
    {:ok, alice_token, %{viewer_id: alice}} = join_connected(room_id, "Alice")
    {:ok, bob_token, %{viewer_id: bob}} = join_connected(room_id, "Bob")

    assert {:ok, %{viewer_id: ^alice}} = snapshot_as(room_id, alice_token)

    assert {:ok, %{viewer_id: ^bob}} = snapshot_as(room_id, bob_token)
    assert {:error, :not_host} = start_game_as(room_id, bob_token, %{})

    :ok = start_game_as(room_id, alice_token, %{})
    {:ok, state} = game_state(room_id)
    word = List.first(state.game.word_choices)

    if state.game.drawer_id == alice do
      assert {:error, :not_drawer} =
               select_word_as(room_id, bob_token, word)
    end
  end

  test "permanent lobby removal invalidates the removed credential", %{room_id: room_id} do
    {:ok, alice_token, %{viewer_id: alice}} = join_connected(room_id, "Alice")
    token = alice_token

    resume_tokens = %{alice => alice_token}

    :ok = leave_as(room_id, Map.fetch!(resume_tokens, alice))

    assert {:error, :not_found} = snapshot_as(room_id, token)
    assert {:error, :not_found} = RoomServer.connect(room_id, token)
  end

  test "start_game uses custom words exclusively", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = join_connected(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = join_connected(room_id, "Bob")
    custom_words = ["orbital llama", "velvet cactus", "disco teapot"]

    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    assert :ok =
             start_game_as(room_id, Map.fetch!(resume_tokens, p1), %{
               custom_words: custom_words
             })

    {:ok, state} = game_state(room_id)
    assert state.game.custom_words == custom_words
    assert Enum.sort(state.game.word_choices) == Enum.sort(custom_words)
  end

  test "start_game can include deduplicated default words with custom words", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = join_connected(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = join_connected(room_id, "Bob")

    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    assert :ok =
             start_game_as(room_id, Map.fetch!(resume_tokens, p1), %{
               custom_words: ["apple", "orbital llama"],
               include_default_words: true
             })

    {:ok, state} = game_state(room_id)

    assert state.game.include_default_words
    assert state.game.custom_words == ["apple", "orbital llama"]
    assert length(state.game.word_choices) == 3
  end

  test "start_game rejects invalid custom words", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = join_connected(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = join_connected(room_id, "Bob")

    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    assert {:error, :invalid_custom_words} =
             start_game_as(room_id, Map.fetch!(resume_tokens, p1), %{
               custom_words: ["cat, dog"]
             })

    assert {:error, :too_many_custom_words} =
             start_game_as(room_id, Map.fetch!(resume_tokens, p1), %{
               custom_words: Enum.map(1..3001, &"word #{&1}")
             })
  end

  test "minimum turn length schedules hints before the turn ends", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = join_connected(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = join_connected(room_id, "Bob")
    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    :ok = start_game_as(room_id, Map.fetch!(resume_tokens, p1), %{turn_length: 15})

    {:ok, state} = game_state(room_id)
    word = List.first(state.game.word_choices)
    :ok = select_word_as(room_id, Map.fetch!(resume_tokens, state.game.drawer_id), word)

    {:ok, state} = game_state(room_id)

    assert is_reference(state.hint_timer.generation)

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
    {_p1, _p2, word, state} = start_playing(room_id)

    pid = RoomServer.whereis(room_id)
    send(pid, {:game_timeout, :hint, :reveal_hint, state.hint_timer.generation})

    {:ok, state} = game_state(room_id)
    assert [index] = state.game.revealed_indices
    assert index in 0..(String.length(word) - 1)
  end

  test "turn reveal clears pending hint timer", %{room_id: room_id} do
    {p1, p2, word, state} = start_playing(room_id, %{turn_length: 15})
    drawer = state.game.drawer_id
    guesser = if p1 == drawer, do: p2, else: p1

    assert is_reference(state.hint_timer.generation)

    :correct = guess_as(room_id, resume_token_for(state, guesser), word)

    {:ok, state} = game_state(room_id)
    assert state.game.phase == :turn_reveal
    assert state.hint_timer == nil
  end

  test "join returns not_found for nonexistent room" do
    assert {:error, :not_found} = RoomServer.join("no-such-room", "Alice")
  end

  test "connect succeeds for an existing player", %{room_id: room_id} do
    {:ok, player_id_token, %{viewer_id: player_id}} = join_connected(room_id, "Alice")
    resume_tokens = %{player_id => player_id_token}

    {:ok, state} = RoomServer.connect(room_id, Map.fetch!(resume_tokens, player_id))
    assert Map.has_key?(state.players, player_id)
  end

  test "connect fails for an unknown credential", %{room_id: room_id} do
    assert {:error, :not_found} = RoomServer.connect(room_id, "nonexistent")
  end

  test "join remains offline until its first connection", %{room_id: room_id} do
    {:ok, resume_token, %{viewer_id: seat_id} = snapshot} = RoomServer.join(room_id, "Alice")

    refute Map.fetch!(snapshot.players, seat_id).connected

    assert {:ok, connected_snapshot} = RoomServer.connect(room_id, resume_token)
    assert Map.fetch!(connected_snapshot.players, seat_id).connected
  end

  test "closing one of two connections leaves the seat online", %{room_id: room_id} do
    {:ok, resume_token, %{viewer_id: seat_id}} = RoomServer.join(room_id, "Alice")
    {first_id, _first_pid, _snapshot} = start_connection(room_id, resume_token)
    {_second_id, _second_pid, _snapshot} = start_connection(room_id, resume_token)

    {:ok, state} = game_state(room_id)
    assert connection_count(state, seat_id) == 2

    stop_supervised!(first_id)
    _ = :sys.get_state(RoomServer.whereis(room_id))

    {:ok, state} = game_state(room_id)
    assert Members.online?(state.members, seat_id)
    assert connection_count(state, seat_id) == 1
    refute Map.has_key?(state.disconnect_timers, seat_id)
  end

  test "closing the final connection starts grace and reconnect rejects stale expiry", %{
    room_id: room_id
  } do
    {:ok, resume_token, %{viewer_id: seat_id}} = RoomServer.join(room_id, "Alice")
    {connection_id, _pid, _snapshot} = start_connection(room_id, resume_token)

    stop_supervised!(connection_id)
    _ = :sys.get_state(RoomServer.whereis(room_id))

    {:ok, state} = game_state(room_id)
    refute Members.online?(state.members, seat_id)
    stale_grace_ref = Map.fetch!(state.disconnect_timers, seat_id)

    {_replacement_id, _pid, snapshot} = start_connection(room_id, resume_token)
    assert Map.fetch!(snapshot.players, seat_id).connected

    send(RoomServer.whereis(room_id), {:remove_player, seat_id, stale_grace_ref})
    _ = :sys.get_state(RoomServer.whereis(room_id))

    {:ok, state} = game_state(room_id)
    assert Members.online?(state.members, seat_id)
    refute Map.has_key?(state.disconnect_timers, seat_id)
  end

  test "stale DOWN does not remove a current connection", %{room_id: room_id} do
    {:ok, resume_token, %{viewer_id: seat_id}} = RoomServer.join(room_id, "Alice")
    {_connection_id, connection_pid, _snapshot} = start_connection(room_id, resume_token)
    stale_ref = make_ref()

    send(RoomServer.whereis(room_id), {:DOWN, stale_ref, :process, connection_pid, :normal})
    _ = :sys.get_state(RoomServer.whereis(room_id))

    {:ok, state} = game_state(room_id)
    assert Members.online?(state.members, seat_id)
    assert connection_count(state, seat_id) == 1
  end

  test "leave during a game permanently removes the player", %{
    room_id: room_id
  } do
    {p1, p2, _word, state} = start_playing(room_id)
    guesser = if p1 == state.game.drawer_id, do: p2, else: p1

    :ok = leave_as(room_id, resume_token_for(state, guesser))

    {:ok, state} = game_state(room_id)
    refute match?({:ok, _seat}, Members.fetch(state.members, guesser))
    refute guesser in Members.ordered_ids(state.members)
    refute Map.has_key?(state.disconnect_timers, guesser)
  end

  test "next drawer skips removed players", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = join_connected(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = join_connected(room_id, "Bob")
    {:ok, p3_token, %{viewer_id: p3}} = join_connected(room_id, "Charlie")
    resume_tokens = %{p1 => p1_token, p2 => p2_token, p3 => p3_token}

    :ok =
      start_game_as(room_id, Map.fetch!(resume_tokens, p1), %{
        round_count: 1,
        turn_length: 30
      })

    {:ok, state} = game_state(room_id)
    word = List.first(state.game.word_choices)
    :ok = select_word_as(room_id, Map.fetch!(resume_tokens, state.game.drawer_id), word)

    {:ok, state} = game_state(room_id)
    [g1, g2] = Enum.reject([p1, p2, p3], &(&1 == state.game.drawer_id))

    :correct = guess_as(room_id, Map.fetch!(resume_tokens, g1), word)
    :correct = guess_as(room_id, Map.fetch!(resume_tokens, g2), word)

    {:ok, state} = game_state(room_id)
    assert state.game.phase == :turn_reveal

    # The next drawer in order leaves during the reveal.
    next_in_order =
      Enum.find([p1, p2, p3], fn pid ->
        not MapSet.member?(state.game.drawn_this_round, pid)
      end)

    :ok = leave_as(room_id, Map.fetch!(resume_tokens, next_in_order))

    pid = RoomServer.whereis(room_id)
    {:ok, state} = game_state(room_id)
    send(pid, {:game_timeout, :phase, :turn_reveal, state.phase_timer.generation})
    _ = :sys.get_state(pid)

    {:ok, state} = game_state(room_id)
    assert state.game.phase == :word_choice
    assert state.game.drawer_id != next_in_order
  end

  test "a late joiner spectates only the current turn", %{room_id: room_id} do
    {p1, p2, word, state} = start_playing(room_id)
    drawer = state.game.drawer_id
    guesser = if p1 == drawer, do: p2, else: p1
    guesser_token = resume_token_for(state, guesser)

    {:ok, spectator_token, %{viewer_id: spectator, participation: :spectator}} =
      join_connected(room_id, "Charlie")

    {:ok, spectator_snapshot} = snapshot_as(room_id, spectator_token)
    assert spectator_snapshot.participation == :spectator
    assert {:error, :spectator} = guess_as(room_id, spectator_token, word)

    :ok = draw_event_as(room_id, spectator_token, %{"event_type" => "clear"})
    _ = :sys.get_state(RoomServer.whereis(room_id))

    {:ok, state} = game_state(room_id)
    assert state.game.current_drawing == []
    assert state.game.participants[spectator] == :spectator

    assert :correct = guess_as(room_id, guesser_token, word)
    {:ok, state} = game_state(room_id)
    assert state.game.phase == :turn_reveal

    send(
      RoomServer.whereis(room_id),
      {:game_timeout, :phase, :turn_reveal, state.phase_timer.generation}
    )

    _ = :sys.get_state(RoomServer.whereis(room_id))

    {:ok, state} = game_state(room_id)
    assert state.game.phase == :word_choice
    assert state.game.drawer_id == guesser
    assert state.game.participants[spectator] == :active
    assert state.game.scores[spectator] == 0
  end

  defp start_playing(room_id, settings \\ %{round_count: 1, turn_length: 30}) do
    {:ok, p1_token, %{viewer_id: p1}} = join_connected(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = join_connected(room_id, "Bob")
    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    :ok = start_game_as(room_id, Map.fetch!(resume_tokens, p1), settings)

    {:ok, state} = game_state(room_id)
    word = List.first(state.game.word_choices)
    :ok = select_word_as(room_id, Map.fetch!(resume_tokens, state.game.drawer_id), word)

    {:ok, state} = game_state(room_id)
    {p1, p2, word, state}
  end

  test "select_word transitions to playing with timer", %{room_id: room_id} do
    {_p1, _p2, _word, state} = start_playing(room_id)
    assert state.game.phase == :playing
    assert state.turn_end_time != nil
    assert state.phase_timer.generation != nil
  end

  test "correct guess records the guesser", %{room_id: room_id} do
    {_p1, p2, word, state} = start_playing(room_id)

    guesser = if p2 == state.game.drawer_id, do: elem(start_playing(room_id), 0), else: p2
    guesser = if guesser == state.game.drawer_id, do: p2, else: guesser

    assert :correct = guess_as(room_id, resume_token_for(state, guesser), word)

    {:ok, state} = game_state(room_id)
    assert Map.has_key?(state.game.correct_guesses, guesser)
  end

  test "incorrect guess is added to the safe feed", %{room_id: room_id} do
    {p1, p2, _word, state} = start_playing(room_id)
    guesser = if p1 == state.game.drawer_id, do: p2, else: p1

    assert :incorrect =
             guess_as(room_id, resume_token_for(state, guesser), "wrong-answer")

    {:ok, snapshot} = snapshot_as(room_id, resume_token_for(state, guesser))
    assert %{kind: :guess, text: text} = List.last(snapshot.feed)
    assert text =~ "wrong-answer"
  end

  test "close guess sends private feedback instead of public chat", %{room_id: room_id} do
    {p1, p2, word, state} = start_playing(room_id)
    guesser = if p1 == state.game.drawer_id, do: p2, else: p1
    other_player = if guesser == p1, do: p2, else: p1
    replacement = if String.downcase(String.last(word)) == "z", do: "q", else: "z"
    close_guess = String.replace_suffix(word, String.last(word), replacement)

    assert :close =
             guess_as(room_id, resume_token_for(state, guesser), close_guess)

    {:ok, guesser_snapshot} = snapshot_as(room_id, resume_token_for(state, guesser))
    {:ok, other_snapshot} = snapshot_as(room_id, resume_token_for(state, other_player))

    assert %{kind: :close, text: "You were close"} = List.last(guesser_snapshot.feed)
    refute Enum.any?(other_snapshot.feed, &(&1.kind == :close))
  end

  test "close guess ignores case spacing and punctuation for same-length typos", %{
    room_id: room_id
  } do
    {p1, p2, word, state} = start_playing(room_id)
    guesser = if p1 == state.game.drawer_id, do: p2, else: p1

    replacement = if String.downcase(String.last(word)) == "z", do: "q", else: "z"

    close_guess =
      word
      |> String.replace_suffix(String.last(word), replacement)
      |> String.upcase()
      |> String.graphemes()
      |> Enum.join(" ")
      |> Kernel.<>("!")

    assert :close =
             guess_as(room_id, resume_token_for(state, guesser), close_guess)

    {:ok, snapshot} = snapshot_as(room_id, resume_token_for(state, guesser))
    assert List.last(snapshot.feed).kind == :close
  end

  test "wrong-length guesses are normal incorrect guesses", %{room_id: room_id} do
    {p1, p2, word, state} = start_playing(room_id)
    guesser = if p1 == state.game.drawer_id, do: p2, else: p1
    wrong_length_guess = word <> "zz"

    assert :incorrect =
             guess_as(
               room_id,
               resume_token_for(state, guesser),
               wrong_length_guess
             )

    {:ok, snapshot} = snapshot_as(room_id, resume_token_for(state, guesser))
    assert List.last(snapshot.feed).kind == :guess
  end

  test "one-character insertion is a close guess", %{room_id: room_id} do
    {p1, p2, word, state} = start_playing(room_id)
    guesser = if p1 == state.game.drawer_id, do: p2, else: p1
    close_guess = word <> "z"

    assert :close =
             guess_as(room_id, resume_token_for(state, guesser), close_guess)

    {:ok, snapshot} = snapshot_as(room_id, resume_token_for(state, guesser))
    assert List.last(snapshot.feed).kind == :close
  end

  test "one-character deletion is a close guess", %{room_id: room_id} do
    {p1, p2, word, state} = start_playing(room_id)
    guesser = if p1 == state.game.drawer_id, do: p2, else: p1
    close_guess = String.slice(word, 0, String.length(word) - 1)

    assert :close =
             guess_as(room_id, resume_token_for(state, guesser), close_guess)

    {:ok, snapshot} = snapshot_as(room_id, resume_token_for(state, guesser))
    assert List.last(snapshot.feed).kind == :close
  end

  test "drawer cannot guess", %{room_id: room_id} do
    {_p1, _p2, word, state} = start_playing(room_id)

    assert {:error, :drawer_cannot_guess} =
             guess_as(room_id, resume_token_for(state, state.game.drawer_id), word)
  end

  test "unregistered caller cannot guess", %{room_id: room_id} do
    {_p1, _p2, word, _state} = start_playing(room_id)
    assert {:error, :not_found} = RoomServer.guess(room_id, word)
  end

  test "all guessed triggers turn_reveal", %{room_id: room_id} do
    {p1, p2, word, state} = start_playing(room_id)
    guesser = if p1 == state.game.drawer_id, do: p2, else: p1

    assert :correct = guess_as(room_id, resume_token_for(state, guesser), word)

    {:ok, state} = game_state(room_id)
    assert state.game.phase == :turn_reveal
    assert state.game.word == word
  end

  test "scores are Scribble state projected onto public players", %{room_id: room_id} do
    {p1, p2, word, state} = start_playing(room_id)
    guesser = if p1 == state.game.drawer_id, do: p2, else: p1

    assert :correct = guess_as(room_id, resume_token_for(state, guesser), word)

    {:ok, state} = game_state(room_id)
    {:ok, snapshot} = snapshot_as(room_id, resume_token_for(state, guesser))

    refute Map.has_key?(Members.fetch!(state.members, guesser), :score)
    assert Map.fetch!(state.game.scores, guesser) > 0
    assert Map.fetch!(snapshot.players, guesser).score == Map.fetch!(state.game.scores, guesser)
  end

  test "disconnect and reconnect preserve Scribble score", %{room_id: room_id} do
    {p1, p2, word, state} = start_playing(room_id)
    drawer = state.game.drawer_id
    guesser = if p1 == drawer, do: p2, else: p1
    drawer_token = resume_token_for(state, drawer)
    guesser_token = resume_token_for(state, guesser)

    assert :correct = guess_as(room_id, guesser_token, word)
    {:ok, scored_snapshot} = snapshot_as(room_id, drawer_token)
    score = Map.fetch!(scored_snapshot.players, guesser).score
    assert score > 0

    stop_supervised!(Process.get({:player_child, guesser_token}))
    _ = :sys.get_state(RoomServer.whereis(room_id))

    {:ok, offline_snapshot} = snapshot_as(room_id, drawer_token)
    refute Map.fetch!(offline_snapshot.players, guesser).connected
    assert Map.fetch!(offline_snapshot.players, guesser).score == score

    {_connection_id, _pid, reconnected_snapshot} = start_connection(room_id, guesser_token)
    assert Map.fetch!(reconnected_snapshot.players, guesser).connected
    assert Map.fetch!(reconnected_snapshot.players, guesser).score == score
  end

  test "host succession does not change Scribble score", %{room_id: room_id} do
    {host, successor, word, state} = start_playing(room_id)
    assert state.game.drawer_id == host
    successor_token = resume_token_for(state, successor)

    assert :correct = guess_as(room_id, successor_token, word)
    {:ok, scored_snapshot} = snapshot_as(room_id, successor_token)
    score = Map.fetch!(scored_snapshot.players, successor).score
    assert score > 0

    :ok = leave_as(room_id, resume_token_for(state, host))

    {:ok, successor_snapshot} = snapshot_as(room_id, successor_token)
    assert successor_snapshot.host_id == successor
    assert Map.fetch!(successor_snapshot.players, successor).score == score
  end

  test "turn_reveal tracks drawn_this_round", %{room_id: room_id} do
    {p1, p2, word, state} = start_playing(room_id)
    drawer = state.game.drawer_id
    guesser = if p1 == drawer, do: p2, else: p1

    guess_as(room_id, resume_token_for(state, guesser), word)

    {:ok, state} = game_state(room_id)
    assert MapSet.member?(state.game.drawn_this_round, drawer)
  end

  test "completed turn records drawing history", %{room_id: room_id} do
    {p1, p2, word, state} = start_playing(room_id)
    drawer = state.game.drawer_id
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

    draw_event_as(room_id, resume_token_for(state, drawer), start_event)
    draw_event_as(room_id, resume_token_for(state, drawer), draw_event)
    :correct = guess_as(room_id, resume_token_for(state, guesser), word)

    {:ok, state} = game_state(room_id)

    # Drawings are kept as compact ops (delta-encoded polylines), not raw
    # events.
    assert [
             %{
               drawer_id: ^drawer,
               word: ^word,
               round_number: 1,
               ops: [["p", "#000000", 9, [10, 20, 20, 20]]]
             }
           ] = state.game.final_drawings
  end

  test "completed turn records empty drawing history", %{room_id: room_id} do
    {p1, p2, word, state} = start_playing(room_id)
    drawer = state.game.drawer_id
    guesser = if p1 == drawer, do: p2, else: p1

    :correct = guess_as(room_id, resume_token_for(state, guesser), word)

    {:ok, state} = game_state(room_id)

    assert [
             %{
               drawer_id: ^drawer,
               word: ^word,
               round_number: 1,
               ops: []
             }
           ] = state.game.final_drawings
  end

  test "game ends after all players draw in all rounds", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = join_connected(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = join_connected(room_id, "Bob")
    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    :ok =
      start_game_as(room_id, Map.fetch!(resume_tokens, p1), %{
        round_count: 1,
        turn_length: 30
      })

    play_turn = fn ->
      {:ok, state} = game_state(room_id)
      word = List.first(state.game.word_choices)
      :ok = select_word_as(room_id, Map.fetch!(resume_tokens, state.game.drawer_id), word)

      {:ok, state} = game_state(room_id)
      guesser = if p1 == state.game.drawer_id, do: p2, else: p1
      :correct = guess_as(room_id, Map.fetch!(resume_tokens, guesser), word)

      pid = RoomServer.whereis(room_id)
      _ = :sys.get_state(pid)

      {:ok, state} = game_state(room_id)
      assert state.game.phase == :turn_reveal

      send(pid, {:game_timeout, :phase, :turn_reveal, state.phase_timer.generation})
      _ = :sys.get_state(pid)
    end

    play_turn.()

    {:ok, state} = game_state(room_id)
    assert state.game.phase == :word_choice
    assert state.game.current_round == 0

    play_turn.()

    {:ok, state} = game_state(room_id)
    assert state.game.phase == :game_ended
    assert length(state.game.final_drawings) == 2
  end

  test "round increments after all players draw", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = join_connected(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = join_connected(room_id, "Bob")
    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    :ok =
      start_game_as(room_id, Map.fetch!(resume_tokens, p1), %{
        round_count: 2,
        turn_length: 30
      })

    pid = RoomServer.whereis(room_id)

    play_turn = fn ->
      {:ok, state} = game_state(room_id)
      word = List.first(state.game.word_choices)
      :ok = select_word_as(room_id, Map.fetch!(resume_tokens, state.game.drawer_id), word)

      {:ok, state} = game_state(room_id)
      guesser = if p1 == state.game.drawer_id, do: p2, else: p1
      :correct = guess_as(room_id, Map.fetch!(resume_tokens, guesser), word)

      {:ok, state} = game_state(room_id)
      send(pid, {:game_timeout, :phase, :turn_reveal, state.phase_timer.generation})
      _ = :sys.get_state(pid)
    end

    play_turn.()
    play_turn.()

    {:ok, state} = game_state(room_id)
    assert state.game.phase == :word_choice
    assert state.game.current_round == 1
    assert state.game.drawn_this_round == MapSet.new()
  end

  test "selected words are excluded from later choices in the same game", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = join_connected(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = join_connected(room_id, "Bob")
    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    :ok =
      start_game_as(room_id, Map.fetch!(resume_tokens, p1), %{
        round_count: 1,
        turn_length: 30
      })

    pid = RoomServer.whereis(room_id)

    {:ok, state} = game_state(room_id)
    word = List.first(state.game.word_choices)
    :ok = select_word_as(room_id, Map.fetch!(resume_tokens, state.game.drawer_id), word)

    {:ok, state} = game_state(room_id)
    guesser = if p1 == state.game.drawer_id, do: p2, else: p1
    :correct = guess_as(room_id, Map.fetch!(resume_tokens, guesser), word)

    {:ok, state} = game_state(room_id)
    assert MapSet.member?(state.game.used_words, word)

    send(pid, {:game_timeout, :phase, :turn_reveal, state.phase_timer.generation})
    _ = :sys.get_state(pid)

    {:ok, state} = game_state(room_id)
    refute word in state.game.word_choices
  end

  test "used word history resets when a new game starts", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = join_connected(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = join_connected(room_id, "Bob")
    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    :ok =
      start_game_as(room_id, Map.fetch!(resume_tokens, p1), %{
        round_count: 1,
        turn_length: 30
      })

    pid = RoomServer.whereis(room_id)

    play_turn = fn ->
      {:ok, state} = game_state(room_id)
      word = List.first(state.game.word_choices)
      :ok = select_word_as(room_id, Map.fetch!(resume_tokens, state.game.drawer_id), word)

      {:ok, state} = game_state(room_id)
      guesser = if p1 == state.game.drawer_id, do: p2, else: p1
      :correct = guess_as(room_id, Map.fetch!(resume_tokens, guesser), word)

      {:ok, state} = game_state(room_id)
      send(pid, {:game_timeout, :phase, :turn_reveal, state.phase_timer.generation})
      _ = :sys.get_state(pid)

      word
    end

    first_word = play_turn.()
    play_turn.()

    {:ok, state} = game_state(room_id)
    assert state.game.phase == :game_ended
    assert MapSet.member?(state.game.used_words, first_word)

    :ok =
      start_game_as(room_id, Map.fetch!(resume_tokens, p1), %{
        round_count: 1,
        turn_length: 30
      })

    {:ok, state} = game_state(room_id)
    assert state.game.phase == :word_choice
    assert state.game.used_words == MapSet.new()
  end

  test "leave during playing reconciles turn completion", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = join_connected(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = join_connected(room_id, "Bob")
    {:ok, p3_token, %{viewer_id: p3}} = join_connected(room_id, "Charlie")
    resume_tokens = %{p1 => p1_token, p2 => p2_token, p3 => p3_token}

    :ok =
      start_game_as(room_id, Map.fetch!(resume_tokens, p1), %{
        round_count: 1,
        turn_length: 30
      })

    {:ok, state} = game_state(room_id)
    word = List.first(state.game.word_choices)
    :ok = select_word_as(room_id, Map.fetch!(resume_tokens, state.game.drawer_id), word)

    {:ok, state} = game_state(room_id)
    drawer = state.game.drawer_id
    [g1, g2] = Enum.reject([p1, p2, p3], &(&1 == drawer))

    :correct = guess_as(room_id, Map.fetch!(resume_tokens, g1), word)

    {:ok, state} = game_state(room_id)
    assert state.game.phase == :playing

    :ok = leave_as(room_id, Map.fetch!(resume_tokens, g2))

    {:ok, state} = game_state(room_id)
    assert state.game.phase == :turn_reveal
  end

  test "leave during playing does not trigger reveal if guessers remain", %{room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = join_connected(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = join_connected(room_id, "Bob")
    {:ok, p3_token, %{viewer_id: p3}} = join_connected(room_id, "Charlie")
    resume_tokens = %{p1 => p1_token, p2 => p2_token, p3 => p3_token}

    :ok =
      start_game_as(room_id, Map.fetch!(resume_tokens, p1), %{
        round_count: 1,
        turn_length: 30
      })

    {:ok, state} = game_state(room_id)
    word = List.first(state.game.word_choices)
    :ok = select_word_as(room_id, Map.fetch!(resume_tokens, state.game.drawer_id), word)

    {:ok, state} = game_state(room_id)
    drawer = state.game.drawer_id
    [g1, _g2] = Enum.reject([p1, p2, p3], &(&1 == drawer))

    :ok = leave_as(room_id, Map.fetch!(resume_tokens, g1))

    {:ok, state} = game_state(room_id)
    assert state.game.phase == :playing
  end
end
