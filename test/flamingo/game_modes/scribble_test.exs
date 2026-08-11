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
      select_candidate: Keyword.get(options, :select_candidate, &List.first/1)
    }
  end

  defp admitted do
    state = Scribble.new()
    {:ok, %{state: state}} = Scribble.admit_member(state, %{id: "a", name: "Alice"}, context())
    {:ok, %{state: state}} = Scribble.admit_member(state, %{id: "b", name: "Bob"}, context())
    state
  end

  defp complete_turn(state, game_context, drawing_events \\ []) do
    word = List.first(state.word_choices)
    drawer = state.drawer_id
    guesser = if drawer == "a", do: "b", else: "a"
    {:ok, %{state: state}} = Scribble.command(state, drawer, {:select_word, word}, game_context)

    state =
      Enum.reduce(drawing_events, state, fn event, state ->
        {:ok, %{state: state}} = Scribble.command(state, drawer, {:draw, event}, game_context)
        state
      end)

    {:ok, %{state: state}} = Scribble.command(state, guesser, {:guess, word}, game_context)
    {:ok, result} = Scribble.timeout(state, :turn_reveal, game_context)
    {result, word}
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

  test "constraint roulette selects and projects a constraint for each turn" do
    pick_last = fn candidates -> List.last(candidates) end

    {:ok, %{state: roulette}} =
      Scribble.start(
        admitted(),
        %{round_count: 1, game_variant: :constraint_roulette},
        context(select_candidate: pick_last)
      )

    assert roulette.constraint == :mirror
    assert Scribble.view(roulette, "b", roster()).constraint == :mirror
    assert Scribble.view(roulette, "b", roster()).game_variant == :constraint_roulette

    {:ok, %{state: classic}} = Scribble.start(admitted(), %{round_count: 1}, context())
    assert classic.constraint == nil
  end

  test "single-stroke and straight-line constraints are enforced by the game" do
    drawing_state = %{
      admitted()
      | phase: :playing,
        drawer_id: "a",
        word: "cat",
        constraint: :single_stroke
    }

    start_event = %{"event_type" => "start", "x" => 1, "y" => 1}
    end_event = %{"event_type" => "end", "end_x" => 2, "end_y" => 2}

    {:ok, %{state: drawing_state}} =
      Scribble.command(drawing_state, "a", {:draw, start_event}, context())

    {:ok, %{state: drawing_state}} =
      Scribble.command(drawing_state, "a", {:draw, end_event}, context())

    assert :ignored == Scribble.command(drawing_state, "a", {:draw, start_event}, context())

    assert :ignored ==
             Scribble.command(drawing_state, "a", {:draw, %{"event_type" => "clear"}}, context())

    straight_state = %{drawing_state | constraint: :straight_lines, current_drawing: []}

    assert :ignored ==
             Scribble.command(
               straight_state,
               "a",
               {:draw, %{"event_type" => "draw"}},
               context()
             )

    assert {:ok, _result} =
             Scribble.command(straight_state, "a", {:draw, start_event}, context())

    assert :ignored == Scribble.command(straight_state, "a", {:draw, end_event}, context())
  end

  test "lobby and game-ended admits are active and final results remain immutable on removal" do
    state = admitted()
    {:ok, %{state: state}} = Scribble.admit_member(state, %{id: "c", name: "Cara"}, context())
    assert state.participants["c"] == :active

    final = %{players: %{}, player_order: [], drawings: []}
    state = %{state | phase: :game_ended, final_result: final}
    {:ok, %{state: state}} = Scribble.admit_member(state, %{id: "c", name: "Cara"}, context())
    assert state.participants["c"] == :active

    post = %{roster() | players: Map.delete(roster().players, "b"), player_order: ["a"]}

    {:ok, %{state: state}} =
      Scribble.remove_member(state, "b", %{name: "Bob"}, context(roster: post))

    assert state.final_result == final
    refute Map.has_key?(state.participants, "b")
  end

  test "in-progress admits spectate only until the next turn" do
    three_player_roster = %{
      roster()
      | players: Map.put(roster().players, "c", %{id: "c", name: "Cara", connected: true}),
        player_order: ["a", "b", "c"]
    }

    for phase <- [:word_choice, :playing, :turn_reveal] do
      state = %{admitted() | phase: phase, drawer_id: "a", word: "cat"}

      {:ok, %{state: state}} =
        Scribble.admit_member(
          state,
          %{id: "c", name: "Cara"},
          context(roster: three_player_roster)
        )

      assert state.participants["c"] == :spectator
      assert state.scores["c"] == 0
      assert Scribble.view(state, "c", three_player_roster).participation == :spectator
    end

    state = %{admitted() | phase: :playing, drawer_id: "a", word: "cat"}

    {:ok, %{state: state}} =
      Scribble.admit_member(state, %{id: "c", name: "Cara"}, context(roster: three_player_roster))

    spectator_context = context(roster: three_player_roster)

    assert {:error, :spectator} =
             Scribble.command(state, "c", {:guess, "cat"}, spectator_context)

    assert :ignored =
             Scribble.command(state, "c", {:draw, %{"event_type" => "clear"}}, spectator_context)

    {:ok, %{state: reveal}} =
      Scribble.command(state, "b", {:guess, "cat"}, spectator_context)

    assert reveal.phase == :turn_reveal
    refute Map.has_key?(reveal.score_gains, "c")

    {:ok, %{state: next}} =
      Scribble.timeout(reveal, :turn_reveal, context(roster: three_player_roster))

    assert next.participants["c"] == :active
    assert next.drawer_id == "b"
    assert next.phase == :word_choice
  end

  test "a spectator admitted on the final existing turn extends the current round" do
    three_player_roster = %{
      roster()
      | players: Map.put(roster().players, "c", %{id: "c", name: "Cara", connected: true}),
        player_order: ["a", "b", "c"]
    }

    state = %{
      admitted()
      | phase: :turn_reveal,
        drawer_id: "b",
        current_round: 0,
        round_count: 1,
        drawn_this_round: MapSet.new(["a", "b"])
    }

    {:ok, %{state: state}} =
      Scribble.admit_member(state, %{id: "c", name: "Cara"}, context(roster: three_player_roster))

    {:ok, %{state: next, status: :continue}} =
      Scribble.timeout(state, :turn_reveal, context(roster: three_player_roster))

    assert next.phase == :word_choice
    assert next.drawer_id == "c"
    assert next.participants["c"] == :active
    assert next.current_round == 0
  end

  test "spectators do not affect the drawer scoring denominator" do
    four_player_roster = %{
      players: %{
        "a" => %{id: "a", name: "Alice", connected: true},
        "b" => %{id: "b", name: "Bob", connected: true},
        "c" => %{id: "c", name: "Cara", connected: true},
        "d" => %{id: "d", name: "Drew", connected: true}
      },
      player_order: ["a", "b", "c", "d"],
      host_id: "a"
    }

    {:ok, %{state: state}} =
      Scribble.admit_member(admitted(), %{id: "c", name: "Cara"}, context())

    state = %{state | phase: :playing, drawer_id: "a", word: "cat"}

    {:ok, %{state: state}} =
      Scribble.admit_member(
        state,
        %{id: "d", name: "Drew"},
        context(roster: four_player_roster)
      )

    game_context = context(roster: four_player_roster)
    {:ok, %{state: state}} = Scribble.command(state, "b", {:guess, "cat"}, game_context)
    {:ok, %{state: reveal}} = Scribble.command(state, "c", {:guess, "cat"}, game_context)

    assert reveal.phase == :turn_reveal
    assert reveal.score_gains["a"] == 350
    refute Map.has_key?(reveal.score_gains, "d")
  end

  test "reconnect preserves spectator status and start promotes all participants" do
    state = %{admitted() | phase: :playing, drawer_id: "a", word: "cat"}
    {:ok, %{state: state}} = Scribble.admit_member(state, %{id: "c", name: "Cara"}, context())

    {:ok, %{state: reconnected}} = Scribble.connection_changed(state, "c", :online, context())
    assert reconnected.participants["c"] == :spectator

    rematch_roster = %{
      roster()
      | players: Map.put(roster().players, "c", %{id: "c", name: "Cara", connected: true}),
        player_order: ["a", "b", "c"]
    }

    {:ok, %{state: restarted}} = Scribble.start(reconnected, %{}, context(roster: rematch_roster))
    assert Enum.all?(restarted.participants, fn {_id, status} -> status == :active end)
  end

  test "deterministic hints reveal candidates and schedule the next hint" do
    {:ok, %{state: state}} = Scribble.start(admitted(), %{}, context())
    {:ok, %{state: state}} = Scribble.command(state, "a", {:select_word, "bird"}, context())
    {:ok, %{state: hinted, timers: timers}} = Scribble.timeout(state, :reveal_hint, context())
    assert hinted.revealed_indices == [0]
    assert match?([{:schedule_hint_timeout, :reveal_hint, _}], timers)
  end

  test "hint schedule spreads reveals across the turn for every round length" do
    for turn_length <- [15, 30, 45, 120] do
      schedule = Scribble.hint_schedule("flamingo", turn_length)
      turn_ms = turn_length * 1000

      # 8 letters -> up to half revealed
      assert length(schedule) == 4
      assert schedule == Enum.sort(schedule)
      assert Enum.all?(schedule, &(&1 >= trunc(turn_ms * 0.3)))
      assert Enum.all?(schedule, &(&1 < turn_ms))
    end
  end

  test "hint schedule reveals at most half the letters" do
    assert length(Scribble.hint_schedule("cat", 45)) == 1
    assert length(Scribble.hint_schedule("Pac-Man", 45)) == 3
    assert Scribble.hint_schedule("a", 45) == []
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

  test "removing guessers reconciles completion without ending an active turn early" do
    three_player_roster = %{
      players: %{
        "a" => %{id: "a", name: "Alice", connected: true},
        "b" => %{id: "b", name: "Bob", connected: true},
        "c" => %{id: "c", name: "Cara", connected: true}
      },
      player_order: ["a", "b", "c"],
      host_id: "a"
    }

    {:ok, %{state: state}} =
      Scribble.admit_member(admitted(), %{id: "c", name: "Cara"}, context())

    playing = %{
      state
      | phase: :playing,
        drawer_id: "a",
        word: "cat",
        correct_guesses: %{"b" => @now}
    }

    without_c = %{
      three_player_roster
      | players: Map.delete(three_player_roster.players, "c"),
        player_order: ["a", "b"]
    }

    {:ok, %{state: completed}} =
      Scribble.remove_member(playing, "c", %{name: "Cara"}, context(roster: without_c))

    assert completed.phase == :turn_reveal

    without_b = %{
      three_player_roster
      | players: Map.delete(three_player_roster.players, "b"),
        player_order: ["a", "c"]
    }

    {:ok, %{state: continuing}} =
      Scribble.remove_member(playing, "b", %{name: "Bob"}, context(roster: without_b))

    assert continuing.phase == :playing
  end

  test "a removed next drawer is skipped after reveal" do
    three_player_roster = %{
      players: %{
        "a" => %{id: "a", name: "Alice", connected: true},
        "b" => %{id: "b", name: "Bob", connected: true},
        "c" => %{id: "c", name: "Cara", connected: true}
      },
      player_order: ["a", "b", "c"],
      host_id: "a"
    }

    {:ok, %{state: state}} =
      Scribble.admit_member(admitted(), %{id: "c", name: "Cara"}, context())

    reveal = %{
      state
      | phase: :turn_reveal,
        drawer_id: "a",
        drawn_this_round: MapSet.new(["a"])
    }

    without_b = %{
      three_player_roster
      | players: Map.delete(three_player_roster.players, "b"),
        player_order: ["a", "c"]
    }

    {:ok, %{state: state}} =
      Scribble.remove_member(reveal, "b", %{name: "Bob"}, context(roster: without_b))

    {:ok, %{state: next}} = Scribble.timeout(state, :turn_reveal, context(roster: without_b))
    assert next.phase == :word_choice
    assert next.drawer_id == "c"
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

  test "a deterministic two-round game resets round state and retains drawing history" do
    words = ["cat", "dog", "bird", "fish"]

    game_context = %{
      context()
      | word_choices: fn _count, used, _custom, _defaults ->
          Enum.reject(words, &MapSet.member?(used, &1))
        end
    }

    {:ok, %{state: state}} = Scribble.start(admitted(), %{round_count: 2}, game_context)

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

    {%{state: state}, "cat"} = complete_turn(state, game_context, [start_event, draw_event])
    refute "cat" in state.word_choices

    {%{state: state}, "dog"} = complete_turn(state, game_context)
    assert state.phase == :word_choice
    assert state.current_round == 1
    assert state.drawn_this_round == MapSet.new()
    assert state.drawer_id == "a"
    refute "cat" in state.word_choices
    refute "dog" in state.word_choices

    {%{state: state}, "bird"} = complete_turn(state, game_context)

    {%{state: finished, status: {:finished, result}}, "fish"} =
      complete_turn(state, game_context)

    assert finished.phase == :game_ended
    assert length(result.drawings) == 4

    assert [
             %{
               drawer_id: "a",
               word: "cat",
               round_number: 1,
               ops: [["p", "#000000", 9, [10, 20, 20, 20]]]
             }
             | _
           ] = result.drawings
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
