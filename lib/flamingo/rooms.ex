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

  @doc """
  Subscribes the caller to `{:saved_lobby_presence, name, summary}` messages,
  sent whenever the players online in the saved lobby's room change.
  """
  def subscribe_saved_lobby_presence(name),
    do: Phoenix.PubSub.subscribe(Flamingo.PubSub, "saved_lobby_presence:" <> name)

  @doc "Returns who is online in the saved lobby's room, or `:error` if it isn't running."
  def saved_lobby_presence(name) do
    with {:ok, room_id} <- RoomServer.saved_lobby_room(name), do: RoomServer.presence(room_id)
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

  @doc """
  Starts a game of `mode` in the room's lobby, run by the `engine` game module.
  The room reports `mode` as the snapshot's `game_mode`.
  """
  def start_game(room_id, mode, engine, settings),
    do: RoomServer.start_game(room_id, mode, engine, settings)

  @doc "Records the host's mode choice and settings draft so every viewer and later lobby sees it."
  def update_lobby(room_id, mode, draft), do: RoomServer.update_lobby(room_id, mode, draft)

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
