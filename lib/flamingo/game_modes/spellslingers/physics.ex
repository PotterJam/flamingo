defmodule Flamingo.GameModes.Spellslingers.Physics do
  @moduledoc false

  use Flamingo.GameModes.Spellslingers.Rules

  alias Flamingo.GameModes.Spellslingers.{Fx, Terrain, Units}

  def launch(spell, angle, power) do
    radians = angle * :math.pi() / 180
    speed = @max_speed * spell.speed * max(power, 5) / 100
    {:math.cos(radians) * speed, -:math.sin(radians) * speed}
  end

  @doc false
  def fly(state, origin, velocity, spell, ignore) do
    ax = state.wind * state.tuning.wind_accel * spell.wind
    ay = state.tuning.gravity * spell.gravity
    fly_step(state, origin, velocity, {ax, ay}, [origin], 0, ignore)
  end

  defp fly_step(_state, pos, _v, _a, path, @max_steps, _), do: {Enum.reverse(path), {:lost, pos}}

  defp fly_step(state, {x, y}, {vx, vy}, {ax, ay}, path, n, near) do
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
      {{_, _} = pos, near} -> fly_step(state, pos, {vx, vy}, {ax, ay}, [pos | path], n + 1, near)
      {kind, pos} -> {Enum.reverse([pos | path]), {kind, pos}}
    end
  end

  def unit_hit(state, px, py, considered?) do
    Enum.find_value(state.units, fn {id, unit} ->
      height = Units.hit_height(unit)

      if considered?.(id) and Units.alive_unit?(unit) and abs(px - (unit.x + 0.5)) <= 1.6 and
           py >= unit.y + 1 - height and py <= unit.y + 1.2,
         do: id
    end)
  end

  def explode(fx, actor, {x, y}, radius, damage, knock) do
    state = fx.state |> Terrain.carve([{x, y, radius}]) |> Units.destroy_crates(x, y, radius + 1)
    reach = radius + 2

    state.units
    |> Map.values()
    |> Enum.sort_by(& &1.id)
    |> Enum.reduce(%{fx | state: state}, fn unit, fx ->
      {cx, cy} = Units.center(unit)
      distance = :math.sqrt((cx - x) ** 2 + (cy - y) ** 2)

      if Units.alive_unit?(unit) and distance <= reach do
        falloff = max(0.35, 1 - distance / (reach + 1))
        fx = %{fx | state: Units.damage(fx.state, unit.id, round(damage * falloff), actor)}
        Fx.add_impulse(fx, unit.id, cx - x, cy - y, distance, knock * falloff)
      else
        fx
      end
    end)
  end

  def apply_knocks(state, impulses) do
    impulses
    |> Enum.sort()
    |> Enum.reduce({state, []}, fn {id, {vx, vy}}, {state, knocks} ->
      unit = state.units[id]
      # A ward that survived the hit keeps its wizard mostly planted.
      {vx, vy} = if unit && Map.get(unit, :ward, 0) > 0, do: {vx * 0.3, vy * 0.3}, else: {vx, vy}

      if (unit && Units.alive_unit?(unit)) and :math.sqrt(vx * vx + vy * vy) >= 6 do
        {unit, path} =
          knock_flight(state, unit, {Terrain.clamp(vx, -65, 65), Terrain.clamp(vy, -65, 65)})

        {Units.put_unit(state, unit), [%{id: id, path: path} | knocks]}
      else
        {state, knocks}
      end
    end)
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
          px < 0 or px >= @width -> {:halt, {:gone, {px, py}}}
          py >= state.water_level -> {:halt, {:gone, {px, py}}}
          Units.blocked?(state, unit, floor(px), floor(py)) -> {:halt, {:land, {x, y}}}
          true -> {:cont, {px, py}}
        end
      end)

    case result do
      {:gone, {px, py}} ->
        unit = %{unit | x: px |> floor() |> Terrain.clamp(0, @width - 1), y: state.water_level}
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
      | x: floor(x) |> Terrain.clamp(0, @width - 1),
        y: floor(y) |> Terrain.clamp(0, @height - 1)
    }

    {unit, Enum.reverse([{unit.x * 1.0, unit.y * 1.0} | path])}
  end
end
