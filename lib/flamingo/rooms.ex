defmodule Flamingo.Rooms do
  alias Flamingo.{RoomServer, RoomSupervisor}

  def create_room do
    RoomSupervisor.start_room()
  end

  def join(room_id, player_name) do
    RoomServer.join(room_id, player_name)
  end

  def rejoin(room_id, resume_token), do: RoomServer.rejoin(room_id, resume_token)

  def leave(room_id, resume_token) do
    RoomServer.leave(room_id, resume_token)
  end

  def snapshot(room_id, resume_token) do
    RoomServer.snapshot(room_id, resume_token)
  end

  def start_game(room_id, resume_token, settings) do
    RoomServer.start_game(room_id, resume_token, settings)
  end

  def select_word(room_id, resume_token, word) do
    RoomServer.select_word(room_id, resume_token, word)
  end

  def draw_event(room_id, resume_token, event) do
    RoomServer.draw_event(room_id, resume_token, event)
  end

  def guess(room_id, resume_token, text) do
    RoomServer.guess(room_id, resume_token, text)
  end

  def subscribe(room_id) do
    Phoenix.PubSub.subscribe(Flamingo.PubSub, "game:#{room_id}")
  end
end
