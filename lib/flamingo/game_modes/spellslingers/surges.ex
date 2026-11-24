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
    |> Units.log("Rockfall! Boulders come down from above!")
    |> Spells.run(nil, "surge", nil, fn fx ->
      Enum.reduce(0..3, %{fx | shake: true}, fn i, fx ->
        {r, rng} = :rand.uniform_s(fx.state.rng)
        fx = %{fx | state: %{fx.state | rng: rng}}
        Spells.meteor(fx, 10 + r * (@width - 20), i * 6, "surge")
      end)
    end)
  end

  def surge_before(state, :mana) do
    # Every limited spell gets one more charge.
    ammo =
      Map.new(state.ammo, fn {id, spells} ->
        {id, Map.new(spells, fn {s, n} -> {s, n + 1} end)}
      end)

    %{state | ammo: ammo}
    |> Units.log("Lucky seam! Everyone finds one more of everything.")
  end

  def surge_before(state, :crates) do
    state
    |> Units.log("Supplies come down the shaft.")
    |> Crates.drop_crate()
    |> Crates.drop_crate()
  end

  def surge_before(state, _), do: state

  def surge_after(state, :gale) do
    {sign, rng} = Rng.pick([-1, 1], state.rng)

    %{state | wind: sign * 10, rng: rng}
    |> Units.log("A howling draught sweeps the mine.")
  end

  def surge_after(state, _), do: state
end
