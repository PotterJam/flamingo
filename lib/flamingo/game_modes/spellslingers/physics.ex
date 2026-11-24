defmodule Flamingo.GameModes.Spellslingers.Physics do
  @moduledoc false

  use Flamingo.GameModes.Spellslingers.Rules

  alias Flamingo.GameModes.Spellslingers.{Crates, Fx, Terrain, Units}

  def launch(spell, angle, power) do
    radians = angle * :math.pi() / 180
    speed = @max_speed * spell.speed * max(power, 5) / 100
    {:math.cos(radians) * speed, -:math.sin(radians) * speed}
  end

  @doc """
  Flies a projectile until it hits something. `steer`, when given, turns the
  velocity each step: `steer.({x, y}, {vx, vy})` returns the new velocity.
  """
  def fly(state, origin, velocity, spell, ignore, steer \\ nil) do
    ax = state.wind * state.tuning.wind_accel * spell.wind
    ay = state.tuning.gravity * spell.gravity
    fly_step(state, origin, velocity, {ax, ay, steer}, [origin], 0, ignore)
  end

  defp fly_step(_state, pos, _v, _a, path, @max_steps, _), do: {Enum.reverse(path), {:lost, pos}}

  defp fly_step(state, {x, y}, {vx, vy}, {ax, ay, steer} = accel, path, n, near) do
    {vx, vy} = if steer, do: steer.({x, y}, {vx, vy}), else: {vx, vy}
    vx = vx + ax * @dt
    vy = vy + ay * @dt
    # Sub-steps keep fast bolts from tunnelling through thin walls.
    substeps = max(1, ceil(:math.sqrt(vx * vx + vy * vy) * @dt / 0.5))

    result =
      Enum.reduce_while(1..substeps, {{x, y}, near}, fn i, {_, near} ->
        px = x + vx * @dt * i / substeps
        py = y + vy * @dt * i / substeps
        near = if near && unit_hit(state, px, py, &(&1 == near)), do: near, else: nil

        cond do
          px < 0 or px >= @width -> {:halt, {:out, {px, py}}}
          py >= state.water_level -> {:halt, {:water, {px, py}}}
          Terrain.solid?(state.terrain, floor(px), floor(py)) -> {:halt, {:terrain, {px, py}}}
          unit_hit(state, px, py, &(&1 != near)) -> {:halt, {:unit, {px, py}}}
          true -> {:cont, {{px, py}, near}}
        end
      end)

    case result do
      {{_, _} = pos, near} -> fly_step(state, pos, {vx, vy}, accel, [pos | path], n + 1, near)
      {kind, pos} -> {Enum.reverse([pos | path]), {kind, pos}}
    end
  end

  def unit_hit(state, px, py, considered?) do
    Enum.find_value(state.units, fn {id, unit} ->
      if considered?.(id) and Units.alive_unit?(unit) and Units.distance_to(unit, {px, py}) == 0,
        do: id
    end)
  end

  # A blast reaches whatever it comes near as drawn, so it catches a flamingo's head as
  # well as its legs. Falloff counts from a cell inside the unit, which keeps the damage
  # near what it was when blasts measured from the unit's middle.
  def explode(fx, actor, {x, y}, radius, damage, knock) do
    state = fx.state |> Terrain.carve([{x, y, radius}]) |> Crates.destroy_crates(x, y, radius + 1)
    reach = radius + 1

    state.units
    |> Map.values()
    |> Enum.sort_by(& &1.id)
    |> Enum.reduce(%{fx | state: state}, fn unit, fx ->
      {cx, cy} = Units.center(unit)
      distance = Units.distance_to(unit, {x, y})

      if Units.alive_unit?(unit) and distance <= reach do
        falloff = max(0.35, 1 - (distance + 1) / (reach + 2))
        fx = Fx.hit(fx, unit.id, round(damage * falloff), actor)
        away = :math.sqrt((cx - x) ** 2 + (cy - y) ** 2)
        Fx.add_impulse(fx, unit.id, cx - x, cy - y, away, knock * falloff)
      else
        fx
      end
    end)
  end

  @egg_radius 1.0
  @egg_steps 200

  def egg_radius, do: @egg_radius

  @doc """
  Lets an egg go at `pos` (its middle) with the given velocity: it falls, bounces off
  the land and rolls down slopes until it comes to rest. Flamingos don't stop it.
  Returns {:rest, pos, path}, or {:sea, pos, path} when it ends up in the water or off
  the map's side.
  """
  def roll_egg(state, pos, velocity) do
    egg_step(state, pos, velocity, [pos], 0, 0)
  end

  defp egg_step(_state, pos, _v, path, @egg_steps, _still), do: {:rest, pos, Enum.reverse(path)}

  defp egg_step(state, {x, y}, {vx, vy}, path, n, still) do
    g = state.tuning.gravity
    vy = vy + g * @dt
    substeps = max(1, ceil(:math.sqrt(vx * vx + vy * vy) * @dt / 0.25))

    {pos, v, normal} =
      Enum.reduce(1..substeps, {{x, y}, {vx, vy}, nil}, fn _, {{px, py}, {vx, vy}, touched} ->
        next = {px + vx * @dt / substeps, py + vy * @dt / substeps}

        case egg_contact(state, next) do
          nil ->
            {next, {vx, vy}, touched}

          {{nx, ny} = normal, depth} ->
            # A hard landing bounces; a soft one just stops going into the land.
            vn = vx * nx + vy * ny
            bounce = if vn < -6, do: 0.35, else: 0.0

            v =
              if vn < 0,
                do: {vx - (1 + bounce) * vn * nx, vy - (1 + bounce) * vn * ny},
                else: {vx, vy}

            {{elem(next, 0) + nx * depth, elem(next, 1) + ny * depth}, v, normal}
        end
      end)

    # On the ground it rolls: gravity along the slope speeds it up and the ground slows it
    # a little, so it rolls down a steep slope but stops on a gentle one.
    v = if normal, do: roll_friction(v, normal, g), else: v
    {vx, vy} = v
    still = if normal && vx * vx + vy * vy < 0.25, do: still + 1, else: 0
    {px, py} = pos
    path = [pos | path]

    cond do
      py >= state.water_level or px < 0 or px >= @width -> {:sea, pos, Enum.reverse(path)}
      still >= 4 -> {:rest, pos, Enum.reverse(path)}
      true -> egg_step(state, pos, v, path, n + 1, still)
    end
  end

  defp roll_friction({vx, vy}, {nx, ny}, g) do
    vn = vx * nx + vy * ny
    {tx, ty} = {vx - vn * nx, vy - vn * ny}
    speed = :math.sqrt(tx * tx + ty * ty)
    slow = if speed > 0, do: max(speed * (1 - 1.5 * @dt) - g * 0.2 * @dt, 0) / speed, else: 0
    {vn * nx + tx * slow, vn * ny + ty * slow}
  end

  # How the egg, a circle at `pos`, overlaps the land: the direction out of it and how
  # deep it is in, or nil when it touches nothing. The direction comes from the land
  # around the egg, not the cell it touches, so it rolls over the smooth ground clients
  # draw instead of resting on each step of the cells, and tips off a ledge's edge.
  defp egg_contact(state, pos) do
    with {normal, depth} <- egg_overlap(state, pos),
         do: {land_normal(state, pos) || normal, depth}
  end

  defp land_normal(state, {x, y}) do
    reach = 2.5

    {sx, sy} =
      for cx <- floor(x - reach)..floor(x + reach),
          cy <- floor(y - reach)..floor(y + reach),
          (x - cx - 0.5) ** 2 + (y - cy - 0.5) ** 2 <= reach * reach,
          Terrain.solid?(state.terrain, cx, cy),
          reduce: {0.0, 0.0},
          do: ({sx, sy} -> {sx + x - cx - 0.5, sy + y - cy - 0.5})

    length = :math.sqrt(sx * sx + sy * sy)
    if length > 0.5, do: {sx / length, sy / length}
  end

  defp egg_overlap(state, {x, y}) do
    r = @egg_radius

    pushes =
      for cx <- floor(x - r)..floor(x + r),
          cy <- floor(y - r)..floor(y + r),
          Terrain.solid?(state.terrain, cx, cy),
          {qx, qy} = {clamp(x, cx, cx + 1), clamp(y, cy, cy + 1)},
          d = :math.sqrt((x - qx) ** 2 + (y - qy) ** 2),
          d < r,
          do:
            if(d == 0,
              do: {0.0, -r, r},
              else: {(x - qx) / d * (r - d), (y - qy) / d * (r - d), r - d}
            )

    case pushes do
      [] ->
        nil

      _ ->
        {sx, sy} =
          Enum.reduce(pushes, {0.0, 0.0}, fn {px, py, _}, {sx, sy} -> {sx + px, sy + py} end)

        length = :math.sqrt(sx * sx + sy * sy)
        normal = if length > 0, do: {sx / length, sy / length}, else: {0.0, -1.0}
        {normal, pushes |> Enum.map(&elem(&1, 2)) |> Enum.max()}
    end
  end

  def apply_knocks(state, impulses) do
    impulses
    |> Enum.sort()
    |> Enum.reduce({state, []}, fn {id, {vx, vy}}, {state, knocks} ->
      unit = state.units[id]

      if (unit && Units.alive_unit?(unit)) and :math.sqrt(vx * vx + vy * vy) >= 6 do
        {unit, path} =
          knock_flight(state, unit, {clamp(vx, -65, 65), clamp(vy, -65, 65)})

        {Units.put_unit(state, unit), [%{id: id, path: path} | knocks]}
      else
        {state, knocks}
      end
    end)
  end

  @doc """
  Flies a wizard through a jump of the given {apex height, flat distance} toward
  `dir` and returns {landed unit, path}. The arc keeps its shape whatever the
  gravity is tuned to.
  """
  def jump(state, unit, {height, distance}, dir) do
    g = state.tuning.gravity
    vy = :math.sqrt(2 * g * height)
    start = {unit.x + 0.5, unit.y + 0.5}
    velocity = {dir * distance * g / (2 * vy), -vy}
    jump_step(state, unit, start, velocity, [{unit.x * 1.0, unit.y * 1.0}], 0)
  end

  defp jump_step(state, unit, pos, _v, path, 300), do: land(state, unit, pos, path)

  # Unlike knockback, a wall met on the way up slides the jumper up its face, so a
  # jump from right beside a cliff still climbs it. The map's edges count as walls.
  defp jump_step(state, unit, {x, y}, {vx, vy}, path, n) do
    vy = vy + state.tuning.gravity * @dt
    substeps = max(1, ceil(max(abs(vx), abs(vy)) * @dt / 0.6))

    result =
      Enum.reduce_while(1..substeps, {x, y}, fn _, {cx, cy} ->
        px = cx + vx * @dt / substeps
        py = cy + vy * @dt / substeps

        cond do
          py >= state.water_level -> {:halt, {:gone, {px, py}}}
          not Units.blocked?(state, unit, floor(px), floor(py)) -> {:cont, {px, py}}
          vy < 0 and not Units.blocked?(state, unit, floor(cx), floor(py)) -> {:cont, {cx, py}}
          true -> {:halt, {:land, {cx, cy}}}
        end
      end)

    case result do
      {:gone, {px, py}} ->
        unit = %{unit | x: px |> floor() |> clamp(0, @width - 1), y: state.water_level}
        {unit, Enum.reverse([{px - 0.5, py - 0.5} | path])}

      {:land, pos} ->
        land(state, unit, pos, path)

      {px, py} ->
        jump_step(state, unit, {px, py}, {vx, vy}, [{px - 0.5, py - 0.5} | path], n + 1)
    end
  end

  defp knock_flight(state, unit, velocity) do
    start = {unit.x + 0.5, unit.y + 0.5}
    knock_step(state, unit, start, velocity, [{unit.x * 1.0, unit.y * 1.0}], 0)
  end

  defp knock_step(state, unit, pos, _v, path, 300), do: land(state, unit, pos, path)

  defp knock_step(state, unit, {x, y}, {vx, vy}, path, n) do
    vy = vy + state.tuning.gravity * @dt
    substeps = max(1, ceil(max(abs(vx), abs(vy)) * @dt / 0.6))

    result =
      Enum.reduce_while(1..substeps, {x, y}, fn i, _ ->
        px = x + vx * @dt * i / substeps
        py = y + vy * @dt * i / substeps

        cond do
          py >= state.water_level ->
            {:halt, {:gone, {px, py}}}

          # Walking stops at the map's edges, but a knock carries a unit on past
          # them, with nothing below until the sea.
          px >= 0 and px < @width and Units.blocked?(state, unit, floor(px), floor(py)) ->
            {:halt, {:land, {x, y}}}

          true ->
            {:cont, {px, py}}
        end
      end)

    case result do
      {:gone, {px, py}} ->
        unit = %{unit | x: floor(px), y: state.water_level}
        {unit, Enum.reverse([{px - 0.5, py - 0.5} | path])}

      {:land, pos} ->
        land(state, unit, pos, path)

      {px, py} ->
        knock_step(state, unit, {px, py}, {vx, vy}, [{px - 0.5, py - 0.5} | path], n + 1)
    end
  end

  defp land(_state, unit, {x, y}, path) do
    unit = %{
      unit
      | x: floor(x),
        y: floor(y) |> clamp(0, @height - 1)
    }

    {unit, Enum.reverse([{unit.x * 1.0, unit.y * 1.0} | path])}
  end
end
