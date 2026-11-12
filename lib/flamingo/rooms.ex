defmodule Flamingo.Rooms do
  alias Flamingo.{RoomServer, RoomSupervisor}

  def create_room do
    RoomSupervisor.start_room()
  end

  @doc """
  Returns the saved lobby's running room, starting one if none is running.
  """
  def open_saved_lobby(name) do
    with :error <- RoomServer.saved_lobby_room(name) do
      case RoomSupervisor.start_room(nil, saved_lobby: name) do
        {:error, :saved_lobby_already_open} -> open_saved_lobby(name)
        result -> result
      end
    end
  end

  def save_lobby(room_id, name), do: RoomServer.save_lobby(room_id, name)

  def join(room_id, player_name, avatar \\ Flamingo.Avatar.default()) do
    RoomServer.join(room_id, player_name, avatar)
  end

  def connect(room_id, resume_token), do: RoomServer.connect(room_id, resume_token)
  def prepare_handoff(room_id), do: RoomServer.prepare_handoff(room_id)
  def return_to_lobby(room_id), do: RoomServer.return_to_lobby(room_id)

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
