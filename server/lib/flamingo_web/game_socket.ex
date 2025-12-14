defmodule FlamingoWeb.GameSocket do
  @behaviour Phoenix.Socket.Transport

  require Logger

  alias Flamingo.Game.{GameServer, Message}

  @type connect_state :: %{room_id: String.t(), player_name: String.t()}

  @type state :: %{room_id: String.t(), player_name: String.t(), player_id: String.t()}

  @impl true
  def child_spec(_opts), do: :ignore

  @impl true
  @spec connect(map()) :: {:ok, connect_state()} | :error
  def connect(%{params: params}) do
    room_id = Map.get(params, "roomId")
    player_name = Map.get(params, "playerName")

    Logger.info("WebSocket connect - room: #{room_id}, player: #{player_name}")

    case {room_id, player_name} do
      {nil, _} ->
        Logger.warning("WebSocket rejected: no roomId param")
        :error

      {_, nil} ->
        Logger.warning("WebSocket rejected: no playerName param")
        :error

      {room_id, player_name} ->
        {:ok, %{room_id: room_id, player_name: player_name}}
    end
  end

  @impl true
  @spec init(connect_state()) :: {:ok, state()} | {:stop, term()}
  def init(state) do
    case GameServer.register_player(state.room_id, state.player_name, self()) do
      {:ok, player_id} ->
        Logger.info("Player #{state.player_name} (#{player_id}) joined room #{state.room_id}")
        {:ok, Map.put(state, :player_id, player_id)}

      {:error, reason} ->
        Logger.warning("Failed to register player: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_in({text, _opts}, state) do
    case Jason.decode(text) do
      {:ok, payload} ->
        handle_message(payload, state)

      {:error, _} ->
        Logger.warning("Failed to decode message: #{text}")
        {:ok, state}
    end
  end

  @impl true
  def handle_info({:game_message, type, payload}, state) do
    json = Message.encode(type, payload)
    {:push, {:text, json}, state}
  end

  def handle_info(info, state) do
    Logger.warning("GameSocket received unexpected message: #{inspect(info)}")
    {:ok, state}
  end

  @impl true
  @spec terminate(term(), state()) :: :ok
  def terminate(_reason, state) do
    if state[:player_id] do
      Logger.info(
        "Player #{state.player_name} (#{state.player_id}) terminated connection to #{state.room_id}"
      )

      GameServer.unregister_player(state.room_id, state.player_id)
    end

    :ok
  end

  defp handle_message(%{"type" => "startGame", "payload" => payload}, state) do
    config = %{
      round_count: payload["roundCount"],
      round_duration: payload["roundLength"]
    }

    GameServer.dispatch(state.room_id, {:start_game, state.player_id, config})
    {:ok, state}
  end

  defp handle_message(%{"type" => _type, "payload" => _payload}, state) do
    {:ok, state}
  end

  defp handle_message(_payload, state) do
    {:ok, state}
  end
end
