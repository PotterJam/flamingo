defmodule FlamingoWeb.GameModes do
  @moduledoc "The game modes offered in the lobby, in picker order. See `FlamingoWeb.GameMode`."

  alias FlamingoWeb.GameModes.{Classic, Roulette, Teams, Telephone}

  @modes [Classic, Roulette, Telephone, Teams]

  def all, do: @modes

  @doc "The mode a new lobby starts on."
  def default, do: hd(@modes)

  @doc "Finds a mode by id, falling back to the default for unknown or unset ids."
  def get(id), do: Enum.find(@modes, default(), &(&1.id() == id))

  @doc "Finds a mode from a client param without creating atoms."
  def from_param(value), do: Enum.find(@modes, &(Atom.to_string(&1.id()) == value))
end
