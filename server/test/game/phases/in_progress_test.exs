defmodule Flamingo.Game.Phases.InProgressTest do
  use ExUnit.Case

  alias Flamingo.Game.{Context, Player}
  alias Flamingo.Game.Phases.InProgress

  describe "init/1 (word selection)" do
    test "initializes with word selection sub-phase" do
      ctx =
        Context.new()
        |> Context.add_player(Player.new("Alice", "p1"))
        |> Context.add_player(Player.new("Bob", "p2"))
        |> Map.put(:round_duration, 60)
        |> Map.put(:total_rounds, 3)

      {state, new_ctx, effects} = InProgress.init(ctx)

      assert state.sub_phase == :word_selection
      assert state.drawer_id in ["p1", "p2"]
      assert length(state.word_choices) == 3
      assert state.yet_to_draw |> length() == 1
      assert new_ctx.current_round == 1
      assert new_ctx.current_drawer_id == state.drawer_id
    end

    test "sends turn_setup to drawer with word choices" do
      ctx =
        Context.new()
        |> Context.add_player(Player.new("Alice", "p1"))
        |> Context.add_player(Player.new("Bob", "p2"))
        |> Map.put(:round_duration, 60)
        |> Map.put(:total_rounds, 3)

      {state, _ctx, effects} = InProgress.init(ctx)

      drawer_effect =
        Enum.find(effects, fn
          {:send_to, id, :turn_setup, _} when id == state.drawer_id -> true
          _ -> false
        end)

      assert {:send_to, _, :turn_setup, payload} = drawer_effect
      assert payload.word_choices == state.word_choices
      assert length(payload.word_choices) == 3
      assert payload.game_phase == "RoundSetup"
    end

    test "sends turn_setup to non-drawers without word choices" do
      ctx =
        Context.new()
        |> Context.add_player(Player.new("Alice", "p1"))
        |> Context.add_player(Player.new("Bob", "p2"))
        |> Map.put(:round_duration, 60)
        |> Map.put(:total_rounds, 3)

      {state, _ctx, effects} = InProgress.init(ctx)

      broadcast_effect =
        Enum.find(effects, fn
          {:broadcast_except, id, :turn_setup, _} when id == state.drawer_id -> true
          _ -> false
        end)

      assert {:broadcast_except, _, :turn_setup, payload} = broadcast_effect
      assert payload.word_choices == []
    end

    test "sets 10 second timeout" do
      ctx =
        Context.new()
        |> Context.add_player(Player.new("Alice", "p1"))
        |> Context.add_player(Player.new("Bob", "p2"))
        |> Map.put(:round_duration, 60)
        |> Map.put(:total_rounds, 3)

      {_state, _ctx, effects} = InProgress.init(ctx)

      timeout_effect = Enum.find(effects, fn e -> match?({:set_timeout, _}, e) end)
      assert {:set_timeout, 10_000} = timeout_effect
    end

    test "broadcasts system chat about drawer choosing" do
      ctx =
        Context.new()
        |> Context.add_player(Player.new("Alice", "p1"))
        |> Context.add_player(Player.new("Bob", "p2"))
        |> Map.put(:round_duration, 60)
        |> Map.put(:total_rounds, 3)

      {state, _ctx, effects} = InProgress.init(ctx)
      drawer_name = if state.drawer_id == "p1", do: "Alice", else: "Bob"

      chat_effect =
        Enum.find(effects, fn
          {:broadcast_all, :chat, _} -> true
          _ -> false
        end)

      assert {:broadcast_all, :chat, payload} = chat_effect
      assert payload.is_system == true
      assert String.contains?(payload.message, drawer_name)
      assert String.contains?(payload.message, "choosing a word")
    end
  end

  describe "handle_action/4 {:select_word, ...}" do
    setup do
      ctx =
        Context.new()
        |> Context.add_player(Player.new("Alice", "p1"))
        |> Context.add_player(Player.new("Bob", "p2"))
        |> Map.put(:round_duration, 60)
        |> Map.put(:total_rounds, 3)

      {state, ctx, _effects} = InProgress.init(ctx)
      %{state: state, ctx: ctx}
    end

    test "drawer can select a valid word", %{state: state, ctx: ctx} do
      word = List.first(state.word_choices)

      {:continue, new_state, _ctx, effects} =
        InProgress.handle_action(state, ctx, {:select_word, {state.drawer_id, word}}, 0)

      assert new_state.sub_phase == :drawing
      assert new_state.word == word
      assert new_state.word_choices == nil
      assert Enum.any?(effects, fn e -> match?({:send_to, _, :turn_start, _}, e) end)
      assert Enum.any?(effects, fn e -> match?({:broadcast_except, _, :turn_start, _}, e) end)
    end

    test "drawer receives word in turn_start", %{state: state, ctx: ctx} do
      word = List.first(state.word_choices)

      {:continue, _new_state, _ctx, effects} =
        InProgress.handle_action(state, ctx, {:select_word, {state.drawer_id, word}}, 0)

      drawer_effect =
        Enum.find(effects, fn
          {:send_to, id, :turn_start, _} when id == state.drawer_id -> true
          _ -> false
        end)

      assert {:send_to, _, :turn_start, payload} = drawer_effect
      assert payload.word == word
      assert payload.game_phase == "RoundInProgress"
    end

    test "non-drawer cannot select word", %{state: state, ctx: ctx} do
      word = List.first(state.word_choices)
      non_drawer_id = Enum.find(["p1", "p2"], &(&1 != state.drawer_id))

      assert {:error, :not_drawer} =
               InProgress.handle_action(state, ctx, {:select_word, {non_drawer_id, word}}, 0)
    end

    test "cannot select invalid word", %{state: state, ctx: ctx} do
      assert {:error, :invalid_word} =
               InProgress.handle_action(
                 state,
                 ctx,
                 {:select_word, {state.drawer_id, "not_a_choice"}},
                 0
               )
    end
  end

  describe "handle_timeout/2" do
    test "auto-selects random word on timeout" do
      ctx =
        Context.new()
        |> Context.add_player(Player.new("Alice", "p1"))
        |> Context.add_player(Player.new("Bob", "p2"))
        |> Map.put(:round_duration, 60)
        |> Map.put(:total_rounds, 3)

      {state, ctx, _effects} = InProgress.init(ctx)

      {:continue, new_state, _ctx, effects} = InProgress.handle_timeout(state, ctx)

      assert new_state.sub_phase == :drawing
      assert new_state.word in state.word_choices
      assert Enum.any?(effects, fn e -> match?({:send_to, _, :turn_start, _}, e) end)
    end
  end

  describe "generate_word_outline/2" do
    test "generates blanks for letters" do
      assert InProgress.generate_word_outline("cat") == "_ _ _"
    end

    test "preserves spaces" do
      assert InProgress.generate_word_outline("hot dog") == "_ _ _   _ _ _"
    end

    test "reveals specified indices" do
      assert InProgress.generate_word_outline("cat", [0, 2]) == "c _ t"
    end
  end
end
