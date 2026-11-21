defmodule Flamingo.GameModes.Spellslingers.Spells do
  @moduledoc false

  use Flamingo.GameModes.Spellslingers.Rules

  alias Flamingo.GameModes.Spellslingers.{Catalog, Physics, Rng, Terrain, Units}

  def roll_surge(state) do
    {chance, rng} = :rand.uniform_s(state.rng)
    state = %{state | rng: rng}

    if state.turn_number >= 4 and chance < 0.22 do
      {kind, rng} = Rng.pick([:meteors, :gale, :mana, :crates], state.rng)
      {kind, %{state | rng: rng}}
    else
      {nil, state}
    end
  end

  def surge_before(state, :meteors) do
    state = Units.log(state, "Wild magic! Meteors fall from the sky!")
    before = state

    {fx, rng} =
      Enum.reduce(0..3, {new_fx(state, nil) |> Map.put(:shake, true), state.rng}, fn i,
                                                                                     {fx, rng} ->
        {r, rng} = :rand.uniform_s(rng)
        {fx_with_meteor(fx, 10 + r * (@width - 20), i * 6, "surge"), rng}
      end)

    state = %{fx.state | rng: rng}
    {state, knocks} = resolve_fx(state, fx)
    record_cast(state, before, nil, "surge", fx, knocks)
  end

  def surge_before(state, :mana) do
    %{state | cooldowns: Map.new(state.cooldowns, fn {id, _} -> {id, %{}} end)}
    |> Units.log("Wild magic! A mana storm recharges every spell.")
  end

  def surge_before(state, :crates) do
    state
    |> Units.log("Wild magic! Supplies rain from the sky.")
    |> Units.drop_crate()
    |> Units.drop_crate()
  end

  def surge_before(state, _), do: state

  def surge_after(state, :gale) do
    {sign, rng} = Rng.pick([-1, 1], state.rng)

    %{state | wind: sign * 10, rng: rng}
    |> Units.log("Wild magic! A howling gale sweeps the arena.")
  end

  def surge_after(state, _), do: state

  def new_fx(state, target),
    do: %{
      state: state,
      target: target,
      segments: [],
      beams: [],
      auras: [],
      impulses: %{},
      shake: false
    }

  def in_place_range?(state, actor, x, y) do
    caster = state.units[actor]
    :math.sqrt((x - caster.x - 0.5) ** 2 + (y - caster.y + 1) ** 2) <= @place_range
  end

  def resolve_fx(state, fx) do
    {state, knocks} = Physics.apply_knocks(state, fx.impulses)
    # Anything knocked off the map or into the sea is gone before settling could
    # lift it back onto nearby ground.
    state =
      state
      |> Units.resolve_deaths()
      |> Units.settle_all()
      |> Units.collect_crates()
      |> Units.resolve_deaths()

    {state, knocks}
  end

  def record_cast(state, before, caster, spell_id, fx, knocks) do
    segments = Enum.reverse(fx.segments)
    flight = segments |> Enum.map(&(&1.start + length(&1.path))) |> Enum.max(fn -> 0 end)
    knock = knocks |> Enum.map(&length(&1.path)) |> Enum.max(fn -> 0 end)
    beams = Enum.reverse(fx.beams)

    knocked_out =
      for {id, %{kind: :wizard} = unit} <- before.units,
          Units.alive_unit?(unit) and not Units.alive?(state, id),
          do: id

    # Knockouts replay in slow motion on clients, so the turn waits for them.
    slow_mo =
      if knocked_out != [],
        do: round(knock * @dt * 1000 / @playback_speed * 1.9) + 1100,
        else: 0

    extra = if(beams != [], do: 500, else: 0) + if(fx.shake, do: 700, else: 0) + slow_mo

    %{
      state
      | cast_count: state.cast_count + 1,
        last_cast: %{
          id: state.cast_count + 1,
          caster_id: caster,
          spell: spell_id,
          segments:
            Enum.map(segments, fn segment ->
              %{segment | path: Enum.map(segment.path, &round_point/1)}
            end),
          beams: beams,
          knocks: Enum.map(knocks, fn k -> %{k | path: Enum.map(k.path, &round_point/1)} end),
          shake: fx.shake,
          auras: Enum.reverse(fx.auras),
          ko: knocked_out,
          flight_steps: flight,
          duration_ms: round((flight + knock) * @dt * 1000 / @playback_speed) + extra + 450
        }
    }
  end

  defp round_point({x, y}), do: [Float.round(x * 1.0, 2), Float.round(y * 1.0, 2)]

  def caster_origin(state, actor) do
    caster = state.units[actor]
    {caster.x + 0.5, caster.y - 2.0}
  end

  # Flies the spell's main projectile and records it as the first segment.
  defp throw_spell(fx, actor, spell, angle, power) do
    {path, impact} =
      case fx.target do
        # A placed spell appears at the target and drops straight onto the ground below.
        {x, y} ->
          Physics.fly(
            fx.state,
            Terrain.surface_above(fx.state, x, y),
            {0.0, 6.0},
            %{spell | gravity: 1.0, wind: 0.0},
            actor
          )

        nil ->
          Physics.fly(
            fx.state,
            caster_origin(fx.state, actor),
            Physics.launch(spell, angle, power),
            spell,
            actor
          )
      end

    hit? = elem(impact, 0) in [:terrain, :unit]

    segment = %{
      path: path,
      start: 0,
      spell: spell.id,
      radius: if(hit?, do: spell.radius, else: 0),
      hit: hit?
    }

    {%{fx | segments: [segment | fx.segments]}, impact, length(path)}
  end

  defp fizzle(fx), do: %{fx | state: Units.log(fx.state, "…and it fizzles out.")}

  def effect(:blast, fx, actor, spell, angle, power) do
    case throw_spell(fx, actor, spell, angle, power) do
      {fx, {kind, pos}, _} when kind in [:terrain, :unit] ->
        Physics.explode(fx, actor, pos, spell.radius, spell.damage, spell.knock)

      {fx, _, _} ->
        fizzle(fx)
    end
  end

  def effect(:cluster, fx, actor, spell, angle, power) do
    case throw_spell(fx, actor, spell, angle, power) do
      {fx, {kind, {x, y}}, steps} when kind in [:terrain, :unit] ->
        fx = Physics.explode(fx, actor, {x, y}, spell.radius, spell.damage, spell.knock)
        bomblet = %{spell | gravity: 1.0, wind: 0.5}

        Enum.reduce([-15, -6, 6, 15], fx, fn vx, fx ->
          {path, impact} = Physics.fly(fx.state, {x, y - 1.5}, {vx * 1.0, -24.0}, bomblet, nil)
          hit? = elem(impact, 0) in [:terrain, :unit]

          fx = %{
            fx
            | segments: [
                %{
                  path: path,
                  start: steps,
                  spell: "cluster",
                  radius: if(hit?, do: 4, else: 0),
                  hit: hit?
                }
                | fx.segments
              ]
          }

          if hit?, do: Physics.explode(fx, actor, elem(impact, 1), 4, 12, 18), else: fx
        end)

      {fx, _, _} ->
        fizzle(fx)
    end
  end

  def effect(:rain, fx, actor, spell, angle, power) do
    {fx, {kind, {x, _}}, steps} = throw_spell(fx, actor, spell, angle, power)

    if kind in [:lost] do
      fizzle(fx)
    else
      x = x |> max(2) |> min(@width - 3)

      [-16, -8, 0, 8, 16]
      |> Enum.with_index()
      |> Enum.reduce(%{fx | shake: true}, fn {offset, i}, fx ->
        fx_with_meteor(fx, x + offset, steps + i * 4, "firerain", actor, spell)
      end)
    end
  end

  def effect(:raise, fx, actor, spell, angle, power) do
    case throw_spell(fx, actor, spell, angle, power) do
      {fx, {kind, {x, y}}, _} when kind in [:terrain, :unit, :lost] ->
        state =
          fx.state
          |> Terrain.fill([{x, y - spell.radius * 0.4, spell.radius}])
          |> Units.unbury_all()

        %{fx | state: state}

      {fx, _, _} ->
        fizzle(fx)
    end
  end

  def effect(:blink, fx, actor, spell, angle, power) do
    case throw_spell(fx, actor, spell, angle, power) do
      {fx, {kind, {x, y}}, _} when kind in [:terrain, :unit, :lost] ->
        wizard = fx.state.units[actor]

        case Units.free_spot(fx.state, floor(x), floor(y), wizard) do
          {:ok, moved} ->
            {moved, fall} = Units.settle(fx.state, moved)
            %{fx | state: fx.state |> Units.put_unit(moved) |> Units.fall_damage(actor, fall)}

          :error ->
            %{fx | state: Units.log(fx.state, "…but there was no room to land.")}
        end

      {fx, _, _} ->
        fizzle(fx)
    end
  end

  def effect(:summon, fx, actor, spell, angle, power) do
    case throw_spell(fx, actor, spell, angle, power) do
      {fx, {kind, {x, y}}, _} when kind in [:terrain, :unit, :lost] ->
        %{fx | state: summon(fx.state, actor, spell.minion, x, y)}

      {fx, _, _} ->
        fizzle(fx)
    end
  end

  def effect(:quake, fx, actor, spell, _angle, _power) do
    state = Units.log(fx.state, "The ground heaves!")
    spots = Units.standable_spots(state, 1)

    # With no ground left to stand on there is nothing to crack, but it still shakes.
    pit_count = if spots == [], do: 0, else: 14

    {state, pits} =
      Enum.reduce(1..pit_count//1, {state, []}, fn _, {state, pits} ->
        {{x, y}, rng} = Rng.pick(spots, state.rng)
        {%{state | rng: rng}, [{x + 0.5, y + 1.5, 3} | pits]}
      end)

    fx = %{fx | state: Terrain.carve(state, pits), shake: true}

    fx.state.units
    |> Map.values()
    |> Enum.filter(&(Units.alive_unit?(&1) and &1.id != actor))
    |> Enum.sort_by(& &1.id)
    |> Enum.reduce(fx, fn unit, fx ->
      {r, rng} = :rand.uniform_s(fx.state.rng)
      state = %{fx.state | rng: rng} |> Units.damage(unit.id, spell.damage, actor)
      Physics.push(%{fx | state: state}, unit.id, {(r - 0.5) * 24, -18.0})
    end)
  end

  def effect(:gust, fx, actor, spell, angle, power) do
    case throw_spell(fx, actor, spell, angle, power) do
      {fx, {kind, {x, y}}, _} when kind in [:terrain, :unit, :water] ->
        fx.state.units
        |> Map.values()
        |> Enum.sort_by(& &1.id)
        |> Enum.reduce(fx, fn unit, fx ->
          {cx, cy} = Units.center(unit)
          distance = :math.sqrt((cx - x) ** 2 + (cy - y) ** 2)

          if Units.alive_unit?(unit) and distance <= spell.radius do
            falloff = max(0.35, 1 - distance / (spell.radius + 1))
            fx = %{fx | state: Units.damage(fx.state, unit.id, spell.damage, actor)}
            Physics.add_impulse(fx, unit.id, cx - x, cy - y, distance, spell.knock * falloff)
          else
            fx
          end
        end)

      {fx, _, _} ->
        fizzle(fx)
    end
  end

  def effect(:chain, fx, actor, spell, angle, power) do
    case throw_spell(fx, actor, spell, angle, power) do
      {fx, {kind, {x, y}}, _} when kind in [:terrain, :unit] ->
        fx = Physics.explode(fx, actor, {x, y}, spell.radius, spell.damage, spell.knock)
        chain(fx, actor, {x, y}, MapSet.new([actor]), 2)

      {fx, _, _} ->
        fizzle(fx)
    end
  end

  def effect(:burrow, fx, actor, spell, angle, _power) do
    {ox, oy} = caster_origin(fx.state, actor)
    radians = angle * :math.pi() / 180
    {dx, dy} = {:math.cos(radians), -:math.sin(radians)}

    points =
      Enum.reduce_while(1..70, [], fn d, points ->
        px = ox + dx * d
        py = oy + dy * d

        if px < 0 or px >= @width or py < -10 or py >= fx.state.water_level,
          do: {:halt, points},
          else: {:cont, [{px, py} | points]}
      end)
      |> Enum.reverse()

    state = Terrain.carve(fx.state, Enum.map(points, fn {x, y} -> {x, y, 2.6} end))

    state =
      state.units
      |> Map.values()
      |> Enum.filter(fn unit ->
        {cx, cy} = Units.center(unit)

        Units.alive_unit?(unit) and unit.id != actor and
          Enum.any?(points, fn {x, y} -> (cx - x) ** 2 + (cy - y) ** 2 <= 6 end)
      end)
      |> Enum.reduce(state, &Units.damage(&2, &1.id, spell.damage, actor))
      |> Units.unbury_all()

    path = [{ox, oy} | Enum.take_every(points, 2)]
    segment = %{path: path, start: 0, spell: "burrow", radius: 0, hit: false}
    %{fx | state: state, segments: [segment | fx.segments]}
  end

  def effect(:heal, fx, actor, spell, angle, power) do
    case throw_spell(fx, actor, spell, angle, power) do
      {fx, {kind, {x, y}}, _} when kind in [:terrain, :unit, :lost] ->
        healed =
          fx.state.units
          |> Map.values()
          |> Enum.filter(fn unit ->
            {cx, cy} = Units.center(unit)

            Units.alive_unit?(unit) and unit.owner == actor and
              (cx - x) ** 2 + (cy - y) ** 2 <= spell.radius ** 2
          end)

        state =
          healed
          |> Enum.reduce(fx.state, fn unit, state ->
            Units.put_unit(state, %{unit | hp: min(unit.max_hp, unit.hp + spell.damage)})
          end)
          |> Terrain.fill([{x, y, 2.5}])
          |> Units.unbury_all()

        message =
          if healed == [],
            do: "…flowers bloom, but nobody is healed.",
            else: "Flowers bloom: #{length(healed)} healed!"

        %{fx | state: Units.log(state, message)}

      {fx, _, _} ->
        fizzle(fx)
    end
  end

  def effect(:ward, fx, actor, _spell, _angle, _power) do
    wizard = fx.state.units[actor]

    state =
      fx.state
      |> Units.put_unit(Map.put(wizard, :ward, 40))
      |> Units.log("#{Units.player_name(fx.state, actor)} is wrapped in an arcane ward.")

    %{fx | state: state, auras: [%{id: actor, kind: "ward"} | fx.auras]}
  end

  def effect(:levitate, fx, actor, _spell, _angle, _power) do
    wizard = fx.state.units[actor]

    state =
      fx.state
      |> Units.put_unit(Map.put(wizard, :float, 2))
      |> Units.log("#{Units.player_name(fx.state, actor)} begins to float.")

    %{fx | state: state, auras: [%{id: actor, kind: "levitate"} | fx.auras]}
  end

  def effect(:ledge, %{target: {x, y}} = fx, _actor, _spell, _angle, _power) do
    {x, y} = Terrain.surface_above(fx.state, x, y)
    segment = %{path: [{x, y - 3}, {x, y}], start: 0, spell: "ledge", radius: 0, hit: true}
    build_ledge(%{fx | segments: [segment | fx.segments]}, x, y)
  end

  def effect(:ledge, fx, actor, spell, angle, power) do
    {path, {kind, impact}} =
      Physics.fly(
        fx.state,
        caster_origin(fx.state, actor),
        Physics.launch(spell, angle, power),
        spell,
        actor
      )

    # The stone seed builds its ledge at the top of the arc, or where it strikes first.
    apex =
      path
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.find_index(fn [{_, y0}, {_, y1}] -> y1 > y0 end)

    {path, {x, y}} =
      if apex && apex >= 3,
        do: {Enum.take(path, apex + 1), Enum.at(path, apex)},
        else: {path, impact}

    segment = %{path: path, start: 0, spell: "ledge", radius: 0, hit: true}
    fx = %{fx | segments: [segment | fx.segments]}

    if kind == :out and is_nil(apex), do: fizzle(fx), else: build_ledge(fx, x, y)
  end

  def effect(:updraft, fx, actor, spell, angle, power) do
    case throw_spell(fx, actor, spell, angle, power) do
      {fx, {kind, {x, y}}, _} when kind in [:terrain, :unit, :water] ->
        fx.state.units
        |> Map.values()
        |> Enum.sort_by(& &1.id)
        |> Enum.reduce(fx, fn unit, fx ->
          {cx, cy} = Units.center(unit)
          distance = :math.sqrt((cx - x) ** 2 + (cy - y) ** 2)

          if Units.alive_unit?(unit) and distance <= spell.radius do
            falloff = max(0.5, 1 - distance / (spell.radius + 1))
            Physics.push(fx, unit.id, {(cx - x) * 1.2, -spell.knock * falloff})
          else
            fx
          end
        end)

      {fx, _, _} ->
        fizzle(fx)
    end
  end

  def effect(:swap, fx, actor, spell, angle, power) do
    case throw_spell(fx, actor, spell, angle, power) do
      {fx, {:unit, {x, y}}, _} ->
        other = Physics.unit_hit(fx.state, x, y, &(&1 != actor))
        a = fx.state.units[actor]
        b = other && fx.state.units[other]

        if b do
          state =
            fx.state
            |> Units.put_unit(%{a | x: b.x, y: b.y})
            |> Units.put_unit(%{b | x: a.x, y: a.y})
            |> Units.log(
              "#{Units.player_name(fx.state, actor)} warps places with #{Units.unit_name(fx.state, b)}!"
            )

          %{
            fx
            | state: state,
              auras: [%{id: actor, kind: "swap"}, %{id: b.id, kind: "swap"} | fx.auras]
          }
        else
          fizzle(fx)
        end

      {fx, _, _} ->
        %{fx | state: Units.log(fx.state, "…the warp finds nobody to swap with.")}
    end
  end

  def effect(:chaos, fx, actor, spell, angle, power) do
    {fx, {kind, {x, y}}, steps} = throw_spell(fx, actor, spell, angle, power)
    landed? = kind in [:terrain, :unit]
    x = x |> max(2) |> min(@width - 3)
    y = y |> max(2) |> min(fx.state.water_level - 1)

    outcomes =
      if landed?,
        do: [:mega, :swap, :flood, :bloom, :swarm, :rain],
        else: [:swap, :flood, :bloom]

    {outcome, rng} = Rng.pick(outcomes, fx.state.rng)
    fx = %{fx | state: %{fx.state | rng: rng}}

    case outcome do
      :mega ->
        fx = %{
          fx
          | state: Units.log(fx.state, "Chaos! The orb detonates with terrible force!"),
            shake: true
        }

        Physics.explode(fx, actor, {x, y}, 12, 40, 60)

      :swap ->
        others = Enum.filter(fx.state.turn_order, &(&1 != actor and Units.alive?(fx.state, &1)))
        {other, rng} = Rng.pick(others, fx.state.rng)
        a = fx.state.units[actor]
        b = fx.state.units[other]

        state =
          %{fx.state | rng: rng}
          |> Units.put_unit(%{a | x: b.x, y: b.y})
          |> Units.put_unit(%{b | x: a.x, y: a.y})
          |> Units.log(
            "Chaos! #{Units.player_name(fx.state, actor)} swaps places with #{Units.player_name(fx.state, other)}!"
          )

        %{fx | state: state}

      :flood ->
        state = %{fx.state | water_level: max(fx.state.water_level - 5, 10)}
        %{fx | state: Units.log(state, "Chaos! The sea surges upward!")}

      :bloom ->
        units =
          Map.new(fx.state.units, fn {id, unit} ->
            if Units.alive_unit?(unit),
              do: {id, %{unit | hp: min(unit.max_hp, unit.hp + 20)}},
              else: {id, unit}
          end)

        %{
          fx
          | state: Units.log(%{fx.state | units: units}, "Chaos! Everyone is healed a little.")
        }

      :swarm ->
        state =
          fx.state
          |> Units.log("Chaos! Creatures pour out of the orb!")
          |> summon(actor, :thornling, x - 3, y)
          |> summon(actor, :imp, x + 3, y)

        %{fx | state: state}

      :rain ->
        fx = %{fx | state: Units.log(fx.state, "Chaos! The sky opens!"), shake: true}

        Enum.reduce(0..7, fx, fn i, fx ->
          fx_with_meteor(fx, x + (i - 3.5) * 6, steps + i * 3, "chaos", actor)
        end)
    end
  end

  defp fx_with_meteor(fx, x, start, color, actor \\ nil, spell \\ nil) do
    meteor = spell || %{gravity: 1.0, wind: 1.0, speed: 1.0}
    radius = if(spell, do: spell.radius, else: 5)
    damage = if(spell, do: spell.damage, else: 16)
    knock = if(spell, do: spell.knock, else: 22)
    {path, impact} = Physics.fly(fx.state, {x, -4.0}, {fx.state.wind * 1.5, 8.0}, meteor, nil)
    hit? = elem(impact, 0) in [:terrain, :unit]

    segment = %{
      path: path,
      start: start,
      spell: color,
      radius: if(hit?, do: radius, else: 0),
      hit: hit?
    }

    fx = %{fx | segments: [segment | fx.segments]}
    if hit?, do: Physics.explode(fx, actor, elem(impact, 1), radius, damage, knock), else: fx
  end

  defp chain(fx, _actor, _from, _hit, 0), do: fx

  defp chain(fx, actor, {x, y}, hit, jumps) do
    target =
      fx.state.units
      |> Map.values()
      |> Enum.filter(&(Units.alive_unit?(&1) and not MapSet.member?(hit, &1.id)))
      |> Enum.map(fn unit ->
        {cx, cy} = Units.center(unit)
        {unit, {cx, cy}, :math.sqrt((cx - x) ** 2 + (cy - y) ** 2)}
      end)
      |> Enum.filter(fn {_, _, d} -> d <= 45 end)
      |> Enum.min_by(fn {_, _, d} -> d end, fn -> nil end)

    case target do
      nil ->
        fx

      {unit, {cx, cy}, d} ->
        state = fx.state |> Units.damage(unit.id, 14, actor)
        state = Units.log(state, "Lightning arcs to #{Units.unit_name(state, unit)}!")

        fx = %{
          fx
          | state: state,
            beams: [[x, y, cx, cy] |> Enum.map(&Float.round(&1 * 1.0, 2)) | fx.beams]
        }

        fx = Physics.add_impulse(fx, unit.id, cx - x, cy - y, d, 14)
        chain(fx, actor, {cx, cy}, MapSet.put(hit, unit.id), jumps - 1)
    end
  end

  defp summon(state, actor, kind, x, y) do
    stats = Catalog.minion(kind)

    owned =
      Enum.count(state.units, fn {_, u} ->
        u.kind != :wizard and u.owner == actor and Units.alive_unit?(u)
      end)

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
      owned >= @max_minions ->
        Units.log(
          state,
          "…but #{Units.player_name(state, actor)} already commands #{@max_minions} minions."
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

  defp build_ledge(fx, x, y) do
    x = Terrain.clamp(x, 8, @width - 9)
    y = Terrain.clamp(y, 4, fx.state.water_level - 1)

    state =
      fx.state |> Terrain.fill(for(dx <- -7..7, do: {x + dx, y + 0.5, 1.2})) |> Units.unbury_all()

    %{fx | state: Units.log(state, "A stone ledge rises from the air!")}
  end
end
