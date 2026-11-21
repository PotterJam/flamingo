defmodule FlamingoWeb.GameModes do
  @moduledoc "The game modes offered in the lobby, in picker order. See `FlamingoWeb.GameMode`."

  alias FlamingoWeb.GameModes.{Classic, Roulette, Teams, Telephone}

  @modes [Classic, Roulette, Telephone, Teams]

  def all, do: @modes

  @doc "The mode a new lobby starts on."
  def default, do: hd(@modes)

  @doc """
  Finds a mode by id. A lobby where the host hasn't picked a mode yet has no
  id and shows the default; any other unknown id is a bug, so it raises.
  """
  def get(nil), do: default()

  def get(id),
    do:
      Enum.find(@modes, &(&1.id() == id)) ||
        raise(ArgumentError, "unknown game mode #{inspect(id)}")

  @doc "Finds a mode from a client param without creating atoms."
  def from_param(value), do: Enum.find(@modes, &(Atom.to_string(&1.id()) == value))
end
