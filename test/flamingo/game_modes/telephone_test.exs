defmodule Flamingo.GameModes.TelephoneTest do
  use ExUnit.Case, async: true

  alias Flamingo.GameModes.Telephone

  defp roster(order) do
    names = %{"a" => "Alice", "b" => "Bob", "c" => "Cara", "s" => "Sam"}

    %{
      players:
        Map.new(
          order,
          &{&1, %{id: &1, name: Map.get(names, &1, String.upcase(&1)), connected: true}}
        ),
      player_order: order,
      host_id: "a"
    }
  end

  defp context(roster, actor \\ "a", options \\ []) do
    %{
      roster: roster,
      actor_id: actor,
      now: ~U[2026-01-01 00:00:00Z],
      word_choices: fn count, _used, _custom, _defaults ->
        Enum.take(["cat", "dog", "bird", "fish", "horse", "frog"], count)
      end,
      select_candidate: Keyword.get(options, :select_candidate, &List.first/1)
    }
  end

  defp started(order \\ ["a", "b", "c"], opts \\ []) do
    game_roster = roster(order)

    state =
      Enum.reduce(order, Telephone.new(), fn id, state ->
        {:ok, %{state: state}} =
          Telephone.admit_member(state, game_roster.players[id], context(game_roster))

        state
      end)

    {:ok, %{state: state}} =
      Telephone.start(state, %{turn_length: 15}, context(game_roster, "a", opts))

    state =
      if Keyword.get(opts, :choose_prompts, true) do
        Enum.reduce(order, state, fn id, state ->
          prompt = state.prompt_choices |> Map.fetch!(id) |> List.first()

          {:ok, %{state: state}} =
            Telephone.command(state, id, {:select_prompt, prompt}, context(game_roster, id))

          state
        end)
      else
        state
      end

    {state, game_roster}
  end

  defp submit_everyone(state, game_roster) do
    Enum.reduce(game_roster.player_order, state, fn id, state ->
      result =
        if state.phase == :telephone_draw,
          do: Telephone.command(state, id, :submit_drawing, context(game_roster)),
          else: Telephone.command(state, id, {:submit_guess, "guess #{id}"}, context(game_roster))

      {:ok, %{state: state}} = result
      state
    end)
  end

  test "players privately choose the prompts that start their chains" do
    {state, game_roster} = started(["a", "b"], choose_prompts: false)

    assert state.phase == :telephone_prompt
    assert Telephone.view(state, "a", game_roster).prompt_choices == ["cat", "dog", "bird"]
    assert Telephone.view(state, "b", game_roster).prompt_choices == ["dog", "bird", "cat"]

    {:ok, %{state: state}} =
      Telephone.command(state, "a", {:select_prompt, "bird"}, context(game_roster, "a"))

    assert state.phase == :telephone_prompt
    assert MapSet.member?(state.submitted, "a")

    assert {:error, :invalid_prompt} =
             Telephone.command(
               state,
               "b",
               {:select_prompt, "not offered"},
               context(game_roster, "b")
             )

    {:ok, %{state: state}} =
      Telephone.command(state, "b", {:select_prompt, "dog"}, context(game_roster, "b"))

    assert state.phase == :telephone_draw
    assert Enum.map(state.chains, &hd(&1.entries).value) == ["bird", "dog"]
  end

  test "rotates chains, alternates phases, and keeps drawings viewer-private" do
    {state, game_roster} = started()
    assert Telephone.view(state, "a", game_roster).assignment.chain_id == "telephone-chain-0"

    event = %{
      "event_type" => "start",
      "x" => 1,
      "y" => 2,
      "color" => "#000000",
      "line_width" => 4
    }

    {:ok, %{state: state, drawing_delta: delta, drawing_scope: :actor}} =
      Telephone.command(state, "a", {:draw, event}, context(game_roster))

    assert delta == %{actor_id: "a", event: event}
    assert Telephone.view(state, "a", game_roster).assignment.current_drawing == [event]
    assert Telephone.view(state, "b", game_roster).assignment.current_drawing == []

    state = submit_everyone(state, game_roster)
    assert state.phase == :telephone_guess
    assert Telephone.view(state, "a", game_roster).assignment.chain_id == "telephone-chain-2"
    assert Telephone.view(state, "a", game_roster).assignment.source.type == :drawing

    state = submit_everyone(state, game_roster)
    assert state.phase == :telephone_draw
    assert Telephone.view(state, "a", game_roster).assignment.chain_id == "telephone-chain-1"
    assert Telephone.view(state, "a", game_roster).assignment.source.value == "guess c"
  end

  test "randomizes the pass order while every player contributes to every chain once" do
    pick_middle = &Enum.at(&1, div(length(&1), 2))
    order = ["a", "b", "c", "d", "e"]
    {state, game_roster} = started(order, select_candidate: pick_middle)

    assert state.step_offsets == [0, 3, 2, 4, 1]

    {assignments, reveal} =
      Enum.map_reduce(1..length(order), state, fn _step, state ->
        round_assignments =
          Map.new(order, fn player_id ->
            assignment = Telephone.view(state, player_id, game_roster).assignment
            {player_id, assignment.chain_id}
          end)

        {round_assignments, submit_everyone(state, game_roster)}
      end)

    chain_ids = MapSet.new(Enum.map(reveal.chains, & &1.id))

    assert Enum.all?(assignments, fn round ->
             round |> Map.values() |> MapSet.new() == chain_ids
           end)

    assert Enum.all?(order, fn player_id ->
             assignments
             |> Enum.map(&Map.fetch!(&1, player_id))
             |> MapSet.new() == chain_ids
           end)

    assert Enum.all?(reveal.chains, fn chain ->
             chain.entries
             |> tl()
             |> Enum.map(& &1.player_id)
             |> MapSet.new() == MapSet.new(order)
           end)
  end

  test "timeout records placeholders and a disconnect completes the online set" do
    {state, game_roster} = started(["a", "b"])
    {:ok, %{state: state}} = Telephone.command(state, "a", :submit_drawing, context(game_roster))

    offline_roster = put_in(game_roster.players["b"].connected, false)

    {:ok, %{state: state}} =
      Telephone.connection_changed(state, "b", :offline, context(offline_roster))

    assert state.phase == :telephone_guess
    assert Enum.at(state.chains, 1).entries |> List.last() |> Map.fetch!(:value) == nil

    {:ok, %{state: reveal}} = Telephone.timeout(state, :telephone_step, context(offline_roster))
    assert reveal.phase == :telephone_reveal
    assert Enum.all?(reveal.chains, &(length(&1.entries) == 3))
  end

  test "timeout and disconnect preserve drawings that already reached the server" do
    {state, game_roster} = started(["a", "b"])

    event = %{
      "event_type" => "start",
      "x" => 10,
      "y" => 20,
      "color" => "#000000",
      "line_width" => 9
    }

    {:ok, %{state: state}} =
      Telephone.command(state, "b", {:draw, event}, context(game_roster, "b"))

    {:ok, %{state: state}} =
      Telephone.command(state, "a", :submit_drawing, context(game_roster, "a"))

    offline_roster = put_in(game_roster.players["b"].connected, false)

    {:ok, %{state: disconnected}} =
      Telephone.connection_changed(state, "b", :offline, context(offline_roster))

    assert disconnected.phase == :telephone_guess

    assert Telephone.view(disconnected, "a", offline_roster).assignment.source.value == [
             ["p", "#000000", 9, [10, 20]]
           ]

    {state, game_roster} = started(["a", "b"])

    {:ok, %{state: state}} =
      Telephone.command(state, "b", {:draw, event}, context(game_roster, "b"))

    {:ok, %{state: timed_out}} =
      Telephone.timeout(state, :telephone_step, context(game_roster))

    assert timed_out.phase == :telephone_guess

    assert Telephone.view(timed_out, "a", game_roster).assignment.source.value == [
             ["p", "#000000", 9, [10, 20]]
           ]

    assert Enum.at(timed_out.chains, 0).entries |> List.last() |> Map.fetch!(:value) == nil
  end

  test "a transient fully-offline room does not skip a step" do
    {state, game_roster} = started(["a", "b"])

    offline_roster =
      update_in(game_roster.players, fn players ->
        Map.new(players, fn {id, player} -> {id, %{player | connected: false}} end)
      end)

    {:ok, %{state: unchanged}} =
      Telephone.connection_changed(state, "a", :offline, context(offline_roster))

    assert unchanged.phase == :telephone_draw
    assert unchanged.current_step == 0
    assert Enum.all?(unchanged.chains, &(length(&1.entries) == 1))
  end

  test "rejects restarts, stale commands, and malformed drawing events" do
    {state, game_roster} = started(["a", "b"])

    assert {:error, :game_in_progress} =
             Telephone.start(state, %{turn_length: 15}, context(game_roster))

    assert {:error, :invalid_command} =
             Telephone.command(state, "a", {:guess, "stale"}, context(game_roster))

    assert {:error, :invalid_draw_event} =
             Telephone.command(state, "a", {:draw, "not a map"}, context(game_roster))

    assert :ignored =
             Telephone.command(
               state,
               "a",
               {:draw, %{"event_type" => "start", "x" => 1}},
               context(game_roster)
             )
  end

  test "players admitted after start spectate and captured snapshots survive removal" do
    {state, game_roster} = started(["a", "b"])
    expanded = %{roster(["a", "b", "s"]) | host_id: "a"}

    {:ok, %{state: state}} =
      Telephone.admit_member(state, expanded.players["s"], context(expanded))

    assert state.participants["s"] == :spectator
    assert Telephone.view(state, "s", expanded).assignment == nil

    assert :ignored ==
             Telephone.command(state, "s", {:draw, %{"event_type" => "clear"}}, context(expanded))

    reveal = %{state | phase: :telephone_reveal, reveal_chain_index: 0, reveal_entry_index: 0}
    prompt = hd(hd(reveal.chains).entries)

    assert {:error, :spectator} =
             Telephone.command(
               reveal,
               "s",
               {:vote, :best_save, prompt.id},
               context(expanded)
             )

    removed_roster = %{
      game_roster
      | players: Map.delete(game_roster.players, "b"),
        player_order: ["a"]
    }

    {:ok, %{state: state}} =
      Telephone.remove_member(state, "b", %{name: "Bob"}, context(removed_roster))

    assert state.player_order == ["a", "b"]
    assert state.players["b"].name == "Bob"
  end

  test "a new match promotes spectators and a removed host transfers reveal control" do
    {state, _game_roster} = started(["a", "b"])
    expanded = %{roster(["a", "b", "s"]) | host_id: "a"}

    {:ok, %{state: state}} =
      Telephone.admit_member(state, expanded.players["s"], context(expanded))

    assert state.participants["s"] == :spectator

    ended = %{state | phase: :game_ended}
    {:ok, %{state: restarted}} = Telephone.start(ended, %{turn_length: 15}, context(expanded))
    assert restarted.player_order == ["a", "b", "s"]
    assert restarted.participants["s"] == :active

    restarted =
      Enum.reduce(restarted.player_order, restarted, fn id, state ->
        prompt = state.prompt_choices |> Map.fetch!(id) |> List.first()

        {:ok, %{state: state}} =
          Telephone.command(state, id, {:select_prompt, prompt}, context(expanded, id))

        state
      end)

    new_roster = %{expanded | players: Map.delete(expanded.players, "a"), host_id: "b"}

    {:ok, %{state: migrated}} =
      Telephone.remove_member(
        %{
          restarted
          | phase: :telephone_reveal,
            reveal_chain_index: 0,
            reveal_entry_index: 0
        },
        "a",
        %{name: "Alice"},
        context(new_roster)
      )

    assert migrated.host_id == "b"
    assert {:ok, _result} = Telephone.command(migrated, "b", :advance_reveal, context(new_roster))
  end

  test "a new host can continue reveal after every original player is removed" do
    {state, game_roster} = started(["a", "b"])
    reveal = state |> submit_everyone(game_roster) |> submit_everyone(game_roster)

    bob_roster = %{
      game_roster
      | players: Map.delete(game_roster.players, "a"),
        player_order: ["b"],
        host_id: "b"
    }

    {:ok, %{state: reveal}} =
      Telephone.remove_member(reveal, "a", %{name: "Alice"}, context(bob_roster))

    empty_roster = %{players: %{}, player_order: [], host_id: nil}

    {:ok, %{state: reveal}} =
      Telephone.remove_member(reveal, "b", %{name: "Bob"}, context(empty_roster))

    assert reveal.host_id == nil

    sam_roster = %{roster(["s"]) | host_id: "s"}

    {:ok, %{state: reveal}} =
      Telephone.admit_member(reveal, sam_roster.players["s"], context(sam_roster, "s"))

    assert reveal.host_id == "s"

    assert {:ok, _result} =
             Telephone.command(reveal, "s", :advance_reveal, context(sam_roster, "s"))
  end

  test "host paces leak-free reveal, votes can change, and awards finish deterministically" do
    {state, game_roster} = started(["a", "b"])
    state = state |> submit_everyone(game_roster) |> submit_everyone(game_roster)
    assert state.phase == :telephone_reveal

    view = Telephone.view(state, "b", game_roster)
    assert length(view.reveal.chain.entries) == 1
    refute inspect(view.reveal) =~ "guess b"

    assert {:error, :not_host} =
             Telephone.command(state, "b", :advance_reveal, context(game_roster, "b"))

    future_drawing = Enum.at(state.chains, 0).entries |> Enum.at(1)

    assert {:error, :entry_not_revealed} =
             Telephone.command(
               state,
               "b",
               {:vote, :worst_drawing, future_drawing.id},
               context(game_roster)
             )

    {:ok, %{state: state}} = Telephone.command(state, "a", :advance_reveal, context(game_roster))

    {:ok, %{state: state}} =
      Telephone.command(
        state,
        "b",
        {:vote, :worst_drawing, future_drawing.id},
        context(game_roster)
      )

    prompt = hd(hd(state.chains).entries)

    assert {:error, :invalid_entry} =
             Telephone.command(
               state,
               "b",
               {:vote, :worst_drawing, prompt.id},
               context(game_roster)
             )

    assert {:error, :invalid_entry} =
             Telephone.command(
               state,
               "b",
               {:vote, :best_save, prompt.id},
               context(game_roster)
             )

    {:ok, %{state: state}} =
      Telephone.command(state, "b", {:vote, :best_save, future_drawing.id}, context(game_roster))

    assert Telephone.view(state, "b", game_roster).vote_counts.best_save == %{
             future_drawing.id => 1
           }

    {:ok, %{state: state}} = Telephone.command(state, "a", :advance_reveal, context(game_roster))
    {:ok, %{state: state}} = Telephone.command(state, "a", :advance_reveal, context(game_roster))
    {:ok, %{state: state}} = Telephone.command(state, "a", :advance_reveal, context(game_roster))
    {:ok, %{state: state}} = Telephone.command(state, "a", :advance_reveal, context(game_roster))
    {:ok, result} = Telephone.command(state, "a", :advance_reveal, context(game_roster))

    assert result.state.phase == :game_ended
    assert {:finished, result.state.final_result} == result.status
    assert result.state.awards.worst_drawing.player_id == "a"
    assert result.state.awards.best_save.entry.id == future_drawing.id
  end
end
