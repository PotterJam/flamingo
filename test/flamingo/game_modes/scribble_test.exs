defmodule Flamingo.GameModes.ScribbleTest do
  use ExUnit.Case, async: true

  alias Flamingo.GameModes.Scribble

  @now ~U[2026-01-01 00:00:00Z]

  defp roster(connected \\ true) do
    %{
      players: %{
        "a" => %{id: "a", name: "Alice", connected: connected},
        "b" => %{id: "b", name: "Bob", connected: connected}
      },
      player_order: ["a", "b"],
      host_id: "a"
    }
  end

  defp context(options \\ []) do
    %{
      roster: Keyword.get(options, :roster, roster()),
      actor_id: Keyword.get(options, :actor_id, "a"),
      now: @now,
      word_choices: fn _count, used, _custom, _defaults ->
        Enum.reject(["cat", "dog", "bird"], &MapSet.member?(used, &1))
      end,
      select_candidate: &List.first/1
    }
  end

  defp admitted do
    state = Scribble.new()
    {:ok, %{state: state}} = Scribble.admit_member(state, %{id: "a", name: "Alice"}, context())
    {:ok, %{state: state}} = Scribble.admit_member(state, %{id: "b", name: "Bob"}, context())
    state
  end

  test "start, drawing, guessing, and viewer projection are pure" do
    {:ok, %{state: state, timers: timers}} =
      Scribble.start(admitted(), %{round_count: 1}, context())

    assert state.phase == :word_choice
    assert {:schedule_phase_timeout, :word_choice, 10_000} in timers

    {:ok, %{state: state}} = Scribble.command(state, "a", {:select_word, "cat"}, context())

    {:ok, %{state: state, drawing_delta: event}} =
      Scribble.command(state, "a", {:draw, %{"event_type" => "start"}}, context())

    assert event == %{"event_type" => "start"}
    assert Scribble.view(state, "b", roster()).word == "___"

    {:ok, %{state: state, reply: :correct}} =
      Scribble.command(state, "b", {:guess, "CAT"}, context())

    assert state.phase == :turn_reveal
    assert Scribble.view(state, "b", roster()).word == "cat"
    assert state.scores["b"] > 0
  end

  test "partial restart keeps scores and feed while resetting match fields" do
    {:ok, %{state: state}} =
      Scribble.start(admitted(), %{round_count: 2, turn_length: 45}, context())

    state = %{state | scores: %{"a" => 10, "b" => 20}}
    feed = state.feed
    {:ok, %{state: restarted}} = Scribble.start(state, %{round_count: 1}, context())
    assert restarted.turn_length == 45
    assert restarted.scores == %{"a" => 10, "b" => 20}
    assert Enum.take(restarted.feed.events, length(feed.events)) == feed.events
    assert restarted.used_words == MapSet.new()
  end

  test "late admits are active and final results remain immutable on removal" do
    state = admitted()
    {:ok, %{state: state}} = Scribble.admit_member(state, %{id: "c", name: "Cara"}, context())
    assert state.participants["c"] == :active

    final = %{players: %{}, player_order: [], drawings: []}
    state = %{state | phase: :game_ended, final_result: final}
    post = %{roster() | players: Map.delete(roster().players, "b"), player_order: ["a"]}

    {:ok, %{state: state}} =
      Scribble.remove_member(state, "b", %{name: "Bob"}, context(roster: post))

    assert state.final_result == final
    refute Map.has_key?(state.participants, "b")
  end

  test "deterministic hints reveal candidates and schedule the next hint" do
    {:ok, %{state: state}} = Scribble.start(admitted(), %{}, context())
    {:ok, %{state: state}} = Scribble.command(state, "a", {:select_word, "bird"}, context())
    {:ok, %{state: hinted, timers: timers}} = Scribble.timeout(state, :reveal_hint, context())
    assert hinted.revealed_indices == [0]
    assert match?([{:schedule_hint_timeout, :reveal_hint, _}], timers)
  end

  test "online is an unchanged continuing transition while offline reconciles completion" do
    three_player_roster = %{
      roster()
      | players: Map.put(roster().players, "c", %{id: "c", name: "Cara", connected: true}),
        player_order: ["a", "b", "c"]
    }

    {:ok, %{state: state}} =
      Scribble.admit_member(
        admitted(),
        %{id: "c", name: "Cara"},
        context(roster: three_player_roster)
      )

    state = %{
      state
      | phase: :playing,
        drawer_id: "a",
        word: "cat",
        correct_guesses: %{"b" => @now}
    }

    {:ok, %{state: online, status: :continue, timers: []}} =
      Scribble.connection_changed(state, "c", :online, context(roster: three_player_roster))

    assert online == state

    offline_roster =
      put_in(three_player_roster, [:players, "c", :connected], false)

    {:ok, %{state: offline, status: :continue, timers: timers}} =
      Scribble.connection_changed(state, "c", :offline, context(roster: offline_roster))

    assert offline.phase == :turn_reveal
    assert {:schedule_phase_timeout, :turn_reveal, 5_000} in timers
  end

  test "drawing undo removes the latest operation and empty undo is ignored" do
    state = %{admitted() | phase: :playing, drawer_id: "a", word: "cat"}
    start = %{"event_type" => "start"}
    point = %{"event_type" => "point"}

    {:ok, %{state: state}} = Scribble.command(state, "a", {:draw, start}, context())
    {:ok, %{state: state}} = Scribble.command(state, "a", {:draw, point}, context())

    {:ok, %{state: undone, drawing_delta: %{"event_type" => "undo"}}} =
      Scribble.command(state, "a", {:draw, %{"event_type" => "undo"}}, context())

    assert undone.current_drawing == []
    assert :ignored = Scribble.command(undone, "a", {:draw, %{"event_type" => "undo"}}, context())
    assert :ignored = Scribble.command(state, "b", {:draw, start}, context())
  end

  test "close and incorrect guesses do not leak the word to the guesser" do
    state = %{admitted() | phase: :playing, drawer_id: "a", word: "cat"}

    assert {:ok, %{reply: :close, status: :continue}} =
             Scribble.command(state, "b", {:guess, "bat"}, context())

    {:ok, %{state: state, reply: :incorrect}} =
      Scribble.command(state, "b", {:guess, "horse"}, context())

    guesser = Scribble.view(state, "b", roster())
    drawer = Scribble.view(state, "a", roster())
    assert guesser.word == "___"
    refute guesser.word_visible?
    assert drawer.word == "cat"
    assert drawer.word_visible?
  end

  test "correct guesses preserve exact punctuation and spacing behavior" do
    state = %{admitted() | phase: :playing, drawer_id: "a", word: "cat"}

    for correct_guess <- ["CAT", " cat "] do
      assert {:ok, %{reply: :correct}} =
               Scribble.command(state, "b", {:guess, correct_guess}, context())
    end

    for incorrect_guess <- ["c a t", "cat!"] do
      assert {:ok, %{reply: :incorrect}} =
               Scribble.command(state, "b", {:guess, incorrect_guess}, context())
    end
  end

  test "a complete deterministic game finishes with both turns and final results" do
    {:ok, %{state: state}} = Scribble.start(admitted(), %{round_count: 1}, context())

    {:ok, %{state: state}} =
      Scribble.command(state, "a", {:select_word, "cat"}, context())

    {:ok, %{state: state}} = Scribble.command(state, "b", {:guess, "cat"}, context())
    assert state.phase == :turn_reveal

    {:ok, %{state: state}} = Scribble.timeout(state, :turn_reveal, context())
    assert state.phase == :word_choice
    assert state.drawer_id == "b"

    {:ok, %{state: state}} =
      Scribble.command(state, "b", {:select_word, "dog"}, context())

    {:ok, %{state: state}} = Scribble.command(state, "a", {:guess, "dog"}, context())

    assert {:ok,
            %{
              state: finished,
              status: {:finished, result},
              timers: [:cancel_phase_timeout, :cancel_hint_timeout]
            }} = Scribble.timeout(state, :turn_reveal, context())

    assert finished.phase == :game_ended
    assert result.player_order == ["a", "b"]
    assert length(result.drawings) == 2
  end

  test "word exhaustion finishes without scheduling another phase" do
    exhausted_context = %{
      context()
      | word_choices: fn _count, _used, _custom, _defaults -> [] end
    }

    assert {:ok,
            %{
              state: %{phase: :game_ended},
              status: {:finished, result},
              timers: [:cancel_phase_timeout, :cancel_hint_timeout]
            }} = Scribble.start(admitted(), %{round_count: 1}, exhausted_context)

    assert result.drawings == []
  end
end
