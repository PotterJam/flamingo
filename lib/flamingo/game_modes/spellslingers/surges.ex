defmodule Flamingo.GameModes.Spellslingers.Surges do
  @moduledoc """
  Wild magic: from turn 4 a turn may roll a surge, applied before the next
  wizard's turn (meteors, a mana storm, crates) or after it starts (a gale).
  """

  use Flamingo.GameModes.Spellslingers.Rules

  alias Flamingo.GameModes.Spellslingers.{Crates, Rng, Spells, Units}

  def roll_surge(state) do
    {chance, rng} = :rand.uniform_s(state.rng)
    state = %{state | rng: rng}

    if state.turn_number >= 4 and chance < state.tuning.surge_chance do
      {kind, rng} = Rng.pick([:meteors, :gale, :mana, :crates], state.rng)
      {kind, %{state | rng: rng}}
    else
      {nil, state}
    end
  end

  def surge_before(state, :meteors) do
    state
    |> Units.log("Wild magic! Meteors fall from the sky!")
    |> Spells.run(nil, "surge", nil, fn fx ->
      Enum.reduce(0..3, %{fx | shake: true}, fn i, fx ->
        {r, rng} = :rand.uniform_s(fx.state.rng)
        fx = %{fx | state: %{fx.state | rng: rng}}
        Spells.fx_with_meteor(fx, 10 + r * (@width - 20), i * 6, "surge")
      end)
    end)
  end

  def surge_before(state, :mana) do
    %{state | cooldowns: Map.new(state.cooldowns, fn {id, _} -> {id, %{}} end)}
    |> Units.log("Wild magic! A mana storm recharges every spell.")
  end

  def surge_before(state, :crates) do
    state
    |> Units.log("Wild magic! Supplies rain from the sky.")
    |> Crates.drop_crate()
    |> Crates.drop_crate()
  end

  def surge_before(state, _), do: state

  def surge_after(state, :gale) do
    {sign, rng} = Rng.pick([-1, 1], state.rng)

    %{state | wind: sign * 10, rng: rng}
    |> Units.log("Wild magic! A howling gale sweeps the arena.")
  end

  def surge_after(state, _), do: state
end
