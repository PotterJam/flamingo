defmodule Flamingo.GameTest do
  use ExUnit.Case

  describe "join action" do
    test "adds first player to empty game state" do
      initial_state = %Flamingo.Game{word: "test"}
      player_id = "player-1"
      player_name = "Alice"

      {mutations, updated_state} =
        Flamingo.Game.run(initial_state, {:joined, {player_id, player_name}}, 0)

      assert length(updated_state.players) == 1
      player = Flamingo.Game.Player.new(player_name, player_id)
      assert mutations == [{:players_update, {:new, player}}]
      assert length(updated_state.pending_drawing) == 1
    end

    test "second player joins" do
      first_player = Flamingo.Game.Player.new("Alice", "player-1")

      second_player_id = "player-2"
      second_player_name = "Bob"

      {_, initial_state} =
        Flamingo.Game.run(
          Flamingo.Game.new(["test"]),
          {:joined, {first_player.id, first_player.name}},
          0
        )

      {mutations, updated_state} =
        Flamingo.Game.run(initial_state, {:joined, {second_player_id, second_player_name}}, 0)

      assert length(updated_state.players) == 2

      assert [
               {:players_update,
                {:new, %Flamingo.Game.Player{id: ^second_player_id, name: ^second_player_name}}}
             ] = mutations

      assert length(updated_state.pending_drawing) == 2
    end
  end

  describe "start action" do
    test "selects a random drawer and word choices" do
      player1 = Flamingo.Game.Player.new("Alice", "player-1")
      player2 = Flamingo.Game.Player.new("Bob", "player-2")
      word_list = ["cat", "dog", "bird", "fish", "tree"]

      initial_state = %Flamingo.Game{
        word: nil,
        players: [player1, player2],
        pending_drawing: [player1, player2],
        word_list: word_list
      }

      {mutations, updated_state} = Flamingo.Game.run(initial_state, {:start}, 0)

      assert [{:word_choices, {%Flamingo.Game.Player{} = drawer, [_, _, _]}}] = mutations
      assert drawer in [player1, player2]
      assert drawer not in updated_state.pending_drawing
      assert length(updated_state.pending_drawing) == 1
    end
  end

  describe "choose word action" do
    test "sets the chosen word and removes it from word_list" do
      player1 = Flamingo.Game.Player.new("Alice", "player-1")
      word_list = ["cat", "dog", "bird", "fish", "tree"]
      chosen_word = "cat"

      initial_state = %Flamingo.Game{
        word: nil,
        players: [player1],
        word_list: word_list
      }

      {mutations, updated_state} =
        Flamingo.Game.run(initial_state, {:choose_word, chosen_word}, 0)

      assert updated_state.word == chosen_word
      assert chosen_word not in updated_state.word_list
      assert length(updated_state.word_list) == 4
      assert mutations == [{:start_round}]
    end
  end
end
