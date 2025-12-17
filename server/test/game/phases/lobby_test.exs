defmodule Flamingo.Game.Phases.LobbyTest do
  use ExUnit.Case

  alias Flamingo.Game.{Context, Player}
  alias Flamingo.Game.Phases.Lobby

  describe "player_joined" do
    test "first player becomes host" do
      {state, ctx, []} = Lobby.init(Context.new())

      {:continue, _state, new_ctx, effects} =
        Lobby.handle_action(state, ctx, {:player_joined, {"p1", "Alice"}}, 0)

      assert new_ctx.host_id == "p1"
      assert length(new_ctx.players) == 1

      assert [
               {:send_to, "p1", :game_info, game_info},
               {:broadcast_all, :player_update, players}
             ] = effects

      assert game_info.is_host == true
      assert game_info.host_id == "p1"
      assert length(players) == 1
    end

    test "second player does not become host" do
      ctx =
        Context.new()
        |> Context.add_player(Player.new("Alice", "p1"))

      {state, ctx, []} = Lobby.init(ctx)

      {:continue, _state, new_ctx, effects} =
        Lobby.handle_action(state, ctx, {:player_joined, {"p2", "Bob"}}, 0)

      assert new_ctx.host_id == "p1"
      assert length(new_ctx.players) == 2

      assert [
               {:send_to, "p2", :game_info, game_info},
               {:broadcast_all, :player_update, players}
             ] = effects

      assert game_info.is_host == false
      assert length(players) == 2
    end
  end

  describe "player_left" do
    test "removing non-host player keeps host" do
      ctx =
        Context.new()
        |> Context.add_player(Player.new("Alice", "p1"))
        |> Context.add_player(Player.new("Bob", "p2"))

      {state, ctx, []} = Lobby.init(ctx)

      {:continue, _state, new_ctx, effects} =
        Lobby.handle_action(state, ctx, {:player_left, "p2"}, 0)

      assert new_ctx.host_id == "p1"
      assert length(new_ctx.players) == 1

      assert [{:broadcast_all, :player_update, players}] = effects
      assert length(players) == 1
    end

    test "removing host assigns new host" do
      ctx =
        Context.new()
        |> Context.add_player(Player.new("Alice", "p1"))
        |> Context.add_player(Player.new("Bob", "p2"))

      {state, ctx, []} = Lobby.init(ctx)

      {:continue, _state, new_ctx, _effects} =
        Lobby.handle_action(state, ctx, {:player_left, "p1"}, 0)

      assert new_ctx.host_id == "p2"
      assert length(new_ctx.players) == 1
    end

    test "removing last player clears host" do
      ctx =
        Context.new()
        |> Context.add_player(Player.new("Alice", "p1"))

      {state, ctx, []} = Lobby.init(ctx)

      {:continue, _state, new_ctx, _effects} =
        Lobby.handle_action(state, ctx, {:player_left, "p1"}, 0)

      assert new_ctx.host_id == nil
      assert new_ctx.players == []
    end
  end

  describe "start_game" do
    test "host can start game with enough players" do
      ctx =
        Context.new()
        |> Context.add_player(Player.new("Alice", "p1"))
        |> Context.add_player(Player.new("Bob", "p2"))

      {state, ctx, []} = Lobby.init(ctx)
      config = %{round_count: 3, round_duration: 60_000}

      {:transition, Flamingo.Game.Phases.InProgress, _phase_state, new_ctx, []} =
        Lobby.handle_action(state, ctx, {:start_game, "p1", config}, 0)

      assert new_ctx.total_rounds == 3
      assert new_ctx.round_duration == 60_000
    end

    test "non-host cannot start game" do
      ctx =
        Context.new()
        |> Context.add_player(Player.new("Alice", "p1"))
        |> Context.add_player(Player.new("Bob", "p2"))

      {state, ctx, []} = Lobby.init(ctx)
      config = %{round_count: 3, round_duration: 60_000}

      assert {:error, :not_host} =
               Lobby.handle_action(state, ctx, {:start_game, "p2", config}, 0)
    end

    test "cannot start with fewer than 2 players" do
      ctx =
        Context.new()
        |> Context.add_player(Player.new("Alice", "p1"))

      {state, ctx, []} = Lobby.init(ctx)
      config = %{round_count: 3, round_duration: 60_000}

      assert {:error, :not_enough_players} =
               Lobby.handle_action(state, ctx, {:start_game, "p1", config}, 0)
    end
  end

  describe "unknown action" do
    test "returns error for unknown action" do
      {state, ctx, []} = Lobby.init(Context.new())

      assert {:error, :unknown_action} =
               Lobby.handle_action(state, ctx, {:something_random}, 0)
    end
  end
end
