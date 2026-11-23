defmodule Flamingo.GameModes.Spellslingers.Zones do
  @moduledoc """
  Spells that outlast their cast: napalm on the ground, a volcano, a thunderhead,
  a rising tide, and dragons. They act at the start of their owner's turn, all as one
  cast that clients replay before the turn begins, and wear off after a few turns.
  """

  alias Flamingo.GameModes.Spellslingers.{Fx, Spells, Units}

  @doc "Runs `owner`'s lasting spells. Returns whether anything happened."
  def tick(state, owner) do
    zones = Enum.filter(state.zones, &(&1.owner == owner))

    dragons =
      state.units
      |> Map.values()
      |> Enum.filter(&(&1.kind == :dragon and &1.owner == owner and Units.alive_unit?(&1)))
      |> Enum.sort_by(& &1.id)

    if zones == [] and dragons == [] do
      {false, state}
    else
      state =
        Spells.run(state, owner, "zones", nil, fn fx ->
          fx = Enum.reduce(zones, fx, &act/2)
          fx = Enum.reduce(dragons, fx, &Spells.dragon_breath(&2, &1))
          %{fx | state: wear_off(fx.state, owner)}
        end)

      {true, state}
    end
  end

  defp act(%{kind: :napalm} = zone, fx), do: Spells.burn(fx, zone)
  defp act(%{kind: :thunderhead} = zone, fx), do: Spells.strike(fx, zone, Fx.next_start(fx))

  defp act(%{kind: :volcano} = zone, fx),
    do:
      Spells.erupt(
        %{fx | state: Units.log(fx.state, "The volcano erupts!"), shake: true},
        zone,
        Fx.next_start(fx)
      )

  defp act(%{kind: :tide}, fx), do: %{fx | state: Spells.rise_sea(fx.state), shake: true}

  defp wear_off(state, owner) do
    zones =
      state.zones
      |> Enum.map(&if(&1.owner == owner, do: %{&1 | turns: &1.turns - 1}, else: &1))
      |> Enum.filter(&(&1.turns > 0))

    %{state | zones: zones}
  end
end
