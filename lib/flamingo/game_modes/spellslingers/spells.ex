defmodule Flamingo.GameModes.Spellslingers.Spells do
  @moduledoc false

  use Flamingo.GameModes.Spellslingers.Rules

  alias Flamingo.GameModes.Spellslingers.{
    Catalog,
    Crates,
    Fx,
    Minions,
    Physics,
    Rng,
    Terrain,
    Units
  }

  @doc """
  Runs a cast: `effects` gets a fresh `Fx` and returns it with the cast's
  effects applied. Then knockback, deaths and settling resolve, and the result
  is recorded as the state's `last_cast` for clients to replay.
  """
  def run(state, caster, spell_id, target, effects) do
    fx = effects.(%{Fx.new(state, target) | grand: Catalog.grand?(spell_id)})
    {after_fx, knocks} = resolve_fx(fx.state, fx)
    record_cast(after_fx, state, caster, spell_id, fx, knocks)
  end

  def in_place_range?(state, actor, x, y) do
    caster = state.units[actor]
    :math.sqrt((x - caster.x - 0.5) ** 2 + (y - caster.y + 1) ** 2) <= state.tuning.place_range
  end

  defp resolve_fx(state, fx) do
    {state, knocks} = Physics.apply_knocks(state, fx.impulses)
    # Anything knocked off the map or into the sea is gone before settling could
    # lift it back onto nearby ground.
    state =
      state
      |> Units.resolve_deaths()
      |> Units.settle_all()
      |> Crates.collect_crates()
      |> Units.resolve_deaths()

    {state, knocks}
  end

  defp record_cast(state, before, caster, spell_id, fx, knocks) do
    segments = Enum.reverse(fx.segments)
    beams = Enum.reverse(fx.beams)

    # The flight lasts until the last projectile lands and the last unit is struck.
    flight =
      Enum.map(segments, &(&1.start + length(&1.path)))
      |> Enum.concat(Enum.map(fx.hits, &(&1.at + 1)))
      |> Enum.max(fn -> 0 end)

    knock = knocks |> Enum.map(&length(&1.path)) |> Enum.max(fn -> 0 end)

    knocked_out =
      for {id, %{kind: :wizard} = unit} <- before.units,
          Units.alive_unit?(unit) and not Units.alive?(state, id),
          do: id

    # Knockouts replay in slow motion on clients, so the turn waits for them.
    slow_mo =
      if knocked_out != [],
        do: round(knock * @dt * 1000 / @playback_speed * 1.9) + 1100,
        else: 0

    # Grand spells open with a title card before anything flies.
    extra =
      if(beams != [], do: 500, else: 0) + if(fx.shake, do: 700, else: 0) + slow_mo +
        if(fx.grand, do: @grand_intro_ms, else: 0)

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
          hits: Enum.reverse(fx.hits),
          knocks: Enum.map(knocks, fn k -> %{k | path: Enum.map(k.path, &round_point/1)} end),
          shake: fx.shake,
          grand: fx.grand,
          auras: Enum.reverse(fx.auras),
          ko: knocked_out,
          flight_steps: flight,
          duration_ms: round((flight + knock) * @dt * 1000 / @playback_speed) + extra + 450
        }
    }
  end

  defp round_point({x, y}), do: [Float.round(x * 1.0, 2), Float.round(y * 1.0, 2)]

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
            Units.caster_origin(fx.state, actor),
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

    {%{fx | segments: [segment | fx.segments], at: length(path) - 1}, impact, length(path)}
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
            | at: steps + length(path) - 1,
              segments: [
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
          Units.raise_ground(fx.state, [{x, y - spell.radius * 0.4, spell.radius}])

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

  # A dragon flies, so it appears right where it was placed instead of dropping to the ground.
  def effect(:summon, %{target: {x, y}} = fx, actor, %{minion: :dragon}, _angle, _power) do
    segment = %{path: [{x, y - 3}, {x, y}], start: 0, spell: "dragon", radius: 0, hit: true}

    %{
      fx
      | state: Minions.summon(fx.state, actor, :dragon, x, y + 1),
        segments: [segment | fx.segments]
    }
  end

  def effect(:summon, fx, actor, spell, angle, power) do
    case throw_spell(fx, actor, spell, angle, power) do
      {fx, {kind, {x, y}}, _} when kind in [:terrain, :unit, :lost] ->
        %{fx | state: Minions.summon(fx.state, actor, spell.minion, x, y)}

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
      fx = Fx.hit(%{fx | state: %{fx.state | rng: rng}}, unit.id, spell.damage, actor)
      Fx.push(fx, unit.id, {(r - 0.5) * 24, -18.0})
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
            fx = Fx.hit(fx, unit.id, spell.damage, actor)
            Fx.add_impulse(fx, unit.id, cx - x, cy - y, distance, spell.knock * falloff)
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
        # The unit struck directly already took the bolt, so the arcs skip it.
        struck = if kind == :unit, do: Physics.unit_hit(fx.state, x, y, &(&1 != actor))
        fx = Physics.explode(fx, actor, {x, y}, spell.radius, spell.damage, spell.knock)
        chain(fx, actor, {x, y}, MapSet.new(Enum.reject([actor, struck], &is_nil/1)), 2)

      {fx, _, _} ->
        fizzle(fx)
    end
  end

  def effect(:burrow, fx, actor, spell, angle, _power) do
    {ox, oy} = Units.caster_origin(fx.state, actor)
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

    fx = %{fx | state: Terrain.carve(fx.state, Enum.map(points, fn {x, y} -> {x, y, 2.6} end))}

    # The drawn path keeps every other point, so the point the tunnel first
    # reaches a unit at, halved, is the step it passes through them.
    fx =
      fx.state.units
      |> Map.values()
      |> Enum.filter(&(Units.alive_unit?(&1) and &1.id != actor))
      |> Enum.sort_by(& &1.id)
      |> Enum.reduce(fx, fn unit, fx ->
        {cx, cy} = Units.center(unit)
        reached = Enum.find_index(points, fn {x, y} -> (cx - x) ** 2 + (cy - y) ** 2 <= 6 end)

        if reached,
          do: Fx.hit(%{fx | at: div(reached, 2) + 1}, unit.id, spell.damage, actor),
          else: fx
      end)

    path = [{ox, oy} | Enum.take_every(points, 2)]
    segment = %{path: path, start: 0, spell: "burrow", radius: 0, hit: false}
    %{fx | state: Units.unbury_all(fx.state), segments: [segment | fx.segments]}
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
          |> Units.raise_ground([{x, y, 2.5}])

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
        Units.caster_origin(fx.state, actor),
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
            Fx.push(fx, unit.id, {(cx - x) * 1.2, -spell.knock * falloff})
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

  def effect(:napalm, fx, actor, spell, angle, power) do
    case throw_spell(fx, actor, spell, angle, power) do
      {fx, {kind, {x, y}}, _} when kind in [:terrain, :unit] ->
        fx = Physics.explode(fx, actor, {x, y}, spell.radius, spell.damage, spell.knock)
        ground = Terrain.ground_below(fx.state, x, y - 3) || floor(y)
        cx = floor(x)

        state =
          fx.state
          |> add_zone(%{kind: :napalm, owner: actor, x0: cx - 6, x1: cx + 6, y: ground, turns: 3})
          |> Units.log("Burning napalm splashes across the ground.")

        %{fx | state: state}

      {fx, _, _} ->
        fizzle(fx)
    end
  end

  def effect(:bounce, fx, actor, spell, angle, power) do
    origin = Units.caster_origin(fx.state, actor)
    bounce(fx, actor, spell, origin, Physics.launch(spell, angle, power), actor, 0, 3)
  end

  def effect(:seeker, fx, actor, spell, angle, power) do
    enemies =
      for {_, unit} <- fx.state.units,
          Units.alive_unit?(unit) and unit.owner != actor,
          do: Units.center(unit)

    # Once the arrow starts to fall it turns toward the nearest enemy, a little each step.
    steer = fn {x, y}, {vx, vy} = v ->
      if vy <= 0 or enemies == [] do
        v
      else
        {tx, ty} = Enum.min_by(enemies, fn {ex, ey} -> (ex - x) ** 2 + (ey - y) ** 2 end)
        heading = :math.atan2(vy, vx)
        turn = clamp(angle_between(heading, :math.atan2(ty - y, tx - x)), -0.16, 0.16)
        speed = max(:math.sqrt(vx * vx + vy * vy), 32)
        {:math.cos(heading + turn) * speed, :math.sin(heading + turn) * speed}
      end
    end

    {path, {kind, pos}} =
      Physics.fly(
        fx.state,
        Units.caster_origin(fx.state, actor),
        Physics.launch(spell, angle, power),
        spell,
        actor,
        steer
      )

    hit? = kind in [:terrain, :unit]

    segment = %{
      path: path,
      start: 0,
      spell: spell.id,
      radius: if(hit?, do: spell.radius, else: 0),
      hit: hit?
    }

    fx = %{fx | segments: [segment | fx.segments], at: segment.start + length(segment.path) - 1}

    if hit?,
      do: Physics.explode(fx, actor, pos, spell.radius, spell.damage, spell.knock),
      else: fizzle(fx)
  end

  # A grand meteor tears out of the sky at the chosen spot; sky spells need no line of sight.
  def effect(:cataclysm, %{target: {x, y}} = fx, actor, spell, _angle, _power) do
    x = clamp(x, 2, @width - 3)
    from_x = if x + 26 < @width - 1, do: x + 26, else: x - 26
    from = {from_x, Terrain.sky_row(fx.state, from_x) + 0.5}
    {fx0, fy0} = from
    distance = max(:math.sqrt((x - fx0) ** 2 + (y - fy0) ** 2), 1.0)
    velocity = {(x - fx0) / distance * 55, (y - fy0) / distance * 55}
    {path, {kind, pos}} = Physics.fly(fx.state, from, velocity, %{gravity: 0.0, wind: 0.0}, nil)
    hit? = kind in [:terrain, :unit]

    segment = %{
      path: path,
      start: 0,
      spell: spell.id,
      radius: if(hit?, do: spell.radius, else: 0),
      hit: hit?
    }

    fx = %{
      fx
      | segments: [segment | fx.segments],
        at: segment.start + length(segment.path) - 1,
        shake: true
    }

    fx = %{fx | state: Units.log(fx.state, "The sky tears open!")}

    if hit?,
      do: Physics.explode(fx, actor, pos, spell.radius, spell.damage, spell.knock),
      else: %{fx | state: Units.log(fx.state, "…and the meteor hisses into the sea.")}
  end

  def effect(:volcano, %{target: {x, y}} = fx, actor, _spell, _angle, _power) do
    x = clamp(floor(x), 10, @width - 11)

    case Terrain.ground_below(fx.state, x, y) do
      nil ->
        fizzle(fx)

      ground ->
        cx = x + 0.5

        cone =
          for {dy, r} <- [{2, 9}, {0, 7.5}, {-2, 6}, {-4, 4.5}, {-6, 3}], do: {cx, ground + dy, r}

        state =
          fx.state
          |> Units.raise_ground(cone)
          |> Terrain.carve([{cx, ground - 8, 2}])

        zone = %{kind: :volcano, owner: actor, x: cx, y: ground - 10.0, turns: 3}

        state =
          state
          |> add_zone(zone)
          |> Units.log("A volcano bursts from the ground!")

        erupt(%{fx | state: state, shake: true}, zone, 0)
    end
  end

  def effect(:thunderhead, %{target: {x, _}} = fx, actor, _spell, _angle, _power) do
    x = clamp(floor(x), 18, @width - 19)

    state =
      fx.state
      |> add_zone(%{kind: :thunderhead, owner: actor, x0: x - 16, x1: x + 16, turns: 3})
      |> Units.log("A thunderhead gathers. It will strike for three rounds.")

    %{fx | state: state}
  end

  def effect(:tide, fx, actor, _spell, _angle, _power) do
    state =
      fx.state
      |> rise_sea()
      |> add_zone(%{kind: :tide, owner: actor, turns: 3})

    %{fx | state: state, shake: true}
  end

  def effect(:freeze_bolt, fx, actor, spell, angle, power) do
    case throw_spell(fx, actor, spell, angle, power) do
      {fx, {kind, {x, y}}, _} when kind in [:terrain, :unit] ->
        fx = Physics.explode(fx, actor, {x, y}, spell.radius, spell.damage, spell.knock)

        state =
          fx.state
          |> units_near({x, y}, spell.radius + 2)
          |> Enum.reject(&(&1.id == actor))
          |> Enum.reduce(fx.state, &freeze(&2, &1.id))

        %{fx | state: state}

      {fx, _, _} ->
        fizzle(fx)
    end
  end

  # The sea's surface freezes into a walkable sheet below the chosen spot.
  def effect(:icefloe, %{target: {x, _}} = fx, _actor, _spell, _angle, _power) do
    x = clamp(floor(x), 12, @width - 13)
    top = fx.state.water_level - 1
    path = for i <- 0..6, do: {x + 0.5, top - 6 + i * 1.0}
    segment = %{path: path, start: 0, spell: "icefloe", radius: 0, hit: true}

    state =
      fx.state
      |> Units.raise_ground(for dx <- -11..11, do: {x + 0.5 + dx, top + 0.6, 1.1})
      |> Units.log("The sea freezes over!")

    %{fx | state: state, segments: [segment | fx.segments]}
  end

  def effect(:blizzard, %{target: {x, _}} = fx, actor, _spell, _angle, _power) do
    x = clamp(floor(x), 14, @width - 15)

    state =
      fx.state
      |> add_zone(%{kind: :blizzard, owner: actor, x0: x - 13, x1: x + 13, turns: 3})
      |> Units.log("A blizzard rolls in. It will lash the ground for three rounds.")

    %{fx | state: state}
  end

  def effect(:nova, fx, actor, spell, _angle, _power) do
    origin = Units.center(fx.state.units[actor])

    fx.state
    |> units_near(origin, spell.radius)
    |> Enum.reject(&(&1.id == actor))
    |> Enum.reduce(%{fx | auras: [%{id: actor, kind: "nova"} | fx.auras]}, fn unit, fx ->
      fx = Fx.hit(fx, unit.id, spell.damage, actor)
      %{fx | state: freeze(fx.state, unit.id), auras: [%{id: unit.id, kind: "nova"} | fx.auras]}
    end)
  end

  def effect(:ice_age, fx, actor, spell, _angle, _power) do
    fx = %{fx | state: Units.log(fx.state, "An ice age falls over the arena!"), shake: true}

    fx.state.units
    |> Map.values()
    |> Enum.filter(&(Units.alive_unit?(&1) and &1.owner != actor))
    |> Enum.sort_by(& &1.id)
    |> Enum.reduce(fx, fn unit, fx ->
      fx = Fx.hit(fx, unit.id, spell.damage, actor)
      %{fx | state: freeze(fx.state, unit.id), auras: [%{id: unit.id, kind: "iceage"} | fx.auras]}
    end)
  end

  def effect(:decay, fx, actor, spell, angle, power) do
    case throw_spell(fx, actor, spell, angle, power) do
      {fx, {kind, {x, y}}, _} when kind in [:terrain, :unit] ->
        fx = Physics.explode(fx, actor, {x, y}, spell.radius, spell.damage, spell.knock)

        state =
          fx.state
          |> units_near({x, y}, spell.radius + 2)
          |> Enum.reject(&(&1.id == actor))
          |> Enum.reduce(fx.state, fn unit, state ->
            state
            |> Units.put_unit(Map.put(unit, :decay, 3))
            |> Units.log("Rot takes hold of #{Units.unit_name(state, unit)}.")
          end)

        %{fx | state: state}

      {fx, _, _} ->
        fizzle(fx)
    end
  end

  def effect(:drain, fx, actor, spell, _angle, _power) do
    me = fx.state.units[actor]
    {mx, my} = Units.center(me)

    victims =
      fx.state
      |> units_near({mx, my}, spell.radius)
      |> Enum.filter(&(&1.owner != actor))

    fx = drain(fx, actor, victims, spell.damage)

    if victims == [],
      do: %{fx | state: Units.log(fx.state, "…but nobody is close enough to drain.")},
      else: %{fx | auras: [%{id: actor, kind: "drain"} | fx.auras]}
  end

  def effect(:lich, fx, actor, _spell, _angle, _power) do
    me = fx.state.units[actor]

    state =
      fx.state
      |> Units.put_unit(%{me | max_hp: 150, hp: min(me.hp + 50, 150)})
      |> add_zone(%{kind: :lich, owner: actor, turns: 5})
      |> Units.log("#{Units.player_name(fx.state, actor)} rises as a Lich!")

    %{fx | state: state, shake: true, auras: [%{id: actor, kind: "lich"} | fx.auras]}
  end

  def effect(:clockbomb, fx, actor, spell, angle, power) do
    case throw_spell(fx, actor, spell, angle, power) do
      {fx, {kind, {x, y}}, _} when kind in [:terrain, :unit] ->
        {x, y} = Terrain.surface_above(fx.state, x, y)

        bomb = %{
          kind: :bomb,
          owner: actor,
          spell: "clockbomb",
          x: x,
          y: y,
          radius: spell.radius,
          damage: spell.damage,
          knock: spell.knock,
          turns: 1
        }

        state =
          fx.state
          |> add_zone(bomb)
          |> Units.log("A clockwork bomb starts ticking…")

        %{fx | state: state}

      {fx, _, _} ->
        fizzle(fx)
    end
  end

  def effect(:doomsday, %{target: {x, y}} = fx, actor, spell, _angle, _power) do
    x = clamp(floor(x), 4, @width - 5)
    {_, y} = Terrain.surface_above(fx.state, x, y)

    case Terrain.ground_below(fx.state, x, y) do
      nil ->
        %{fx | state: Units.log(fx.state, "…and the bomb sinks into the sea.")}

      ground ->
        sky = Terrain.sky_row(fx.state, x) + 0.5
        path = for i <- 0..12, do: {x + 0.5, sky + (ground + 0.5 - sky) * i / 12}
        segment = %{path: path, start: 0, spell: "doomsday", radius: 0, hit: true}

        bomb = %{
          kind: :bomb,
          owner: actor,
          spell: "doomsday",
          x: x + 0.5,
          y: ground + 0.5,
          radius: spell.radius,
          damage: spell.damage,
          knock: spell.knock,
          turns: 2
        }

        state =
          fx.state
          |> add_zone(bomb)
          |> Units.log("The Doomsday Clock lands. It strikes in two turns!")

        %{fx | state: state, shake: true, segments: [segment | fx.segments]}
    end
  end

  # A tower of stone rises under the caster, lifting them high and warding them.
  def effect(:tower, fx, actor, _spell, _angle, _power) do
    me = fx.state.units[actor]
    lifted = %{me | y: me.y - 10}

    if lifted.y < 4 or Units.blocked?(fx.state, lifted, lifted.x, lifted.y) do
      %{fx | state: Units.log(fx.state, "…but there is no room to raise a tower.")}
    else
      tower =
        for y <- (lifted.y + 1)..(me.y + 1), dx <- -2..2, do: {me.x + 0.5 + dx, y + 0.5, 0.75}

      state =
        fx.state
        |> Units.put_unit(Map.put(lifted, :ward, 20))
        |> Units.raise_ground(tower)
        |> Units.log("An arcane tower lifts #{Units.player_name(fx.state, actor)} high!")

      %{fx | state: state, auras: [%{id: actor, kind: "ward"} | fx.auras]}
    end
  end

  def effect(:magnet, fx, actor, spell, angle, power) do
    case throw_spell(fx, actor, spell, angle, power) do
      {fx, {kind, {x, y}}, _} when kind in [:terrain, :unit, :water] ->
        {ox, oy} = Units.center(fx.state.units[actor])

        fx.state
        |> units_near({x, y}, spell.radius)
        |> Enum.reject(&(&1.id == actor))
        |> Enum.reduce(fx, fn unit, fx ->
          {cx, cy} = Units.center(unit)
          distance = max(:math.sqrt((ox - cx) ** 2 + (oy - cy) ** 2), 1.0)
          pull = spell.knock * min(1.0, distance / 30)
          fx = Fx.hit(fx, unit.id, spell.damage, actor)
          Fx.push(fx, unit.id, {(ox - cx) / distance * pull, -pull * 0.45})
        end)

      {fx, _, _} ->
        fizzle(fx)
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
          |> Minions.summon(actor, :thornling, x - 3, y)
          |> Minions.summon(actor, :imp, x + 3, y)

        %{fx | state: state}

      :rain ->
        fx = %{fx | state: Units.log(fx.state, "Chaos! The sky opens!"), shake: true}

        Enum.reduce(0..7, fx, fn i, fx ->
          fx_with_meteor(fx, x + (i - 3.5) * 6, steps + i * 3, "chaos", actor)
        end)
    end
  end

  @doc "Drops one meteor at column `x`, recording its flight from step `start`."
  def fx_with_meteor(fx, x, start, color, actor \\ nil, spell \\ nil) do
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

    fx = %{fx | segments: [segment | fx.segments], at: start + length(path) - 1}
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
        # Each arc strikes a moment after the one before it.
        fx = Fx.hit(%{fx | at: fx.at + 6}, unit.id, 14, actor)
        state = Units.log(fx.state, "Lightning arcs to #{Units.unit_name(fx.state, unit)}!")
        line = Enum.map([x, y, cx, cy], &Float.round(&1 * 1.0, 2))
        fx = %{fx | state: state, beams: [%{line: line, at: fx.at} | fx.beams]}

        fx = Fx.add_impulse(fx, unit.id, cx - x, cy - y, d, 14)
        chain(fx, actor, {cx, cy}, MapSet.put(hit, unit.id), jumps - 1)
    end
  end

  defp build_ledge(fx, x, y) do
    x = clamp(x, 8, @width - 9)
    y = clamp(y, 4, fx.state.water_level - 1)

    state =
      Units.raise_ground(fx.state, for(dx <- -7..7, do: {x + dx, y + 0.5, 1.2}))

    %{fx | state: Units.log(state, "A stone ledge rises from the air!")}
  end

  ## Spells that outlast their cast

  @doc "Adds a lasting effect, which acts at the start of its owner's turns."
  def add_zone(state, zone) do
    zone = Map.put(zone, :id, "z#{state.zone_count + 1}")
    %{state | zones: state.zones ++ [zone], zone_count: state.zone_count + 1}
  end

  def rise_sea(state) do
    %{state | water_level: max(state.water_level - 3, 10)}
    |> Units.log("The sea rises!")
  end

  @doc "Four lava bombs from a volcano's vent, flying from step `start`."
  def erupt(fx, zone, start) do
    spell = Catalog.spell("volcano")

    Enum.reduce(0..3, fx, fn i, fx ->
      {a, rng} = :rand.uniform_s(fx.state.rng)
      {b, rng} = :rand.uniform_s(rng)
      fx = %{fx | state: %{fx.state | rng: rng}}
      velocity = {(a - 0.5) * 64, -42.0 - b * 16}

      {path, {kind, pos}} =
        Physics.fly(fx.state, {zone.x, zone.y}, velocity, %{gravity: 1.0, wind: 0.5}, nil)

      hit? = kind in [:terrain, :unit]

      segment = %{
        path: path,
        start: start + i * 5,
        spell: "volcano",
        radius: if(hit?, do: spell.radius, else: 0),
        hit: hit?
      }

      fx = %{fx | segments: [segment | fx.segments], at: segment.start + length(segment.path) - 1}

      if hit?,
        do: Physics.explode(fx, zone.owner, pos, spell.radius, spell.damage, spell.knock),
        else: fx
    end)
  end

  @doc """
  Three lightning strikes inside a thunderhead's strip. The first seeks the tallest
  living thing under the cloud; the rest fall at random.
  """
  def strike(fx, zone, start) do
    spell = Catalog.spell("thunderhead")

    tallest =
      fx.state.units
      |> Map.values()
      |> Enum.filter(&(Units.alive_unit?(&1) and &1.x >= zone.x0 and &1.x <= zone.x1))
      |> Enum.min_by(&(&1.y - Units.unit_height(&1)), fn -> nil end)

    {columns, rng} =
      Enum.reduce(0..2, {[], fx.state.rng}, fn i, {cols, rng} ->
        {r, rng} = :rand.uniform_s(rng)
        col = if i == 0 and tallest, do: tallest.x, else: zone.x0 + floor(r * (zone.x1 - zone.x0))
        {cols ++ [col], rng}
      end)

    fx = %{fx | state: %{fx.state | rng: rng} |> Units.log("The thunderhead strikes!")}

    columns
    |> Enum.with_index()
    |> Enum.reduce(fx, fn {col, i}, fx ->
      from = {col + 0.5, Terrain.sky_row(fx.state, col) + 0.5}

      {path, {kind, pos}} =
        Physics.fly(fx.state, from, {0.0, 70.0}, %{gravity: 0.0, wind: 0.0}, nil)

      hit? = kind in [:terrain, :unit]

      segment = %{
        path: path,
        start: start + i * 6,
        spell: "thunderhead",
        radius: if(hit?, do: spell.radius, else: 0),
        hit: hit?
      }

      fx = %{fx | segments: [segment | fx.segments], at: segment.start + length(segment.path) - 1}

      if hit?,
        do: Physics.explode(fx, zone.owner, pos, spell.radius, spell.damage, spell.knock),
        else: fx
    end)
  end

  @doc "Napalm burns every unit standing in it."
  def burn(fx, zone) do
    fx.state.units
    |> Map.values()
    |> Enum.filter(fn unit ->
      Units.alive_unit?(unit) and unit.x >= zone.x0 and unit.x <= zone.x1 and
        abs(unit.y - zone.y) <= 4
    end)
    |> Enum.sort_by(& &1.id)
    |> Enum.reduce(fx, fn unit, fx ->
      fx = Fx.hit(fx, unit.id, 8, zone.owner)
      %{fx | state: Units.log(fx.state, "Napalm burns #{Units.unit_name(fx.state, unit)}!")}
    end)
  end

  @doc """
  A dragon glides toward the nearest enemy and breathes a fireball at it; a turret
  stays put and shoots a bolt at the nearest enemy in range.
  """
  def minion_shot(fx, dragon) do
    {spell, radius, damage, knock, verb, range} =
      if dragon.kind == :dragon,
        do: {"dragon", 4, 18, 22, "breathes fire", 10_000},
        else: {"turret", 2, 12, 12, "fires", 80}

    target =
      fx.state.units
      |> Map.values()
      |> Enum.filter(&(Units.alive_unit?(&1) and &1.owner != dragon.owner))
      |> Enum.filter(&((&1.x - dragon.x) ** 2 + (&1.y - dragon.y) ** 2 <= range * range))
      |> Enum.min_by(&((&1.x - dragon.x) ** 2 + (&1.y - dragon.y) ** 2), fn -> nil end)

    if target do
      dragon = if dragon.kind == :dragon, do: glide(fx.state, dragon, target), else: dragon
      state = Units.put_unit(fx.state, dragon)
      {ox, oy} = Units.center(dragon)
      {tx, ty} = Units.center(target)
      distance = max(:math.sqrt((tx - ox) ** 2 + (ty - oy) ** 2), 1.0)
      velocity = {(tx - ox) / distance * 60, (ty - oy) / distance * 60}

      {path, {kind, pos}} =
        Physics.fly(state, {ox, oy}, velocity, %{gravity: 0.0, wind: 0.0}, dragon.id)

      hit? = kind in [:terrain, :unit]

      segment = %{
        path: path,
        start: Fx.next_start(fx),
        spell: spell,
        radius: if(hit?, do: radius, else: 0),
        hit: hit?
      }

      state = Units.log(state, "#{Units.unit_name(state, dragon)} #{verb}!")

      fx = %{
        fx
        | state: state,
          segments: [segment | fx.segments],
          at: segment.start + length(segment.path) - 1
      }

      if hit?, do: Physics.explode(fx, dragon.owner, pos, radius, damage, knock), else: fx
    else
      fx
    end
  end

  @doc "Snow lashes every unit standing under a blizzard."
  def snow(fx, zone, damage) do
    fx.state.units
    |> Map.values()
    |> Enum.filter(&(Units.alive_unit?(&1) and &1.x >= zone.x0 and &1.x <= zone.x1))
    |> Enum.sort_by(& &1.id)
    |> Enum.reduce(%{fx | state: Units.log(fx.state, "The blizzard howls!")}, fn unit, fx ->
      {cx, cy} = Units.center(unit)
      path = for i <- 0..10, do: {cx + (10 - i) * 0.6, cy - 12 + i * 1.2}

      segment = %{
        path: path,
        start: Fx.next_start(fx),
        spell: "blizzard",
        radius: 0,
        hit: true
      }

      fx = %{fx | segments: [segment | fx.segments], at: segment.start + length(segment.path) - 1}
      Fx.hit(fx, unit.id, damage, zone.owner)
    end)
  end

  @doc "A clockwork bomb ticks down, and goes off on its last turn."
  def tick_bomb(fx, %{turns: 1} = bomb) do
    segment = %{
      path: [{bomb.x, bomb.y - 1}, {bomb.x, bomb.y}],
      start: Fx.next_start(fx),
      spell: bomb.spell,
      radius: bomb.radius,
      hit: true
    }

    fx = %{
      fx
      | segments: [segment | fx.segments],
        at: segment.start + 1,
        shake: fx.shake or bomb.radius >= 12,
        state:
          Units.log(
            fx.state,
            if(bomb.spell == "doomsday",
              do: "The Doomsday Clock strikes midnight!",
              else: "BOOM! The clockwork bomb goes off!"
            )
          )
    }

    Physics.explode(fx, bomb.owner, {bomb.x, bomb.y}, bomb.radius, bomb.damage, bomb.knock)
  end

  def tick_bomb(fx, bomb),
    do: %{fx | state: Units.log(fx.state, "Tick… tock… #{bomb.turns - 1} more turn.")}

  @doc "Rot eats at a decaying unit."
  def rot(fx, unit) do
    fx = Fx.hit(fx, unit.id, 6, nil)

    state =
      fx.state
      |> then(&Units.put_unit(&1, Map.update!(&1.units[unit.id], :decay, fn d -> d - 1 end)))
      |> Units.log("Decay eats at #{Units.unit_name(fx.state, unit)}.")

    %{fx | state: state}
  end

  @doc "Drains `amount` from each victim and heals `actor` by what it took."
  def drain(fx, actor, victims, amount) do
    {mx, my} = Units.center(fx.state.units[actor])

    fx =
      Enum.reduce(victims, fx, fn unit, fx ->
        {cx, cy} = Units.center(unit)
        before = fx.state.units[unit.id].hp
        # Each drain strikes a moment after the one before it, like chain lightning.
        fx = Fx.hit(%{fx | at: fx.at + 6}, unit.id, amount, actor)
        taken = before - fx.state.units[unit.id].hp
        me = fx.state.units[actor]
        state = Units.put_unit(fx.state, %{me | hp: min(me.max_hp, me.hp + taken)})
        line = Enum.map([cx, cy, mx, my], &Float.round(&1 * 1.0, 2))
        %{fx | state: state, beams: [%{line: line, at: fx.at} | fx.beams]}
      end)

    %{fx | state: Units.log(fx.state, "#{Units.player_name(fx.state, actor)} drinks their life!")}
  end

  @doc """
  Freezes a unit so it loses its next turn. A wizard who just thawed can't be frozen
  again before taking a turn.
  """
  def freeze(state, id) do
    case state.units[id] do
      %{} = unit ->
        if Units.alive_unit?(unit) and Map.get(unit, :frozen, 0) == 0 and
             not Map.get(unit, :thawed, false),
           do:
             state
             |> Units.put_unit(Map.put(unit, :frozen, 1))
             |> Units.log("#{Units.unit_name(state, unit)} is frozen solid!"),
           else: state

      nil ->
        state
    end
  end

  defp units_near(state, {x, y}, radius) do
    state.units
    |> Map.values()
    |> Enum.filter(fn unit ->
      {cx, cy} = Units.center(unit)
      Units.alive_unit?(unit) and (cx - x) ** 2 + (cy - y) ** 2 <= radius * radius
    end)
    |> Enum.sort_by(& &1.id)
  end

  # Up to six cells toward the target, keeping a little distance.
  defp glide(state, dragon, target) do
    dir = if target.x > dragon.x, do: 1, else: -1
    steps = clamp(abs(target.x - dragon.x) - 14, 0, 6)

    Enum.find_value(steps..0//-1, dragon, fn n ->
      x = dragon.x + dir * n
      if n == 0 or not Units.blocked?(state, dragon, x, dragon.y), do: %{dragon | x: x}
    end)
  end

  defp bounce(fx, actor, spell, origin, velocity, ignore, start, left) do
    {path, {kind, pos}} = Physics.fly(fx.state, origin, velocity, spell, ignore)
    steps = length(path)
    {vx, vy} = exit_velocity(path, velocity)
    speed = :math.sqrt(vx * vx + vy * vy)

    if kind == :terrain and left > 0 and speed > 10 do
      segment = %{path: path, start: start, spell: spell.id, radius: 0, hit: true}
      back = Enum.at(path, -2, origin)
      fx = %{fx | segments: [segment | fx.segments], at: segment.start + length(segment.path) - 1}

      bounce(
        fx,
        actor,
        spell,
        back,
        reflect(fx.state, back, pos, {vx, vy}),
        nil,
        start + steps - 1,
        left - 1
      )
    else
      hit? = kind in [:terrain, :unit]

      segment = %{
        path: path,
        start: start,
        spell: spell.id,
        radius: if(hit?, do: spell.radius, else: 0),
        hit: hit?
      }

      fx = %{fx | segments: [segment | fx.segments], at: segment.start + length(segment.path) - 1}

      if hit?,
        do: Physics.explode(fx, actor, pos, spell.radius, spell.damage, spell.knock),
        else: fizzle(fx)
    end
  end

  defp exit_velocity(path, fallback) do
    case Enum.take(path, -3) do
      [{x0, y0}, {x1, y1}, _] -> {(x1 - x0) / @dt, (y1 - y0) / @dt}
      _ -> fallback
    end
  end

  # Bounces off a floor or ceiling when the stone moved into it vertically, else off a wall.
  defp reflect(state, {bx, _by}, {_x, y}, {vx, vy}) do
    if Terrain.solid?(state.terrain, floor(bx), floor(y)) do
      {vx * 0.7, if(vy > 0, do: min(-vy * 0.6, -14.0), else: -vy * 0.6)}
    else
      {-vx * 0.6, vy * 0.7}
    end
  end

  defp angle_between(from, to) do
    d = to - from
    :math.atan2(:math.sin(d), :math.cos(d))
  end
end
