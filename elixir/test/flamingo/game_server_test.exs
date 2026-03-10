defmodule Flamingo.GameServerTest do
  use ExUnit.Case, async: true

  alias Flamingo.GameServer
  alias Flamingo.GameSupervisor

  setup do
    room_id = "test-#{System.unique_integer([:positive])}"
    {:ok, ^room_id} = GameSupervisor.start_game(room_id)
    %{room_id: room_id}
  end

  test "first player becomes host", %{room_id: room_id} do
    {:ok, player_id, state} = GameServer.join(room_id, "Alice")
    assert state.host_id == player_id
    assert map_size(state.players) == 1
    assert state.player_order == [player_id]
  end

  test "second player does not change host", %{room_id: room_id} do
    {:ok, p1, _} = GameServer.join(room_id, "Alice")
    {:ok, p2, state} = GameServer.join(room_id, "Bob")
    assert state.host_id == p1
    assert state.player_order == [p1, p2]
  end

  test "leave reassigns host when host leaves", %{room_id: room_id} do
    {:ok, p1, _} = GameServer.join(room_id, "Alice")
    {:ok, p2, _} = GameServer.join(room_id, "Bob")

    :ok = GameServer.leave(room_id, p1)

    {:ok, state} = GameServer.get_state(room_id)
    assert state.host_id == p2
    assert state.player_order == [p2]
    refute Map.has_key?(state.players, p1)
  end

  test "leave does not change host when non-host leaves", %{room_id: room_id} do
    {:ok, p1, _} = GameServer.join(room_id, "Alice")
    {:ok, p2, _} = GameServer.join(room_id, "Bob")

    :ok = GameServer.leave(room_id, p2)

    {:ok, state} = GameServer.get_state(room_id)
    assert state.host_id == p1
  end

  test "join broadcasts players_updated", %{room_id: room_id} do
    Phoenix.PubSub.subscribe(Flamingo.PubSub, "game:#{room_id}")
    GameServer.join(room_id, "Alice")
    assert_receive {:players_updated, _players, _order, _host}
  end

  test "start_game fails if not host", %{room_id: room_id} do
    {:ok, _p1, _} = GameServer.join(room_id, "Alice")
    {:ok, p2, _} = GameServer.join(room_id, "Bob")
    assert {:error, :not_host} = GameServer.start_game(room_id, p2, %{})
  end

  test "start_game fails with fewer than 2 players", %{room_id: room_id} do
    {:ok, p1, _} = GameServer.join(room_id, "Alice")
    assert {:error, :not_enough_players} = GameServer.start_game(room_id, p1, %{})
  end

  test "start_game fails with invalid round_count", %{room_id: room_id} do
    {:ok, p1, _} = GameServer.join(room_id, "Alice")
    {:ok, _p2, _} = GameServer.join(room_id, "Bob")
    assert {:error, :invalid_round_count} = GameServer.start_game(room_id, p1, %{round_count: 0})
    assert {:error, :invalid_round_count} = GameServer.start_game(room_id, p1, %{round_count: 6})
  end

  test "start_game fails with invalid round_length", %{room_id: room_id} do
    {:ok, p1, _} = GameServer.join(room_id, "Alice")
    {:ok, _p2, _} = GameServer.join(room_id, "Bob")
    assert {:error, :invalid_round_length} = GameServer.start_game(room_id, p1, %{round_length: 10})
  end

  test "start_game succeeds and broadcasts", %{room_id: room_id} do
    Phoenix.PubSub.subscribe(Flamingo.PubSub, "game:#{room_id}")
    {:ok, p1, _} = GameServer.join(room_id, "Alice")
    {:ok, _p2, _} = GameServer.join(room_id, "Bob")

    assert :ok = GameServer.start_game(room_id, p1, %{round_count: 2, round_length: 45})
    assert_receive {:game_started, 2, 45}

    {:ok, state} = GameServer.get_state(room_id)
    assert state.phase == :playing
  end

  test "join returns not_found for nonexistent room" do
    assert {:error, :not_found} = GameServer.join("no-such-room", "Alice")
  end

  test "rejoin succeeds for existing player", %{room_id: room_id} do
    {:ok, player_id, _} = GameServer.join(room_id, "Alice")
    {:ok, state} = GameServer.rejoin(room_id, player_id)
    assert Map.has_key?(state.players, player_id)
  end

  test "rejoin fails for unknown player", %{room_id: room_id} do
    assert {:error, :not_found} = GameServer.rejoin(room_id, "nonexistent")
  end
end
