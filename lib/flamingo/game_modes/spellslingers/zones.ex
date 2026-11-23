defmodule Flamingo.GameModes.Spellslingers.Zones do
  @moduledoc """
  Spells that outlast their cast: napalm on the ground, a volcano, a thunderhead,
  a rising tide, blizzards, clockwork bombs, a Lich's hunger, rot, dragons and turrets. They act at the start of their owner's turn, all as one
  cast that clients replay before the turn begins, and wear off after a few turns.
  """

  alias Flamingo.GameModes.Spellslingers.{Catalog, Fx, Spells, Units}

  @doc "Runs `owner`'s lasting spells. Returns whether anything happened."
  def tick(state, owner) do
    zones = Enum.filter(state.zones, &(&1.owner == owner))

    mine =
      state.units
      |> Map.values()
      |> Enum.filter(&(&1.owner == owner and Units.alive_unit?(&1)))
      |> Enum.sort_by(& &1.id)

    # Frozen shooters skip a turn; their owner's turn end thaws them (see Minions).
    shooters =
      Enum.filter(mine, &(&1.kind in [:dragon, :turret] and Map.get(&1, :frozen, 0) == 0))

    rotting = Enum.filter(mine, &(Map.get(&1, :decay, 0) > 0))

    if zones == [] and shooters == [] and rotting == [] do
      {false, state}
    else
      state =
        Spells.run(state, owner, "zones", nil, fn fx ->
          fx = Enum.reduce(rotting, fx, &Spells.rot(&2, &1))
          fx = Enum.reduce(zones, fx, &act/2)
          fx = Enum.reduce(shooters, fx, &shoot/2)
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

  defp act(%{kind: :blizzard} = zone, fx),
    do: Spells.snow(fx, zone, Catalog.spell("blizzard").damage)

  defp act(%{kind: :bomb} = bomb, fx), do: Spells.tick_bomb(fx, bomb)

  defp act(%{kind: :lich, owner: owner}, fx) do
    victims =
      fx.state.units
      |> Map.values()
      |> Enum.filter(&(Units.alive_unit?(&1) and &1.owner != owner))
      |> Enum.sort_by(& &1.id)

    Spells.drain(fx, owner, victims, Catalog.spell("lich").damage)
  end

  # A shooter killed earlier in this same tick does nothing.
  defp shoot(unit, fx) do
    case fx.state.units[unit.id] do
      %{} = unit -> if Units.alive_unit?(unit), do: Spells.minion_shot(fx, unit), else: fx
      nil -> fx
    end
  end

  defp wear_off(state, owner) do
    zones =
      state.zones
      |> Enum.map(&if(&1.owner == owner, do: %{&1 | turns: &1.turns - 1}, else: &1))
      |> Enum.filter(&(&1.turns > 0))

    %{state | zones: zones}
  end
end
