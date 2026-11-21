defmodule Flamingo.GameModes.Spellslingers.Units do
  @moduledoc false

  use Flamingo.GameModes.Spellslingers.Rules

  alias Flamingo.GameModes.Spellslingers.{Catalog, Rng, Terrain}

  def maybe_drop_crate(state) do
    {chance, rng} = :rand.uniform_s(state.rng)
    state = %{state | rng: rng}
    if chance < 0.35, do: drop_crate(state), else: state
  end

  def drop_crate(state) do
    case standable_spots(state, 1) do
      spots when spots != [] and length(state.crates) < @max_crates ->
        {{x, y}, rng} = Rng.pick(spots, state.rng)
        {kind, rng} = Rng.pick([:health, :health, :mana], rng)
        id = "c#{state.crate_count + 1}"
        crate = %{id: id, kind: :crate, type: kind, x: x, y: y}

        %{state | crates: [crate | state.crates], crate_count: state.crate_count + 1, rng: rng}
        |> log(if kind == :health, do: "A health crate drops in!", else: "A mana crate drops in!")

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
          unit.kind == :wizard and alive_unit?(unit) and abs(unit.x - crate.x) <= 2 and
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
              |> put_unit(%{wizard | hp: min(wizard.hp + 30, wizard.max_hp)})
              |> log("#{player_name(state, wizard.id)} grabs a health crate (+30).")

            :mana ->
              %{state | cooldowns: Map.put(state.cooldowns, wizard.id, %{})}
              |> log("#{player_name(state, wizard.id)} grabs a mana crate: spells recharged!")
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

  def damage(state, id, amount, source) do
    case state.units[id] do
      nil ->
        state

      unit ->
        ward = Map.get(unit, :ward, 0)
        absorbed = min(ward, amount)
        dealt = min(amount - absorbed, unit.hp)

        state =
          put_unit(
            state,
            unit |> Map.put(:ward, ward - absorbed) |> Map.put(:hp, unit.hp - dealt)
          )

        if source && source != unit.owner && Map.has_key?(state.damage_dealt, source),
          do: %{state | damage_dealt: Map.update!(state.damage_dealt, source, &(&1 + dealt))},
          else: state
    end
  end

  def place_wizards(state) do
    count = length(state.turn_order)
    spots = standable_spots(state, 3)

    {state, _} =
      state.turn_order
      |> Enum.with_index()
      |> Enum.reduce({state, []}, fn {id, index}, {state, taken} ->
        target = @width / 2 + spawn_band(count) * ((index + 0.5) / count - 0.5)

        apart = Enum.filter(spots, fn {x, _} -> Enum.all?(taken, &(abs(&1 - x) >= 14)) end)
        candidates = if apart == [], do: spots, else: apart

        {x, y} =
          Enum.min_by(candidates, fn {x, _} -> abs(x - target) end, fn -> {round(target), 10} end)

        wizard = %{
          id: id,
          kind: :wizard,
          owner: id,
          x: x,
          y: y,
          hp: @wizard_hp,
          max_hp: @wizard_hp,
          dead: false,
          ward: 0,
          float: 0
        }

        {put_unit(state, wizard), [x | taken]}
      end)

    state
  end

  # Wizards start within reach of each other however wide the world is.
  defp spawn_band(count), do: min(@width - 36, 55 * (count + 1))

  def standable_spots(state, height) do
    for x <- 4..(@width - 5),
        y <- height..(state.water_level - 3),
        Terrain.solid?(state.terrain, x, y + 1),
        Enum.all?(0..(height - 1), &(not Terrain.solid?(state.terrain, x, y - &1))),
        do: {x, y}
  end

  def put_unit(state, unit), do: %{state | units: Map.put(state.units, unit.id, unit)}

  def unit_height(%{kind: kind}) when kind in [:wizard, :golem], do: 3
  def unit_height(%{kind: :crate}), do: 1
  def unit_height(_), do: 2

  # Shots connect with everything drawn, so a wizard's hat counts as well as its body.
  def hit_height(%{kind: :wizard}), do: 5.2
  def hit_height(unit), do: unit_height(unit) + 0.4

  def center(unit), do: {unit.x + 0.5, unit.y + 1 - unit_height(unit) / 2}

  def blocked?(state, unit, x, y) do
    x < 0 or x >= @width or
      Enum.any?(0..(unit_height(unit) - 1), fn dy -> Terrain.solid?(state.terrain, x, y - dy) end)
  end

  def step(state, unit, dir) do
    x = unit.x + dir

    climb = if Map.get(unit, :float, 0) > 0, do: 6, else: @max_climb

    case Enum.find(0..climb, &(not blocked?(state, unit, x, unit.y - &1))) do
      nil -> {:error, :blocked}
      climb -> {:ok, %{unit | x: x, y: unit.y - climb}}
    end
  end

  # Levitating units hover wherever they are.
  def settle(state, unit) do
    if Map.get(unit, :float, 0) > 0, do: {unit, 0}, else: do_settle(state, unit)
  end

  def do_settle(state, unit) do
    fall =
      Enum.reduce_while(0..@height, 0, fn fall, _ ->
        y = unit.y + fall

        if y + 1 >= @height or y >= state.water_level or
             Terrain.solid?(state.terrain, unit.x, y + 1),
           do: {:halt, fall},
           else: {:cont, fall + 1}
      end)

    {%{unit | y: min(unit.y + fall, @height)}, fall}
  end

  def settle_all(state) do
    state =
      Enum.reduce(Enum.sort(Map.keys(state.units)), unbury_all(state), fn id, state ->
        unit = state.units[id]

        if alive_unit?(unit) do
          {unit, fall} = settle(state, unit)
          state |> put_unit(unit) |> fall_damage(id, fall)
        else
          state
        end
      end)

    crates =
      state.crates
      |> Enum.map(&elem(settle(state, &1), 0))
      |> Enum.reject(&(&1.y >= state.water_level))

    %{state | crates: crates}
  end

  def unbury_all(state) do
    Enum.reduce(Map.values(state.units), state, fn unit, state ->
      lifted =
        Enum.find_value(0..30, fn dy ->
          if not blocked?(state, unit, unit.x, unit.y - dy), do: %{unit | y: unit.y - dy}
        end)

      put_unit(state, lifted || unit)
    end)
  end

  def free_spot(state, x, y, unit) do
    x = Terrain.clamp(x, 0, @width - 1)
    y = Terrain.clamp(y, unit_height(unit), @height - 1)

    Enum.find_value(0..40, :error, fn dy ->
      if not blocked?(state, unit, x, y - dy) and y - dy >= unit_height(unit) - 1,
        do: {:ok, %{unit | x: x, y: y - dy}}
    end)
  end

  def fall_damage(state, id, fall) when fall > @fall_safe,
    do: damage(state, id, (fall - @fall_safe) * 2, nil)

  def fall_damage(state, _id, _fall), do: state

  def resolve_deaths(state) do
    Enum.reduce(Enum.sort(Map.keys(state.units)), state, fn id, state ->
      unit = state.units[id]

      cond do
        is_nil(unit) or unit.dead ->
          state

        unit.y >= state.water_level ->
          state |> put_unit(%{unit | hp: 0}) |> kill(unit, "sinks beneath the waves")

        unit.hp <= 0 ->
          kill(state, unit, "is defeated")

        true ->
          state
      end
    end)
  end

  defp kill(state, %{kind: :wizard} = unit, how) do
    state
    |> put_unit(%{unit | hp: 0, dead: true, y: min(unit.y, @height - 1)})
    |> Map.update!(:eliminated, &[unit.id | &1])
    |> log("#{player_name(state, unit.id)} #{how}!")
    |> remove_minions(unit.id)
  end

  defp kill(state, unit, how) do
    %{state | units: Map.delete(state.units, unit.id)}
    |> log("#{unit_name(state, unit)} #{how}.")
  end

  def remove_minions(state, owner),
    do: %{
      state
      | units: Map.reject(state.units, fn {_, u} -> u.kind != :wizard and u.owner == owner end)
    }

  def alive?(state, id), do: alive_unit?(state.units[id])
  def alive_unit?(nil), do: false
  def alive_unit?(unit), do: not unit.dead and unit.hp > 0

  def unit_name(state, %{kind: :wizard, id: id}), do: player_name(state, id)

  def unit_name(state, unit),
    do: "#{player_name(state, unit.owner)}'s #{Catalog.minion(unit.kind).name}"

  def player_name(state, id) do
    case state.players[id] do
      %{name: name} -> name
      _ -> "Someone"
    end
  end

  def log(state, message), do: %{state | events: Enum.take([message | state.events], 10)}
end
