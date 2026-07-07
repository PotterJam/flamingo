defmodule Flamingo.DrawingShare do
  @moduledoc """
  Encodes a finished drawing into a URL fragment.

  Raw draw events are far too heavy to put in a link (hundreds of KB), so
  drawings are reduced to compact ops the moment a turn completes:

    * pen strokes become polylines simplified with Ramer-Douglas-Peucker
      under a total point budget - the tolerance escalates until the whole
      drawing fits, so busy sketches trade fidelity for size instead of
      producing huge payloads;
    * polyline coordinates are delta-encoded integers, which keeps the
      numbers small and compresses well;
    * fills and clears are single ops.

  The payload is JSON-encoded, zlib-compressed and base64url'd, prefixed
  with "z" so clients can tell it apart from legacy uncompressed links.
  A typical drawing encodes to roughly 1KB.
  """

  @type drawing :: %{
          required(:drawer_name) => String.t(),
          required(:word) => String.t(),
          required(:round_number) => pos_integer(),
          required(:ops) => list(list())
        }

  @version_prefix "z"

  # Total polyline points allowed across the whole drawing. RDP tolerance
  # steps up through @epsilon_steps until the drawing fits (or the roughest
  # tolerance is reached - e.g. hundreds of separate dots can't be reduced
  # below two points per stroke, so the budget is best-effort).
  @max_total_points 200
  @epsilon_steps [1.5, 3, 6, 12, 24, 48, 96]

  def encode(drawing) do
    payload = %{
      "v" => 2,
      "n" => Map.fetch!(drawing, :drawer_name),
      "w" => Map.fetch!(drawing, :word),
      "r" => Map.fetch!(drawing, :round_number),
      "o" => Map.fetch!(drawing, :ops)
    }

    compressed =
      payload
      |> Jason.encode!()
      |> :zlib.compress()
      |> Base.url_encode64(padding: false)

    @version_prefix <> compressed
  end

  def decode(@version_prefix <> encoded) do
    with {:ok, compressed} <- Base.url_decode64(encoded, padding: false),
         {:ok, json} <- safe_uncompress(compressed),
         {:ok, payload} <- Jason.decode(json),
         {:ok, drawing} <- normalize_v2(payload) do
      {:ok, drawing}
    else
      _ -> {:error, :invalid_drawing}
    end
  end

  # Legacy links: plain base64url JSON with the full event list.
  def decode(encoded) when is_binary(encoded) do
    with {:ok, json} <- Base.url_decode64(encoded, padding: false),
         {:ok, payload} <- Jason.decode(json),
         {:ok, drawing} <- normalize_v1(payload) do
      {:ok, drawing}
    else
      _ -> {:error, :invalid_drawing}
    end
  end

  def decode(_encoded), do: {:error, :invalid_drawing}

  @doc """
  Collapses raw draw events into compact ops:

    * `["p", color, line_width, [x0, y0, dx1, dy1, ...]]` - a simplified,
      delta-encoded pen stroke polyline
    * `["f", color, x, y]` - a flood fill
    * `["c"]` - a canvas clear
  """
  def compact_ops(events) do
    raw_ops = collect_ops(events)

    epsilon = choose_epsilon(raw_ops)

    Enum.map(raw_ops, fn
      {:stroke, color, width, points} ->
        ["p", color, width, points |> simplify(epsilon) |> delta_encode()]

      {:fill, color, x, y} ->
        ["f", color, x, y]

      :clear ->
        ["c"]
    end)
  end

  @doc """
  Expands compact ops back into renderable draw events.
  """
  def expand_ops(ops) do
    Enum.flat_map(ops, &expand_op/1)
  end

  defp collect_ops(events) do
    {ops, stroke} = Enum.reduce(events, {[], nil}, &collect_event/2)

    [flush_stroke(stroke) | ops]
    |> Enum.reject(&is_nil/1)
    |> Enum.reverse()
  end

  defp collect_event(%{"event_type" => "start"} = event, {ops, stroke}) do
    point = {round_coord(event["x"]), round_coord(event["y"])}
    {[flush_stroke(stroke) | ops], {event["color"], event["line_width"], [point]}}
  end

  defp collect_event(%{"event_type" => type} = event, {ops, stroke})
       when type in ["draw", "end"] do
    point = {round_coord(event["end_x"]), round_coord(event["end_y"])}

    case stroke do
      nil ->
        start = {round_coord(event["start_x"]), round_coord(event["start_y"])}
        {ops, {event["color"], event["line_width"], [point, start]}}

      {color, width, [^point | _] = points} ->
        {ops, {color, width, points}}

      {color, width, points} ->
        {ops, {color, width, [point | points]}}
    end
  end

  defp collect_event(%{"event_type" => "fill"} = event, {ops, stroke}) do
    op = {:fill, event["color"], round_coord(event["x"]), round_coord(event["y"])}
    {[op, flush_stroke(stroke) | ops], nil}
  end

  defp collect_event(%{"event_type" => "clear"}, {ops, stroke}) do
    {[:clear, flush_stroke(stroke) | ops], nil}
  end

  defp collect_event(_event, acc), do: acc

  defp flush_stroke(nil), do: nil

  defp flush_stroke({color, width, points}) do
    {:stroke, color, width, Enum.reverse(points)}
  end

  defp choose_epsilon(raw_ops) do
    point_lists = for {:stroke, _color, _width, points} <- raw_ops, do: points

    Enum.find(@epsilon_steps, List.last(@epsilon_steps), fn epsilon ->
      total =
        point_lists
        |> Enum.map(&length(simplify(&1, epsilon)))
        |> Enum.sum()

      total <= @max_total_points
    end)
  end

  # Ramer-Douglas-Peucker: keeps the points that define the stroke's shape
  # (corners, curves) and drops everything within `epsilon` px of the
  # simplified line.
  defp simplify(points, _epsilon) when length(points) <= 2, do: points

  defp simplify(points, epsilon) do
    first = List.first(points)
    last = List.last(points)

    {max_distance, max_index} =
      points
      |> Enum.with_index()
      |> Enum.reduce({0.0, 0}, fn {point, index}, {best_distance, best_index} ->
        distance = perpendicular_distance(point, first, last)

        if distance > best_distance,
          do: {distance, index},
          else: {best_distance, best_index}
      end)

    if max_distance > epsilon do
      {left, right} = Enum.split(points, max_index + 1)
      simplify(left, epsilon) ++ tl(simplify([Enum.at(points, max_index) | right], epsilon))
    else
      [first, last]
    end
  end

  defp perpendicular_distance({px, py}, {x1, y1} = first, {x2, y2} = last) do
    if first == last do
      distance({px, py}, first)
    else
      dx = x2 - x1
      dy = y2 - y1
      abs(dy * px - dx * py + x2 * y1 - y2 * x1) / :math.sqrt(dx * dx + dy * dy)
    end
  end

  defp distance({x1, y1}, {x2, y2}) do
    :math.sqrt((x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2))
  end

  defp delta_encode([{x0, y0} | rest]) do
    {deltas, _last} =
      Enum.map_reduce(rest, {x0, y0}, fn {x, y}, {prev_x, prev_y} ->
        {[x - prev_x, y - prev_y], {x, y}}
      end)

    [x0, y0 | List.flatten(deltas)]
  end

  defp delta_encode([]), do: []

  defp round_coord(value) when is_number(value), do: round(value)
  defp round_coord(_value), do: 0

  defp expand_op(["p", color, width, [x0, y0 | deltas]]) do
    start = %{
      "event_type" => "start",
      "x" => x0,
      "y" => y0,
      "color" => color,
      "line_width" => width
    }

    {segments, _last} =
      deltas
      |> Enum.chunk_every(2)
      |> Enum.map_reduce({x0, y0}, fn [dx, dy], {prev_x, prev_y} ->
        x = prev_x + dx
        y = prev_y + dy

        segment = %{
          "event_type" => "draw",
          "start_x" => prev_x,
          "start_y" => prev_y,
          "end_x" => x,
          "end_y" => y,
          "color" => color,
          "line_width" => width
        }

        {segment, {x, y}}
      end)

    [start | segments]
  end

  defp expand_op(["f", color, x, y]) do
    [%{"event_type" => "fill", "x" => x, "y" => y, "color" => color}]
  end

  defp expand_op(["c"]) do
    [%{"event_type" => "clear"}]
  end

  defp expand_op(_op), do: []

  defp safe_uncompress(compressed) do
    {:ok, :zlib.uncompress(compressed)}
  rescue
    _error -> {:error, :invalid_drawing}
  end

  defp normalize_v2(%{"v" => 2, "n" => name, "w" => word, "r" => round_number, "o" => ops})
       when is_binary(name) and is_binary(word) and is_integer(round_number) and
              round_number > 0 and is_list(ops) do
    if Enum.all?(ops, &valid_op?/1) do
      {:ok,
       %{
         drawer_name: name,
         word: word,
         round_number: round_number,
         events: expand_ops(ops)
       }}
    else
      {:error, :invalid_drawing}
    end
  end

  defp normalize_v2(_payload), do: {:error, :invalid_drawing}

  defp valid_op?(["p", color, width, points]) when is_binary(color) and is_number(width) do
    is_list(points) and rem(length(points), 2) == 0 and points != [] and
      Enum.all?(points, &is_number/1)
  end

  defp valid_op?(["f", color, x, y]), do: is_binary(color) and is_number(x) and is_number(y)
  defp valid_op?(["c"]), do: true
  defp valid_op?(_op), do: false

  defp normalize_v1(%{
         "drawer_name" => drawer_name,
         "word" => word,
         "round_number" => round_number,
         "events" => events
       })
       when is_binary(drawer_name) and is_binary(word) and is_integer(round_number) and
              round_number > 0 and is_list(events) do
    if Enum.all?(events, &is_map/1) do
      {:ok, %{drawer_name: drawer_name, word: word, round_number: round_number, events: events}}
    else
      {:error, :invalid_drawing}
    end
  end

  defp normalize_v1(_payload), do: {:error, :invalid_drawing}
end
