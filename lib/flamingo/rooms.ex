defmodule Flamingo.Rooms do
  alias Flamingo.{RoomServer, RoomSupervisor}

  def create_room do
    RoomSupervisor.start_room()
  end

  def join(room_id, player_name) do
    with {:ok, player_id, _state} <- RoomServer.join(room_id, player_name),
         {:ok, snapshot} <- RoomServer.snapshot(room_id, player_id) do
      {:ok, player_id, snapshot}
    end
  end

  def rejoin(room_id, player_id) do
    with {:ok, _state} <- RoomServer.rejoin(room_id, player_id) do
      RoomServer.snapshot(room_id, player_id)
    end
  end

  def leave(room_id, player_id) do
    RoomServer.leave(room_id, player_id)
  end

  def snapshot(room_id, player_id) do
    RoomServer.snapshot(room_id, player_id)
  end

  def start_game(room_id, player_id, settings) do
    RoomServer.start_game(room_id, player_id, settings)
  end

  def select_word(room_id, player_id, word) do
    RoomServer.select_word(room_id, player_id, word)
  end

  def draw_event(room_id, player_id, event) do
    RoomServer.draw_event(room_id, player_id, event)
  end

  def guess(room_id, player_id, text) do
    RoomServer.guess(room_id, player_id, text)
  end

  def subscribe(room_id) do
    Phoenix.PubSub.subscribe(Flamingo.PubSub, "game:#{room_id}")
  end
end
