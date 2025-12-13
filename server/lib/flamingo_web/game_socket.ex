defmodule FlamingoWeb.GameSocket do
  @behaviour Phoenix.Socket.Transport

  require Logger

  @impl true
  def child_spec(_opts), do: :ignore

  @impl true
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
  def init(state) do
    Logger.info("WebSocket connected: #{state.player_name} in room #{state.room_id}")
    {:ok, state}
  end

  @impl true
  def handle_in({text, _opts}, state) do
    Logger.debug("Received: #{text}")

    case Jason.decode(text) do
      {:ok, payload} ->
        handle_message(payload, state)

      {:error, _} ->
        Logger.warning("Failed to decode message: #{text}")
        {:ok, state}
    end
  end

  @impl true
  def handle_info(info, state) do
    Logger.debug("handle_info: #{inspect(info)}")
    {:ok, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("WebSocket terminated: #{inspect(reason)}, player: #{state.player_name}")
    :ok
  end

  defp handle_message(payload, state) do
    Logger.debug("Handling: #{inspect(payload)}")
    {:ok, state}
  end
end
