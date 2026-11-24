defmodule Flamingo.GameModes.Spellslingers.Spells do
  @moduledoc """
  What each spell in the arsenal does. Every cast gathers its flights, hits and
  knockback in an `Fx`, which `run/5` resolves and records for clients to replay.
  """

  use Flamingo.GameModes.Spellslingers.Rules

  alias Flamingo.GameModes.Spellslingers.{Crates, Fx, Physics, Rng, Terrain, Units}

  @doc """
  Runs a cast: `effects` gets a fresh `Fx` and returns it with the cast's
  effects applied. Then knockback, deaths and settling resolve, and the result
  is recorded as the state's `last_cast` for clients to replay.
  """
  def run(state, caster, spell_id, target, effects, grand \\ false) do
    fx = effects.(%{Fx.new(state, target) | grand: grand})
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

    # A knockout's knockback opens in slow motion on clients (about 250 ms lost) and the
    # KO banner holds a moment after, so the turn waits for both.
    slow_mo = if knocked_out != [], do: 950, else: 0

    # Grand spells open with a title card before anything flies.
    extra =
      if(fx.shake, do: 700, else: 0) + slow_mo + if(fx.grand, do: @grand_intro_ms, else: 0)

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
          hits: Fx.reveal(fx, before),
          knocks: Enum.map(knocks, fn k -> %{k | path: Enum.map(k.path, &round_point/1)} end),
          shake: fx.shake,
          grand: fx.grand,
          auras: Enum.reverse(fx.auras),
          ko: knocked_out,
          flight_steps: flight,
          duration_ms: round((flight + knock) * @dt * 1000 / @playback_speed) + extra + 300
        }
    }
  end

  defp round_point({x, y}), do: [Float.round(x * 1.0, 2), Float.round(y * 1.0, 2)]

  # Flies the spell's projectile from the caster and records it as a segment. Returns
  # {fx, impact, steps}, where impact is {kind, position}.
  defp throw_spell(fx, actor, spell, angle, power, steer \\ nil) do
    {path, impact} =
      Physics.fly(
        fx.state,
        Units.caster_origin(fx.state, actor),
        Physics.launch(spell, angle, power),
        spell,
        actor,
        steer
      )

    hit? = elem(impact, 0) in [:terrain, :unit]
    fx = add_segment(fx, path, 0, spell.id, if(hit?, do: spell.radius, else: 0), hit?)
    {fx, impact, length(path)}
  end

  defp add_segment(fx, path, start, spell, radius, hit?) do
    segment = %{path: path, start: start, spell: spell, radius: radius, hit: hit?}
    %{fx | segments: [segment | fx.segments], at: start + length(path) - 1}
  end

  # The throw that flies a hooked miner on a short arc to land just in front of the
  # thrower, on the side it came from.
  defp pull(state, unit, caster) do
    g = state.tuning.gravity
    side = if unit.x >= caster.x, do: 1, else: -1
    {tx, ty} = {caster.x + side * 4, caster.y}
    rise = max(unit.y - ty, 0) + 3
    vy = :math.sqrt(2 * g * rise)
    time = vy / g + :math.sqrt(2 * max(rise - (unit.y - ty), 0.5) / g)
    {(tx - unit.x) / time, -vy}
  end

  defp lay(fx, rune, message),
    do: %{fx | state: Units.log(%{fx.state | runes: fx.state.runes ++ [rune]}, message)}

  defp fizzle(fx), do: %{fx | state: Units.log(fx.state, "…and it fizzles out.")}

  defp blast(fx, actor, pos, spell),
    do: Physics.explode(fx, actor, pos, spell.radius, spell.damage, spell.knock)

  def effect(:blast, fx, actor, spell, angle, power) do
    case throw_spell(fx, actor, spell, angle, power) do
      {fx, {kind, pos}, _} when kind in [:terrain, :unit] -> blast(fx, actor, pos, spell)
      {fx, _, _} -> fizzle(fx)
    end
  end

  # A Fuse Rune bounces three times and bursts on its fourth landing.
  def effect(:bounce, fx, actor, spell, angle, power) do
    origin = Units.caster_origin(fx.state, actor)
    bounce(fx, actor, spell, origin, Physics.launch(spell, angle, power), actor, 0, 3)
  end

  # The Hallowed Orb bounces once, then the sky holds its breath.
  def effect(:holy, fx, actor, spell, angle, power) do
    origin = Units.caster_origin(fx.state, actor)
    fx = bounce(fx, actor, spell, origin, Physics.launch(spell, angle, power), actor, 0, 1)
    %{fx | shake: true}
  end

  def effect(:swarm, fx, actor, spell, angle, power) do
    case throw_spell(fx, actor, spell, angle, power) do
      {fx, {kind, pos}, steps} when kind in [:terrain, :unit] ->
        fx = blast(fx, actor, pos, spell)
        ember = %{spell | radius: 5, damage: 16, knock: 20, wind: 0.6}
        scatter(fx, actor, ember, pos, steps, [-18, -9, 0, 9, 18], -26.0)

      {fx, _, _} ->
        fizzle(fx)
    end
  end

  def effect(:egg, fx, actor, spell, angle, power) do
    case throw_spell(fx, actor, spell, angle, power) do
      {fx, {kind, pos}, steps} when kind in [:terrain, :unit] ->
        fx = %{blast(fx, actor, pos, spell) | shake: true}
        scatter(fx, actor, %{spell | wind: 0.3}, pos, steps, [-24, -12, 0, 12, 24], -34.0)

      {fx, _, _} ->
        fizzle(fx)
    end
  end

  def effect(:seeker, fx, actor, spell, angle, power) do
    enemies =
      for {_, unit} <- fx.state.units,
          Units.alive_unit?(unit) and unit.owner != actor,
          do: Units.center(unit)

    # Once the wisp starts to fall it turns toward the nearest enemy, a little each step.
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

    case throw_spell(fx, actor, spell, angle, power, steer) do
      {fx, {kind, pos}, _} when kind in [:terrain, :unit] -> blast(fx, actor, pos, spell)
      {fx, _, _} -> fizzle(fx)
    end
  end

  # The hare lands, then hops on the way it was thrown until it reaches a wizard, runs
  # out of hops or falls in the sea. A wall turns it round once.
  def effect(:hare, fx, actor, spell, angle, power) do
    case throw_spell(fx, actor, spell, angle, power) do
      {fx, {kind, {x, y}}, steps} when kind in [:terrain, :unit] ->
        # Landing is only its first hop; it goes off later.
        [thrown | rest] = fx.segments
        fx = %{fx | segments: [%{thrown | radius: 0} | rest]}
        dir = if :math.cos(angle * :math.pi() / 180) < 0, do: -1, else: 1
        hare = %{kind: :hare, x: clamp(floor(x), 0, @width - 1), y: floor(y)}

        case Units.free_spot(fx.state, hare.x, hare.y, hare) do
          {:ok, hare} ->
            {hare, _} = Units.settle(fx.state, hare)
            hop(fx, actor, spell, hare, dir, steps, 0, false)

          :error ->
            blast(fx, actor, {x, y}, spell)
        end

      {fx, _, _} ->
        fizzle(fx)
    end
  end

  # The pick on its chain: it flies straight along the aim and bites the first miner it
  # meets, who is yanked through the air to land at the thrower's feet. Rock stops it.
  def effect(:hook, fx, actor, spell, angle, _power) do
    {ox, oy} = Units.caster_origin(fx.state, actor)
    oy = oy + 1.5
    radians = angle * :math.pi() / 180
    {dx, dy} = {:math.cos(radians), -:math.sin(radians)}

    struck =
      Enum.reduce_while(1..(spell.range * 2), nil, fn i, _ ->
        d = i / 2
        {px, py} = {ox + dx * d, oy + dy * d}

        cond do
          id = Physics.unit_hit(fx.state, px, py, &(&1 != actor)) -> {:halt, {:unit, id, d}}
          Terrain.solid?(fx.state.terrain, floor(px), floor(py)) -> {:halt, {:rock, d}}
          true -> {:cont, nil}
        end
      end)

    reach =
      case struck do
        {:unit, _, d} -> d
        {:rock, d} -> d
        nil -> spell.range * 1.0
      end

    path = for i <- 0..6, do: {ox + dx * reach * i / 6, oy + dy * reach * i / 6}
    fx = add_segment(fx, path, 0, spell.id, 0, match?({:unit, _, _}, struck))

    case struck do
      {:unit, id, _} ->
        fx = Fx.hit(fx, id, spell.damage, actor)
        Fx.push(fx, id, pull(fx.state, fx.state.units[id], fx.state.units[actor]))

      {:rock, _} ->
        %{fx | state: Units.log(fx.state, "…and the shrimp snags on the rock.")}

      nil ->
        %{fx | state: Units.log(fx.state, "…and nobody bites.")}
    end
  end

  def effect(:tunnel, fx, actor, spell, angle, _power) do
    {ox, oy} = Units.caster_origin(fx.state, actor)
    radians = angle * :math.pi() / 180
    {dx, dy} = {:math.cos(radians), -:math.sin(radians)}

    points =
      Enum.reduce_while(1..spell.range, [], fn d, points ->
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
        reached = Enum.find_index(points, &(Units.distance_to(unit, &1) <= 1.5))

        if reached,
          do: Fx.hit(%{fx | at: div(reached, 2) + 1}, unit.id, spell.damage, actor),
          else: fx
      end)

    fx = add_segment(fx, [{ox, oy} | Enum.take_every(points, 2)], 0, spell.id, 0, false)
    %{fx | state: Units.unbury_all(fx.state)}
  end

  # The egg drops from under the caster, bounces and rolls down whatever slope it lands
  # on, falling off ledges, and waits wherever it stops for the end of their turn.
  # `spin` is how far it has rolled, so clients show it lying the way it stopped.
  def effect(:blastrune, fx, actor, _spell, _angle, _power) do
    wizard = fx.state.units[actor]
    start = {wizard.x + 0.5, wizard.y - 0.5}
    {where, {x, y}, path} = Physics.roll_egg(fx.state, start, {0.0, 0.0})
    fx = add_segment(fx, path, 0, "blastrune", 0, where == :rest)
    who = Units.player_name(fx.state, actor)

    if where == :rest do
      rune = %{owner: actor, x: x, y: y, spin: (x - elem(start, 0)) / Physics.egg_radius()}
      rolled = if abs(y - elem(start, 1)) > 4, do: "drops an egg", else: "lays an egg"
      lay(fx, rune, "#{who} #{rolled}. It fizzes. Run!")
    else
      %{fx | state: Units.log(fx.state, "…and the egg rolls into the sea.")}
    end
  end

  def effect(:meteors, %{target: {x, _}} = fx, actor, spell, _angle, _power) do
    x = clamp(x, 2, @width - 3)

    [-12, -6, 0, 6, 12]
    |> Enum.with_index()
    |> Enum.reduce(%{fx | shake: true}, fn {offset, i}, fx ->
      meteor(fx, x + offset, i * 5, spell.id, actor, spell)
    end)
  end

  def effect(:slab, %{target: {x, y}} = fx, _actor, _spell, _angle, _power) do
    {x, y} = Terrain.surface_above(fx.state, x, y)
    fx = add_segment(fx, [{x, y - 3}, {x, y}], 0, "slab", 0, true)
    x = clamp(x, 8, @width - 9)
    y = clamp(y, 4, fx.state.water_level - 1)
    state = Units.raise_ground(fx.state, for(dx <- -7..7, do: {x + dx, y + 0.5, 1.2}))
    %{fx | state: Units.log(state, "A shelf of mud hangs in the air.")}
  end

  # On a broom the wizard hovers for the rest of the turn with a fresh tank of flight.
  def effect(:broom, fx, actor, _spell, _angle, _power) do
    wizard = fx.state.units[actor]

    state =
      %{Units.put_unit(fx.state, %{wizard | float: 1}) | walk_left: @broom_fuel}
      |> Units.log("#{Units.player_name(fx.state, actor)} takes flight!")

    %{fx | state: state, auras: [%{id: actor, kind: "broom"} | fx.auras]}
  end

  def effect(:blink, %{target: {x, y}} = fx, actor, _spell, _angle, _power) do
    wizard = fx.state.units[actor]

    case Units.free_spot(fx.state, floor(x), floor(y), wizard) do
      {:ok, moved} ->
        {moved, fall} = Units.settle(fx.state, moved)
        from = {wizard.x + 0.5, wizard.y - 1.0}
        fx = add_segment(fx, [from, {moved.x + 0.5, moved.y - 1.0}], 0, "blink", 0, true)
        %{fx | state: fx.state |> Units.put_unit(moved) |> Units.fall_damage(actor, fall)}

      :error ->
        %{fx | state: Units.log(fx.state, "…but there was no room to land.")}
    end
  end

  # The anvil falls from the top of the sky and smashes down through whatever is below,
  # blasting at every slam until it sinks or has slammed six times.
  def effect(:anvil, %{target: {x, _}} = fx, actor, spell, _angle, _power) do
    x = clamp(x, 2, @width - 3)
    start = {x, Terrain.sky_row(fx.state, floor(x)) - 6.0}
    state = Units.log(fx.state, "Look out above: a lawn flamingo!")
    slam(%{fx | state: state, shake: true}, actor, spell, start, 0, 6)
  end

  def effect(:quake, fx, actor, spell, _angle, _power) do
    state = Units.log(fx.state, "The flock stomps! The ground heaves!")
    spots = Units.standable_spots(state, 1)

    # With no ground left to stand on there is nothing to crack, but it still shakes.
    pit_count = if spots == [], do: 0, else: 18

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
      Fx.push(fx, unit.id, {(r - 0.5) * spell.knock, -spell.knock * 0.75})
    end)
  end

  # Stars fall on every stretch of the map, a moment apart, in no particular order.
  def effect(:starfall, fx, actor, spell, _angle, _power) do
    count = 16
    span = (@width - 16) / (count - 1)
    state = Units.log(fx.state, "It's raining red-hot shrimp!")

    {order, rng} = Rng.shuffle(Enum.to_list(0..(count - 1)), state.rng)

    order
    |> Enum.with_index()
    |> Enum.reduce(%{fx | state: %{state | rng: rng}, shake: true}, fn {slot, i}, fx ->
      {r, rng} = :rand.uniform_s(fx.state.rng)
      fx = %{fx | state: %{fx.state | rng: rng}}
      meteor(fx, 8 + slot * span + (r - 0.5) * span * 0.6, i * 4, spell.id, actor, spell)
    end)
  end

  @doc "Blows up every blast rune `owner` left, as a cast clients replay."
  def detonate_runes(state, owner) do
    {mine, others} = Enum.split_with(state.runes, &(&1.owner == owner))
    spell = %{radius: 13, damage: 60, knock: 62}

    state
    |> Map.put(:runes, others)
    |> Units.log("BOOM!")
    |> run(owner, "blastrune", nil, fn fx ->
      Enum.reduce(mine, %{fx | shake: true}, fn rune, fx ->
        fx = add_segment(fx, [{rune.x, rune.y}, {rune.x, rune.y}], 0, "blastrune", 13, true)
        blast(%{fx | at: 1}, owner, {rune.x, rune.y}, spell)
      end)
    end)
  end

  @doc "Drops one meteor at column `x`, recording its flight from step `start`."
  def meteor(fx, x, start, spell_id, actor \\ nil, spell \\ nil) do
    meteor = spell || %{gravity: 1.0, wind: 1.0, speed: 1.0, radius: 5, damage: 16, knock: 22}
    {path, impact} = Physics.fly(fx.state, {x, -4.0}, {fx.state.wind * 1.5, 8.0}, meteor, nil)
    hit? = elem(impact, 0) in [:terrain, :unit]
    fx = add_segment(fx, path, start, spell_id, if(hit?, do: meteor.radius, else: 0), hit?)
    if hit?, do: blast(fx, actor, elem(impact, 1), meteor), else: fx
  end

  # Little bombs flung out of an impact, each with its own blast.
  defp scatter(fx, actor, spell, {x, y}, steps, speeds, lift) do
    Enum.reduce(speeds, fx, fn vx, fx ->
      {path, impact} = Physics.fly(fx.state, {x, y - 1.5}, {vx * 1.0, lift}, spell, nil)
      hit? = elem(impact, 0) in [:terrain, :unit]
      fx = add_segment(fx, path, steps, spell.id, if(hit?, do: spell.radius, else: 0), hit?)
      if hit?, do: blast(fx, actor, elem(impact, 1), spell), else: fx
    end)
  end

  @hops 12
  @hop {5, 7}
  @leap {11, 5}

  defp hop(fx, actor, spell, hare, dir, start, n, turned?) do
    pos = {hare.x + 0.5, hare.y * 1.0}

    cond do
      hare.y >= fx.state.water_level ->
        %{fx | state: Units.log(fx.state, "…and the crab swims off.")}

      n >= @hops or prey?(fx.state, actor, n, pos) ->
        fx = add_segment(fx, [pos, pos], start, spell.id, spell.radius, true)
        blast(fx, actor, pos, spell)

      true ->
        case leap(fx.state, hare, dir) do
          {:ok, landed, path} ->
            path = Enum.map(path, fn {x, y} -> {x + 0.5, y} end)

            # It goes off on the first wizard it meets, even mid-hop.
            case Enum.find_index(path, &prey?(fx.state, actor, n, &1)) do
              nil ->
                fx = add_segment(fx, path, start, spell.id, 0, true)
                hop(fx, actor, spell, landed, dir, start + length(path) - 1, n + 1, turned?)

              i ->
                path = Enum.take(path, i + 1)
                fx = add_segment(fx, path, start, spell.id, spell.radius, true)
                blast(fx, actor, List.last(path), spell)
            end

          :blocked when not turned? ->
            hop(fx, actor, spell, hare, -dir, start, n + 1, true)

          :blocked ->
            hop(fx, actor, spell, hare, dir, start, @hops, true)
        end
    end
  end

  # A wizard close enough for the hare to go off on; its own caster only once it is clear.
  defp prey?(state, actor, n, {x, y}) do
    Enum.any?(Map.values(state.units), fn unit ->
      unit.kind == :wizard and Units.alive_unit?(unit) and (unit.id != actor or n >= 3) and
        abs(unit.x + 0.5 - x) <= 2 and y >= unit.y - 4 and y <= unit.y + 1.5
    end)
  end

  # A low hop, or a high leap when a wall is in the way.
  defp leap(state, hare, dir) do
    Enum.find_value([@hop, @leap], :blocked, fn jump ->
      {flown, path} = Physics.jump(state, hare, jump, dir)
      {landed, _} = Units.settle(state, flown)

      if landed.x != hare.x do
        path = if landed.y != flown.y, do: path ++ [{landed.x * 1.0, landed.y * 1.0}], else: path
        {:ok, landed, path}
      end
    end)
  end

  defp slam(fx, actor, spell, pos, start, left, ignore \\ nil)
  defp slam(fx, _actor, _spell, _pos, _start, 0, _ignore), do: fx

  defp slam(fx, actor, spell, pos, start, left, ignore) do
    {path, {kind, impact}} =
      Physics.fly(fx.state, pos, {0.0, 34.0}, %{gravity: 1.0, wind: 0.0}, ignore)

    hit? = kind in [:terrain, :unit]
    fx = add_segment(fx, path, start, spell.id, if(hit?, do: spell.radius, else: 0), hit?)

    if hit? do
      fx = blast(fx, actor, impact, spell)
      {x, y} = impact
      # A wizard it lands on is flattened once; the anvil carries on down through them.
      struck = if kind == :unit, do: Physics.unit_hit(fx.state, x, y, fn _ -> true end)
      slam(fx, actor, spell, {x, y - 0.5}, start + length(path) - 1, left - 1, struck)
    else
      fx
    end
  end

  defp bounce(fx, actor, spell, origin, velocity, ignore, start, left) do
    {path, {kind, pos}} = Physics.fly(fx.state, origin, velocity, spell, ignore)
    steps = length(path)
    {vx, vy} = exit_velocity(path, velocity)
    speed = :math.sqrt(vx * vx + vy * vy)

    if kind == :terrain and left > 0 and speed > 10 do
      fx = add_segment(fx, path, start, spell.id, 0, true)
      back = Enum.at(path, -2, origin)

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
      fx = add_segment(fx, path, start, spell.id, if(hit?, do: spell.radius, else: 0), hit?)
      if hit?, do: blast(fx, actor, pos, spell), else: fizzle(fx)
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
