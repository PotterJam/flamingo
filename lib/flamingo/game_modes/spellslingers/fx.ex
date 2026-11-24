defmodule Flamingo.GameModes.Spellslingers.Fx do
  @moduledoc """
  What one cast does, gathered while its effects run: the game state they
  change, the flights clients replay, the hits clients reveal as each
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
    auras: [],
    hits: [],
    impulses: %{},
    shake: false,
    grand: false
  ]

  def new(state, target), do: %__MODULE__{state: state, target: target}

  @doc """
  Damages a unit and records the hit at the current step. Effects can record a hit
  that lands earlier than one already recorded (an ember with a shorter flight), so
  each hit keeps the damage it dealt and `reveal/2` works out the health clients show.
  """
  def hit(fx, id, amount, source) do
    before = fx.state.units[id].hp
    state = Units.damage(fx.state, id, amount, source)
    hit = %{id: id, at: fx.at, dealt: before - state.units[id].hp}
    %{fx | state: state, hits: [hit | fx.hits]}
  end

  @doc """
  The hits in the order clients reveal them, as their flights land, each with the
  health it leaves, so a wizard's health only ever goes down during a cast.
  """
  def reveal(fx, before) do
    fx.hits
    |> Enum.reverse()
    |> Enum.sort_by(& &1.at)
    |> Enum.map_reduce(%{}, fn hit, health ->
      hp = Map.get_lazy(health, hit.id, fn -> before.units[hit.id].hp end) - hit.dealt
      {%{id: hit.id, at: hit.at, hp: hp}, Map.put(health, hit.id, hp)}
    end)
    |> elem(0)
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
