defmodule Flamingo.GameModes.Spellslingers.Terrain do
  @moduledoc false

  use Flamingo.GameModes.Spellslingers.Rules

  alias Flamingo.GameModes.Spellslingers.Units

  def clamp(value, low, high), do: value |> max(low) |> min(high)

  # A target inside rock moves up to the open air above it.
  def surface_above(state, x, y) do
    if y > 1 and solid?(state.terrain, floor(x), floor(y)),
      do: surface_above(state, x, y - 1),
      else: {x, y}
  end

  @doc false
  def solid?(terrain, x, y) when x >= 0 and x < @width and y >= 0 and y < @height,
    do: :binary.at(terrain, y * @width + x) == 1

  def solid?(_terrain, _x, _y), do: false

  def carve(state, circles), do: paint(state, circles, 0)
  def fill(state, circles), do: paint(state, circles, 1)

  defp paint(state, circles, value) do
    occupied =
      if value == 1,
        do:
          for(
            {_, u} <- state.units,
            Units.alive_unit?(u),
            dy <- 0..(Units.unit_height(u) - 1),
            into: MapSet.new(),
            do: {u.x, u.y - dy}
          ),
        else: MapSet.new()

    {x0, x1, y0, y1} =
      Enum.reduce(circles, {@width, 0, @height, 0}, fn {cx, cy, r}, {a, b, c, d} ->
        {min(a, floor(cx - r)), max(b, ceil(cx + r)), min(c, floor(cy - r)), max(d, ceil(cy + r))}
      end)

    terrain =
      for y <- 0..(@height - 1), x <- 0..(@width - 1), into: <<>> do
        current = :binary.at(state.terrain, y * @width + x)

        inside? =
          x >= x0 and x <= x1 and y >= y0 and y <= y1 and
            Enum.any?(circles, fn {cx, cy, r} ->
              (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r
            end)

        if inside? and not MapSet.member?(occupied, {x, y}), do: <<value>>, else: <<current>>
      end

    %{state | terrain: terrain}
  end

  def encode_terrain(terrain),
    do: for(<<cell <- terrain>>, into: <<>>, do: <<cell::1>>) |> Base.encode64()

  def generate_terrain(map_id, rng) do
    {shape, rng} = map_shape(map_id, rng)

    terrain =
      for y <- 0..(@height - 1), x <- 0..(@width - 1), into: <<>> do
        if shape.(x + 0.5, y + 0.5 - @sky), do: <<1>>, else: <<0>>
      end

    {terrain, rng}
  end

  defp map_shape("isles", rng) do
    {waves, rng} =
      Enum.map_reduce(1..3, rng, fn i, rng ->
        {phase, rng} = :rand.uniform_s(rng)
        {freq, rng} = :rand.uniform_s(rng)
        {{phase * 2 * :math.pi(), (0.012 + freq * 0.02) * i, 13 / i}, rng}
      end)

    {islands, rng} =
      Enum.map_reduce(1..4, rng, fn i, rng ->
        {jx, rng} = :rand.uniform_s(rng)
        {jy, rng} = :rand.uniform_s(rng)
        {{@width * i / 5 + (jx - 0.5) * 24, 22 + jy * 16, 9 + jy * 6, 2.6}, rng}
      end)

    {chasm, rng} = :rand.uniform_s(rng)
    chasm_x = @width * (0.35 + chasm * 0.3)

    heights =
      for x <- 0..(@width - 1) do
        wave = Enum.reduce(waves, 0, fn {p, f, a}, sum -> sum + a * :math.sin(x * f + p) end)
        edge = max(0, 14 - min(x, @width - 1 - x)) * 3.5
        gap = max(0, 9 - abs(x - chasm_x)) * 2.6
        64 + wave + edge + gap
      end
      |> List.to_tuple()

    shape = fn x, y ->
      y >= elem(heights, floor(x)) or
        Enum.any?(islands, fn {ix, iy, w, h} ->
          dx = (x - ix) / w
          dy = (y - iy) / h
          (y >= iy and dx * dx + dy * dy / 4 <= 1) or (y < iy and y >= iy - 1 and abs(dx) <= 1)
        end)
    end

    {shape, rng}
  end

  defp map_shape("flamingo", rng) do
    neck = [{78, 46}, {66, 38}, {68, 28}, {62, 18}]
    bent_leg = [{112, 60}, {122, 72}, {110, 80}]

    shape = fn x, y ->
      body = ((x - 104) / 32) ** 2 + ((y - 50) / 12) ** 2 <= 1
      tail = in_triangle?({x, y}, {128, 42}, {150, 32}, {136, 56})
      head = (x - 58) ** 2 + (y - 15) ** 2 <= 36
      eye = (x - 56.5) ** 2 + (y - 13.5) ** 2 <= 1.6
      beak = in_triangle?({x, y}, {53, 12}, {42, 22}, {54, 19})
      neck? = near_polyline?({x, y}, neck, 3.6)
      leg = near_polyline?({x, y}, [{100, 58}, {100, 100}], 1.6)
      bent = near_polyline?({x, y}, bent_leg, 1.5)

      sand =
        (x < 34 or x > 166) and
          y >= 80 + 3 * :math.sin(x * 0.3) + max(0, min(x, 200 - x) - 22) * 1.4

      ledges = ellipse?(x, y, {24, 46}, 12, 2.5) or ellipse?(x, y, {176, 36}, 12, 2.5)

      (body or tail or head or beak or neck? or leg or bent or sand or ledges) and not eye
    end

    {centred(shape), rng}
  end

  defp map_shape("castles", rng) do
    tower = fn x, y, x0 ->
      inside = x >= x0 and x < x0 + 26
      wall = inside and y >= 34
      battlement = inside and y >= 29 and y < 34 and rem(floor((x - x0) / 4), 2) == 0
      window = x >= x0 + 9 and x < x0 + 17 and y >= 46 and y < 56
      door = x >= x0 + 10 and x < x0 + 16 and y >= 74 and y < 82
      (wall or battlement) and not window and not door
    end

    shape = fn x, y ->
      ground = abs(x - 100) > 26 and y >= 82 + 2 * :math.sin(x * 0.15)
      sag = 4 * :math.sin(:math.pi() * (x - 66) / 68)
      bridge = x >= 66 and x <= 134 and y >= 44 + sag and y <= 47 + sag
      rock = ellipse?(x, y, {100, 24}, 7, 3)
      ground or bridge or rock or tower.(x, y, 12) or tower.(x, y, 162)
    end

    {centred(shape), rng}
  end

  defp map_shape("cavern", rng) do
    {p1, rng} = :rand.uniform_s(rng)
    {p2, rng} = :rand.uniform_s(rng)

    {stalactites, rng} =
      Enum.map_reduce(1..(div(@width, 25) - 1), rng, fn i, rng ->
        {j, rng} = :rand.uniform_s(rng)
        {{i * 25 + (j - 0.5) * 12, 10 + j * 16}, rng}
      end)

    {pillar, rng} = :rand.uniform_s(rng)
    pillar_x = @width * (0.35 + pillar * 0.3)

    shape = fn x, y ->
      ceiling = y <= 9 + 4 * :math.sin(x * 0.07 + p1 * 6)
      floor_y = 74 + 8 * :math.sin(x * 0.05 + p2 * 6) + 4 * :math.sin(x * 0.13)
      floor? = y >= floor_y and x > 6 and x < @width - 6
      walls = x < 4 or x > @width - 4

      drip =
        Enum.any?(stalactites, fn {sx, len} ->
          y <= 9 + len and abs(x - sx) <= (9 + len - y) * 0.22
        end)

      column = abs(x - pillar_x) <= 4 + 2 * :math.sin(y * 0.3)

      ledges =
        ellipse?(x, y, {@width * 0.2, 44}, 13, 2.5) or ellipse?(x, y, {@width * 0.8, 40}, 13, 2.5)

      ceiling or floor? or walls or drip or column or ledges
    end

    {shape, rng}
  end

  defp map_shape("archipelago", rng) do
    {islands, rng} =
      Enum.map_reduce(0..9, rng, fn i, rng ->
        {a, rng} = :rand.uniform_s(rng)
        {b, rng} = :rand.uniform_s(rng)
        {{14 + i * (@width - 28) / 9 + (a - 0.5) * 8, 48 + b * 30, 8 + a * 6}, rng}
      end)

    {rocks, rng} =
      Enum.map_reduce(1..6, rng, fn i, rng ->
        {a, rng} = :rand.uniform_s(rng)
        {{i * @width / 7 + (a - 0.5) * 16, 18 + a * 18}, rng}
      end)

    shape = fn x, y ->
      Enum.any?(islands, fn {cx, top, w} ->
        abs(x - cx) <= w and y >= top + ((x - cx) / w) ** 2 * 12
      end) or Enum.any?(rocks, fn {cx, cy} -> ellipse?(x, y, {cx, cy}, 6, 2.2) end)
    end

    {shape, rng}
  end

  defp centred(shape), do: fn x, y -> shape.(x - @margin, y) end

  defp ellipse?(x, y, {cx, cy}, rx, ry), do: ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1

  defp in_triangle?({px, py}, {ax, ay}, {bx, by}, {cx, cy}) do
    d1 = (px - bx) * (ay - by) - (ax - bx) * (py - by)
    d2 = (px - cx) * (by - cy) - (bx - cx) * (py - cy)
    d3 = (px - ax) * (cy - ay) - (cx - ax) * (py - ay)
    not ((d1 < 0 or d2 < 0 or d3 < 0) and (d1 > 0 or d2 > 0 or d3 > 0))
  end

  defp near_polyline?(point, points, radius) do
    points
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.any?(fn [a, b] -> segment_distance(point, a, b) <= radius end)
  end

  defp segment_distance({px, py}, {ax, ay}, {bx, by}) do
    {dx, dy} = {bx - ax, by - ay}
    t = clamp(((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy), 0, 1)
    :math.sqrt((px - ax - t * dx) ** 2 + (py - ay - t * dy) ** 2)
  end
end
