defmodule Flamingo.GameModes.Spellslingers.Minions do
  @moduledoc """
  Summoned minions: summoning them and their own moves at the start of their
  owner's turn.
  """

  alias Flamingo.GameModes.Spellslingers.{Catalog, Units}

  @doc "How many living minions `owner` commands."
  def count(state, owner) do
    Enum.count(state.units, fn {_, u} ->
      u.kind != :wizard and u.owner == owner and Units.alive_unit?(u)
    end)
  end

  @doc "Summons a minion for `actor` near (x, y), within the minion limit."
  def summon(state, actor, kind, x, y) do
    stats = Catalog.minion(kind)

    owned = count(state, actor)

    minion = %{
      id: "m#{state.minion_count + 1}",
      kind: kind,
      owner: actor,
      x: 0,
      y: 0,
      hp: stats.hp,
      max_hp: stats.hp,
      dead: false,
      ward: 0,
      float: 0
    }

    cond do
      owned >= state.tuning.max_minions ->
        Units.log(
          state,
          "…but #{Units.player_name(state, actor)} already commands #{state.tuning.max_minions} minions."
        )

      true ->
        case Units.free_spot(state, floor(x), floor(y), minion) do
          {:ok, minion} ->
            {minion, _} = Units.settle(state, minion)

            %{state | minion_count: state.minion_count + 1}
            |> Units.put_unit(minion)
            |> Units.log("A #{stats.name} appears for #{Units.player_name(state, actor)}!")

          :error ->
            Units.log(state, "…but the #{stats.name} found no room.")
        end
    end
  end

  def minions_act(state, owner) do
    state.units
    |> Map.values()
    |> Enum.filter(&(&1.kind != :wizard and &1.owner == owner and Units.alive_unit?(&1)))
    |> Enum.sort_by(& &1.id)
    |> Enum.reduce(state, &minion_act(&2, &1.id))
  end

  defp minion_act(state, id) do
    with %{} = minion <- state.units[id],
         true <- Units.alive_unit?(minion),
         %{} = target <- nearest_enemy(state, minion) do
      stats = Catalog.minion(minion.kind)
      dir = if target.x > minion.x, do: 1, else: -1
      minion = hop(state, minion, dir, min(stats.hop, max(abs(target.x - minion.x) - 1, 0)))
      state = Units.put_unit(state, minion)

      if abs(target.x - minion.x) <= stats.reach and abs(target.y - minion.y) <= stats.reach do
        state
        |> Units.damage(target.id, stats.bite, minion.owner)
        |> Units.log(
          "#{Units.player_name(state, minion.owner)}'s #{stats.name} bites #{Units.unit_name(state, target)} for #{stats.bite}!"
        )
      else
        state
      end
    else
      _ -> state
    end
  end

  defp hop(_state, minion, _dir, 0), do: minion

  defp hop(state, minion, dir, steps) do
    case Units.step(state, minion, dir) do
      {:ok, moved} ->
        {moved, _} = Units.settle(state, moved)
        if moved.y >= state.water_level, do: minion, else: hop(state, moved, dir, steps - 1)

      _ ->
        minion
    end
  end

  defp nearest_enemy(state, minion) do
    state.units
    |> Map.values()
    |> Enum.filter(&(Units.alive_unit?(&1) and &1.owner != minion.owner))
    |> Enum.min_by(&(abs(&1.x - minion.x) + abs(&1.y - minion.y)), fn -> nil end)
  end
end
