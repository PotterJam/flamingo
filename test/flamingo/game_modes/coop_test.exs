defmodule Flamingo.GameModes.CoopTest do
  use ExUnit.Case, async: true

  alias Flamingo.GameModes.Coop

  defp game(count \\ 5, rounds \\ 1) do
    ids = Enum.map(1..count, &Integer.to_string/1)

    context = %{
      roster: %{
        players: Map.new(ids, &{&1, %{id: &1, name: "Player #{&1}", connected: true}}),
        player_order: ids,
        host_id: "1"
      },
      actor_id: "1",
      now: ~U[2026-01-01 00:00:00Z],
      word_choices: fn _, _, _ -> ["cat", "dog", "butterfly"] end,
      select_candidate: &List.first/1
    }

    {:ok, %{state: state}} =
      Coop.start(Coop.new(), %{round_count: rounds, turn_length: 30}, context)

    {state, context}
  end

  defp command(state, id, command, context) do
    {:ok, %{state: next}} = Coop.command(state, id, command, context)
    next
  end

  test "pairs connected players with one trio for odd counts" do
    for count <- 2..9 do
      {state, context} = game(count)
      view = Coop.view(state, "1", context.roster)
      sizes = view.teams |> Map.values() |> Enum.frequencies() |> Map.values() |> Enum.sort()

      assert sizes ==
               List.duplicate(2, div(count, 2) - rem(count, 2)) ++
                 if(rem(count, 2) == 1, do: [3], else: [])

      assert map_size(view.teams) == count
      refute view.spin_enabled
    end
  end

  defp texts(state, viewer, context),
    do: Enum.map(Coop.view(state, viewer, context.roster).feed, & &1.text)

  test "the picking team chooses one word every team draws, on private canvases with shared chat" do
    {state, context} = game()
    assert Coop.view(state, "1", context.roster).word_choices == ["cat", "dog", "butterfly"]
    assert Coop.view(state, "3", context.roster).word_choices == []
    assert Coop.view(state, "3", context.roster).word_picker_id == "1"
    assert Coop.command(state, "3", {:select_word, "cat"}, context) == {:error, :not_drawer}
    assert Coop.command(state, "2", {:select_word, "cat"}, context) == {:error, :not_drawer}

    state = command(state, "1", {:select_word, "dog"}, context)
    assert Coop.view(state, "4", context.roster).phase == :playing
    assert Coop.view(state, "3", context.roster).word == "dog"
    assert Coop.view(state, "4", context.roster).word == "___"

    event = %{"event_type" => "start", "x" => 12, "y" => 25}
    state = command(state, "1", {:draw, event}, context)
    assert Coop.view(state, "2", context.roster).current_drawing == [event]
    assert Coop.view(state, "4", context.roster).current_drawing == []

    state = command(state, "4", {:guess, "cow"}, context)
    state = command(state, "4", {:guess, "dot"}, context)
    assert "Player 4: cow" in texts(state, "2", context)
    assert "dot was close!" in texts(state, "4", context)
    refute Enum.any?(texts(state, "2", context), &(&1 =~ "dot"))

    state = command(state, "4", {:vote_drawing, :up}, context)
    assert "Player 4 liked the drawing" in texts(state, "5", context)
    assert "Player 4 liked Team 2's drawing" in texts(state, "2", context)

    state = command(state, "2", {:guess, "dog"}, context)
    assert MapSet.member?(Coop.view(state, "4", context.roster).correct_guesses, "2")
    assert Coop.view(state, "4", context.roster).word == "___"
    assert "Player 2 guessed the word" in texts(state, "4", context)
    refute Enum.any?(texts(state, "4", context), &(&1 =~ "dog"))
    assert "You guessed it" in texts(state, "2", context)
  end

  test "either trio guesser finishes once; first team gets 400 and later teams decay with time" do
    for guesser <- ["4", "5"] do
      {state, context} = game()
      state = command(state, "1", {:select_word, "cat"}, context)
      state = command(state, guesser, {:guess, "cat"}, context)
      assert Coop.view(state, "3", context.roster).team_finished?
      refute Coop.view(state, "4", context.roster).can_guess?
      refute Coop.view(state, "5", context.roster).can_guess?
      assert Coop.view(state, "1", context.roster).phase == :playing
      assert Coop.view(state, "2", context.roster).word == "___"
      assert Coop.view(state, "1", context.roster).team_scores == %{1 => 0, 2 => 400}
      assert {:error, :team_finished} = Coop.command(state, "5", {:guess, "cat"}, context)
      assert :ignored = Coop.command(state, "3", {:draw, %{"event_type" => "clear"}}, context)
      later = %{context | now: DateTime.add(context.now, 15, :second)}
      state = command(state, "2", {:guess, "cat"}, later)
      assert Coop.view(state, "2", context.roster).team_scores == %{1 => 190, 2 => 400}
      assert Coop.view(state, "2", context.roster).phase == :turn_reveal
      assert "The word was cat" in texts(state, "4", context)

      {:ok, %{state: state, status: {:finished, result}}} =
        Coop.timeout(state, :turn_reveal, later)

      assert Coop.view(state, "1", context.roster).team_scores == %{1 => 190, 2 => 400}
      assert Enum.map(result.drawings, &{&1.drawer_id, &1.word}) == [{"1", "cat"}, {"3", "cat"}]
    end
  end

  test "the reveal shows everyone, including teamless watchers, every team's drawing best first" do
    {state, context} = game(5)
    watcher = %{id: "6", name: "Late", connected: true}

    context = %{
      context
      | roster: %{
          context.roster
          | players: Map.put(context.roster.players, "6", watcher),
            player_order: context.roster.player_order ++ ["6"]
        }
    }

    {:ok, %{state: state}} = Coop.admit_member(state, watcher, context)
    state = command(state, "1", {:select_word, "dog"}, context)

    state =
      command(state, "1", {:draw, %{"event_type" => "start", "x" => 10, "y" => 20}}, context)

    state =
      command(
        state,
        "1",
        {:draw,
         %{"event_type" => "draw", "start_x" => 10, "start_y" => 20, "end_x" => 90, "end_y" => 60}},
        context
      )

    state = command(state, "4", {:guess, "dog"}, context)
    assert Coop.view(state, "6", context.roster).team_reveals == []
    {:ok, %{state: state, timers: timers}} = Coop.timeout(state, :playing, context)
    assert {:schedule_phase_timeout, :turn_reveal, 15_000} in timers

    assert [
             %{team: 2, drawer_id: "3", word: "dog", gain: 400},
             %{team: 1, drawer_id: "1", word: "dog", gain: 0, ops: [_ | _]}
           ] = Coop.view(state, "6", context.roster).team_reveals

    assert Coop.view(state, "2", context.roster).team_reveals ==
             Coop.view(state, "6", context.roster).team_reveals

    # Anyone but the drawer rates any team's drawing; votes reach the final results.
    assert {:error, :drawer_cannot_vote} =
             Coop.command(state, "1", {:vote_drawing, 1, :up}, context)

    state = command(state, "4", {:vote_drawing, 1, :up}, context)
    state = command(state, "6", {:vote_drawing, 1, :down}, context)
    state = command(state, "6", {:vote_drawing, 1, :up}, context)

    assert [_, %{team: 1, vote: :up}] =
             Coop.view(state, "6", context.roster).team_reveals

    assert "Player 4 liked Team 1's drawing" in texts(state, "5", context)
    assert "Player 4 liked your team's drawing" in texts(state, "2", context)
    assert "Late disliked Team 1's drawing" in texts(state, "6", context)

    {:ok, %{status: {:finished, result}}} = Coop.timeout(state, :turn_reveal, context)
    assert result.players["1"].thumbs_up == 2
  end

  test "timeouts pick the word for everyone, hints reveal for every team and the picking team rotates" do
    {state, context} = game(5, 3)
    {:ok, %{state: state}} = Coop.timeout(state, :word_choice, context)
    assert Coop.view(state, "1", context.roster).word == "cat"
    assert Coop.view(state, "3", context.roster).word == "cat"
    later = %{context | now: DateTime.add(context.now, 19, :second)}
    {:ok, %{state: state}} = Coop.timeout(state, :reveal_hint, later)
    assert length(Coop.view(state, "2", context.roster).revealed_indices) == 1
    assert length(Coop.view(state, "4", context.roster).revealed_indices) == 1
    state = command(state, "2", {:guess, "cat"}, later)
    {:ok, %{state: state}} = Coop.timeout(state, :playing, later)
    assert Coop.view(state, "1", context.roster).team_scores == %{1 => 400, 2 => 0}
    {:ok, %{state: state}} = Coop.timeout(state, :turn_reveal, later)
    assert Coop.view(state, "1", context.roster).drawer_id == "2"
    assert Coop.view(state, "5", context.roster).drawer_id == "4"
    assert Coop.view(state, "5", context.roster).current_round == 1
    assert Coop.view(state, "1", context.roster).word_picker_id == "4"
    assert Coop.view(state, "2", context.roster).word_choices == []
    assert Coop.view(state, "4", context.roster).word_choices == ["cat", "dog", "butterfly"]
    assert Coop.command(state, "2", {:select_word, "dog"}, context) == {:error, :not_drawer}
    state = command(state, "4", {:select_word, "dog"}, context)
    assert Coop.view(state, "2", context.roster).word == "dog"
  end

  test "late joiners spectate without private words; a removed picker hands the choice to a timeout" do
    {state, context} = game()
    newcomer = %{id: "6", name: "Late", connected: true}

    context = %{
      context
      | roster: %{
          context.roster
          | players: Map.put(context.roster.players, "6", newcomer),
            player_order: context.roster.player_order ++ ["6"]
        }
    }

    {:ok, %{state: state}} = Coop.admit_member(state, newcomer, context)
    assert Coop.view(state, "6", context.roster).participation == :spectator
    assert Coop.view(state, "6", context.roster).word == nil
    assert Coop.view(state, "6", context.roster).current_drawing == []
    roster = context.roster

    removed = %{
      context
      | roster: %{
          roster
          | players: Map.delete(roster.players, "1"),
            player_order: List.delete(roster.player_order, "1")
        }
    }

    {:ok, %{state: state}} = Coop.remove_member(state, "1", %{id: "1", name: "Player 1"}, removed)
    assert Coop.view(state, "3", removed.roster).phase == :playing
    assert Coop.view(state, "3", removed.roster).word == "cat"
    assert Coop.view(state, "2", removed.roster).participation == :spectator
    assert "Player 1 left" in texts(state, "4", removed)
    {:ok, %{state: state}} = Coop.command(state, "5", {:guess, "cat"}, removed)
    assert Coop.view(state, "4", removed.roster).team_scores == %{1 => 0, 2 => 400}
    assert Coop.view(state, "4", removed.roster).phase == :turn_reveal
  end
end
