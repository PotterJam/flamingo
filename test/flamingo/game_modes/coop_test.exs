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

  test "same choices, independent words, a shared clock and private canvases and guesses" do
    {state, context} = game()
    assert Coop.view(state, "1", context.roster).word_choices == ["cat", "dog", "butterfly"]
    assert Coop.view(state, "3", context.roster).word_choices == ["cat", "dog", "butterfly"]
    state = command(state, "1", {:select_word, "cat"}, context)
    assert Coop.view(state, "1", context.roster).phase == :word_choice

    assert Coop.command(state, "1", {:draw, %{"event_type" => "clear"}}, context) ==
             {:error, :not_playing}

    state = command(state, "3", {:select_word, "dog"}, context)
    assert Coop.view(state, "2", context.roster).phase == :playing
    assert Coop.view(state, "4", context.roster).phase == :playing
    event = %{"event_type" => "start", "x" => 12, "y" => 25}
    state = command(state, "1", {:draw, event}, context)
    assert Coop.view(state, "2", context.roster).current_drawing == [event]
    assert Coop.view(state, "4", context.roster).current_drawing == []
    state = command(state, "4", {:guess, "cat"}, context)
    assert Coop.view(state, "4", context.roster).word == "___"
    assert Coop.view(state, "4", context.roster).feed |> Enum.any?(&(&1.kind == :guess))
    refute Coop.view(state, "2", context.roster).feed |> Enum.any?(&(&1.kind == :guess))
  end

  test "either trio guesser finishes once; first team gets 400 and later teams decay with time" do
    for guesser <- ["4", "5"] do
      {state, context} = game()
      state = command(state, "1", {:select_word, "cat"}, context)
      state = command(state, "3", {:select_word, "dog"}, context)
      state = command(state, guesser, {:guess, "dog"}, context)
      assert Coop.view(state, "3", context.roster).team_finished?
      refute Coop.view(state, "4", context.roster).can_guess?
      refute Coop.view(state, "5", context.roster).can_guess?
      assert Coop.view(state, "1", context.roster).phase == :playing
      assert Coop.view(state, "1", context.roster).team_scores == %{1 => 0, 2 => 400}
      assert {:error, :team_finished} = Coop.command(state, "5", {:guess, "dog"}, context)
      assert :ignored = Coop.command(state, "3", {:draw, %{"event_type" => "clear"}}, context)
      later = %{context | now: DateTime.add(context.now, 15, :second)}
      state = command(state, "2", {:guess, "cat"}, later)
      assert Coop.view(state, "2", context.roster).team_scores == %{1 => 190, 2 => 400}
      assert Coop.view(state, "2", context.roster).phase == :turn_reveal

      {:ok, %{state: state, status: {:finished, result}}} =
        Coop.timeout(state, :turn_reveal, later)

      assert Coop.view(state, "1", context.roster).team_scores == %{1 => 190, 2 => 400}
      assert Enum.map(result.drawings, &{&1.drawer_id, &1.word}) == [{"1", "cat"}, {"3", "dog"}]
    end
  end

  test "timeouts auto-select missing choices, reveal hints independently and rotate drawers" do
    {state, context} = game(5, 3)
    state = command(state, "1", {:select_word, "butterfly"}, context)
    {:ok, %{state: state}} = Coop.timeout(state, :word_choice, context)
    assert Coop.view(state, "1", context.roster).word == "butterfly"
    assert Coop.view(state, "3", context.roster).word == "cat"
    later = %{context | now: DateTime.add(context.now, 14, :second)}
    {:ok, %{state: state}} = Coop.timeout(state, :reveal_hint, later)
    assert length(Coop.view(state, "2", context.roster).revealed_indices) > 0
    assert Coop.view(state, "4", context.roster).revealed_indices == []
    state = command(state, "2", {:guess, "butterfly"}, later)
    {:ok, %{state: state}} = Coop.timeout(state, :playing, later)
    assert Coop.view(state, "1", context.roster).team_scores == %{1 => 400, 2 => 0}
    {:ok, %{state: state}} = Coop.timeout(state, :turn_reveal, later)
    assert Coop.view(state, "1", context.roster).drawer_id == "2"
    assert Coop.view(state, "5", context.roster).drawer_id == "4"
    assert Coop.view(state, "5", context.roster).current_round == 1
  end

  test "late joiners spectate without private words; removed drawers only end their own team" do
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
    assert Coop.view(state, "3", removed.roster).phase == :word_choice
    state = command(state, "3", {:select_word, "dog"}, removed)
    assert Coop.view(state, "2", removed.roster).team_finished?
    assert Coop.view(state, "4", removed.roster).can_guess?
    state = command(state, "5", {:guess, "dog"}, removed)
    assert Coop.view(state, "4", removed.roster).team_scores == %{1 => 0, 2 => 400}
  end
end
