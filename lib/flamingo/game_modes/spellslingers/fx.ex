defmodule Flamingo.GameModes.Spellslingers.Fx do
  @moduledoc """
  What one cast does, gathered while its effects run: the game state they
  change, the flights and beams clients replay, and the knockback each unit
  will take once the effects finish.
  """

  defstruct [:state, :target, segments: [], beams: [], auras: [], impulses: %{}, shake: false]

  def new(state, target), do: %__MODULE__{state: state, target: target}

  @doc "Adds a velocity to the knockback a unit will take."
  def push(fx, id, {vx, vy}) do
    %{fx | impulses: Map.update(fx.impulses, id, {vx, vy}, fn {ax, ay} -> {ax + vx, ay + vy} end)}
  end

  @doc "Knocks a unit away along (dx, dy), and a little upwards."
  def add_impulse(fx, id, dx, dy, distance, magnitude) do
    {nx, ny} = if distance < 0.5, do: {0.0, -1.0}, else: {dx / distance, dy / distance}
    push(fx, id, {nx * magnitude, ny * magnitude - magnitude * 0.55})
  end
end
