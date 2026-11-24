defmodule Flamingo.GameModes.Spellslingers.Crates do
  @moduledoc """
  Supply crates: dropping them, wizards collecting them, blasts destroying them. A health
  crate heals; a spell crate (`:mana`) holds ammo for one of the arsenal's limited spells.
  """

  alias Flamingo.GameModes.Spellslingers.{Catalog, Rng, Units}

  def maybe_drop_crate(state) do
    {chance, rng} = :rand.uniform_s(state.rng)
    state = %{state | rng: rng}
    if chance < state.tuning.crate_chance, do: drop_crate(state), else: state
  end

  def drop_crate(state) do
    case Units.standable_spots(state, 1) do
      spots when spots != [] and length(state.crates) < state.tuning.max_crates ->
        {{x, y}, rng} = Rng.pick(spots, state.rng)
        {kind, rng} = Rng.pick([:health, :mana, :mana], rng)
        {spell, rng} = Rng.pick(Map.keys(Catalog.starting_ammo()), rng)
        id = "c#{state.crate_count + 1}"
        crate = %{id: id, kind: :crate, type: kind, spell: spell, x: x, y: y}

        %{state | crates: [crate | state.crates], crate_count: state.crate_count + 1, rng: rng}
        |> Units.log(
          if kind == :health, do: "A health crate drops in!", else: "A supply crate drops in!"
        )

      _ ->
        state
    end
  end

  def collect_crates(state) do
    Enum.reduce(state.crates, state, fn crate, state ->
      taker =
        state.units
        |> Map.values()
        |> Enum.find(fn unit ->
          unit.kind == :wizard and Units.alive_unit?(unit) and abs(unit.x - crate.x) <= 2 and
            abs(unit.y - crate.y) <= 3
        end)

      case taker do
        nil ->
          state

        wizard ->
          state = %{state | crates: Enum.reject(state.crates, &(&1.id == crate.id))}

          case crate.type do
            :health ->
              state
              |> Units.put_unit(%{wizard | hp: min(wizard.hp + 30, wizard.max_hp)})
              |> Units.log("#{Units.player_name(state, wizard.id)} grabs a health crate (+30).")

            :mana ->
              spell = Map.get(crate, :spell, "embers")

              %{
                state
                | ammo:
                    Map.update(
                      state.ammo,
                      wizard.id,
                      %{spell => 1},
                      &Map.update(&1, spell, 1, fn n -> n + 1 end)
                    )
              }
              |> Units.log(
                "#{Units.player_name(state, wizard.id)} grabs a supply crate: +1 #{Catalog.spell(spell).name}!"
              )
          end
      end
    end)
  end

  def destroy_crates(state, x, y, radius) do
    %{
      state
      | crates:
          Enum.reject(state.crates, fn c ->
            (c.x + 0.5 - x) ** 2 + (c.y + 0.5 - y) ** 2 <= radius ** 2
          end)
    }
  end
end
