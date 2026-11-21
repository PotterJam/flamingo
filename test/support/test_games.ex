defmodule Flamingo.TestGames do
  @moduledoc false

  @doc """
  Starts a game as the calling player. `settings.game_mode` names the lobby mode
  (Classic by default); the rest go to its engine unchanged.
  """
  def start_game(room_id, settings) do
    {id, settings} = Map.pop(settings, :game_mode, :classic)
    mode = FlamingoWeb.GameModes.from_param(to_string(id)) || raise "unknown game mode #{id}"
    Flamingo.Rooms.start_game(room_id, mode.id(), mode.engine(), settings)
  end
end
