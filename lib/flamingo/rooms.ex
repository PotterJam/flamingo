defmodule Flamingo.Rooms do
  alias Flamingo.{RoomServer, RoomSupervisor}

  def create_room do
    RoomSupervisor.start_room()
  end

  def join(room_id, player_name, avatar \\ Flamingo.Avatar.default()) do
    RoomServer.join(room_id, player_name, avatar)
  end

  def connect(room_id, resume_token), do: RoomServer.connect(room_id, resume_token)

  def leave(room_id) do
    RoomServer.leave(room_id)
  end

  def snapshot(room_id) do
    RoomServer.snapshot(room_id)
  end

  def start_game(room_id, settings) do
    RoomServer.start_game(room_id, settings)
  end

  def select_word(room_id, word) do
    RoomServer.select_word(room_id, word)
  end

  def draw_event(room_id, event) do
    RoomServer.draw_event(room_id, event)
  end

  def guess(room_id, text) do
    RoomServer.guess(room_id, text)
  end

  def command(room_id, command) do
    RoomServer.command(room_id, command)
  end
end
