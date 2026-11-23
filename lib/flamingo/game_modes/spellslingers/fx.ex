defmodule Flamingo.GameModes.Spellslingers.Fx do
  @moduledoc """
  What one cast does, gathered while its effects run: the game state they
  change, the flights and beams clients replay, the hits clients reveal as each
  one lands, and the knockback each unit will take once the effects finish.

  `at` is the step of the cast's flight timeline the effects have reached, so a
  hit records the moment clients should show it.
  """

  alias Flamingo.GameModes.Spellslingers.Units

  defstruct [
    :state,
    :target,
    at: 0,
    segments: [],
    beams: [],
    auras: [],
    hits: [],
    impulses: %{},
    shake: false
  ]

  def new(state, target), do: %__MODULE__{state: state, target: target}

  @doc "Damages a unit and records the hit, with the health it leaves, at the current step."
  def hit(fx, id, amount, source) do
    state = Units.damage(fx.state, id, amount, source)
    unit = state.units[id]
    hit = %{id: id, at: fx.at, hp: unit.hp, ward: Map.get(unit, :ward, 0)}
    %{fx | state: state, hits: [hit | fx.hits]}
  end

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
