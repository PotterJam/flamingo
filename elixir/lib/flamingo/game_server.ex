defmodule Flamingo.GameServer do
  use GenServer

  defstruct [
    :room_id,
    :host_id,
    phase: :lobby,
    players: %{},
    player_order: [],
    round_count: 3,
    round_length: 30
  ]

  def start_link(room_id) do
    GenServer.start_link(__MODULE__, room_id, name: via(room_id))
  end

  def join(room_id, player_name) do
    GenServer.call(via(room_id), {:join, player_name})
  catch
    :exit, {:noproc, _} -> {:error, :not_found}
  end

  def rejoin(room_id, player_id) do
    GenServer.call(via(room_id), {:rejoin, player_id})
  catch
    :exit, {:noproc, _} -> {:error, :not_found}
  end

  def leave(room_id, player_id) do
    GenServer.call(via(room_id), {:leave, player_id})
  catch
    :exit, {:noproc, _} -> :ok
  end

  def start_game(room_id, player_id, settings) do
    GenServer.call(via(room_id), {:start_game, player_id, settings})
  end

  def get_state(room_id) do
    GenServer.call(via(room_id), :get_state)
  catch
    :exit, {:noproc, _} -> {:error, :not_found}
  end

  defp via(room_id) do
    {:via, Registry, {Flamingo.GameRegistry, room_id}}
  end

  @impl true
  def init(room_id) do
    {:ok, %__MODULE__{room_id: room_id}}
  end

  @impl true
  def handle_call({:join, player_name}, _from, state) do
    player_id = generate_player_id()
    player = %{id: player_id, name: player_name, score: 0}

    players = Map.put(state.players, player_id, player)
    player_order = state.player_order ++ [player_id]
    host_id = state.host_id || player_id

    new_state = %{state | players: players, player_order: player_order, host_id: host_id}

    broadcast(
      state.room_id,
      {:players_updated, new_state.players, new_state.player_order, new_state.host_id}
    )

    {:reply, {:ok, player_id, new_state}, new_state}
  end

  def handle_call({:rejoin, player_id}, _from, state) do
    if Map.has_key?(state.players, player_id) do
      {:reply, {:ok, state}, state}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call({:start_game, player_id, settings}, _from, state) do
    round_count = Map.get(settings, :round_count, state.round_count)
    round_length = Map.get(settings, :round_length, state.round_length)

    with :ok <- validate_host(state, player_id),
         :ok <- validate_player_count(state),
         :ok <- validate_round_count(round_count),
         :ok <- validate_round_length(round_length) do
      new_state = %{state | phase: :playing, round_count: round_count, round_length: round_length}
      broadcast(state.room_id, {:game_started, round_count, round_length})
      {:reply, :ok, new_state}
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({:leave, player_id}, _from, state) do
    if not Map.has_key?(state.players, player_id) do
      {:reply, :ok, state}
    else
      players = Map.delete(state.players, player_id)
      player_order = List.delete(state.player_order, player_id)

      host_id =
        if state.host_id == player_id,
          do: List.first(player_order),
          else: state.host_id

      new_state = %{state | players: players, player_order: player_order, host_id: host_id}

      broadcast(
        state.room_id,
        {:players_updated, new_state.players, new_state.player_order, new_state.host_id}
      )

      {:reply, :ok, new_state}
    end
  end

  defp validate_host(state, player_id) do
    if player_id == state.host_id, do: :ok, else: {:error, :not_host}
  end

  defp validate_player_count(state) do
    if map_size(state.players) >= 2, do: :ok, else: {:error, :not_enough_players}
  end

  defp validate_round_count(count) when count >= 1 and count <= 5, do: :ok
  defp validate_round_count(_), do: {:error, :invalid_round_count}

  defp validate_round_length(length) when length >= 30, do: :ok
  defp validate_round_length(_), do: {:error, :invalid_round_length}

  defp generate_player_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  defp broadcast(room_id, message) do
    Phoenix.PubSub.broadcast(Flamingo.PubSub, "game:#{room_id}", message)
  end
end
