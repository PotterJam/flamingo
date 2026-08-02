defmodule Flamingo.Games do
  alias Flamingo.{GameServer, GameSupervisor}

  def create_room do
    GameSupervisor.start_game()
  end

  def join(room_id, player_name), do: join(room_id, player_name, Flamingo.Avatar.default())

  def join(room_id, player_name, avatar) do
    GameServer.join(room_id, player_name, avatar)
  end

  def rejoin(room_id, player_id) do
    GameServer.rejoin(room_id, player_id)
  end

  def leave(room_id, player_id) do
    GameServer.leave(room_id, player_id)
  end

  def get_state(room_id) do
    GameServer.get_state(room_id)
  end

  def start_game(room_id, player_id, settings) do
    GameServer.start_game(room_id, player_id, settings)
  end

  def select_word(room_id, player_id, word) do
    GameServer.select_word(room_id, player_id, word)
  end

  def draw_event(room_id, player_id, event) do
    GameServer.draw_event(room_id, player_id, event)
  end

  def guess(room_id, player_id, text) do
    GameServer.guess(room_id, player_id, text)
  end

  def subscribe(room_id) do
    Phoenix.PubSub.subscribe(Flamingo.PubSub, "game:#{room_id}")
  end
end
