defmodule Flamingo.GameTest do
  use ExUnit.Case

  describe "first player joins" do
    test "adds first player to empty game state" do
      initial_state = %Flamingo.Game{word: "test", players: [], revealed: []}
      player_id = "player-1"
      player_name = "Alice"

      {mutations, updated_state} =
        Flamingo.Game.run(initial_state, {:joined, {player_id, player_name}}, 0)

      assert length(updated_state.players) == 1

      assert mutations == [{:players_update, {:new, {player_id, player_name}}}]
    end

    test "second player joins" do
      first_player = %Flamingo.Game.Player{id: "player-1", name: "Alice", score: 0}
      initial_state = %Flamingo.Game{word: "test", players: [first_player], revealed: []}

      second_player_id = "player-2"
      second_player_name = "Bob"

      {mutations, updated_state} =
        Flamingo.Game.run(initial_state, {:joined, {second_player_id, second_player_name}}, 0)

      assert length(updated_state.players) == 2

      assert mutations == [{:players_update, {:new, {second_player_id, second_player_name}}}]
    end
  end
end
