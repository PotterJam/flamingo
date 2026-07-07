defmodule Flamingo.DrawingShare do
  @moduledoc """
  Encodes a finished drawing into a URL fragment.

  Raw draw events are far too heavy to put in a link (hundreds of KB), so we
  compact them first: pen strokes collapse into simplified integer polylines,
  fills and clears stay as single ops. The compact payload is then
  JSON-encoded, zlib-compressed and base64url'd, prefixed with "z" so clients
  can tell it apart from legacy uncompressed links.
  """

  @type drawing :: %{
          required(:drawer_name) => String.t(),
          required(:word) => String.t(),
          required(:round_number) => pos_integer(),
          required(:events) => list(map())
        }

  @version_prefix "z"
  # Minimum distance in px between kept polyline points; small deviations are
  # invisible at pen widths >= 6.
  @min_point_gap 2.0

  def encode(drawing) do
    payload = %{
      "v" => 2,
      "n" => Map.fetch!(drawing, :drawer_name),
      "w" => Map.fetch!(drawing, :word),
      "r" => Map.fetch!(drawing, :round_number),
      "o" => compact_ops(Map.fetch!(drawing, :events))
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

    * `["p", color, line_width, [x0, y0, x1, y1, ...]]` - a pen stroke polyline
    * `["f", color, x, y]` - a flood fill
    * `["c"]` - a canvas clear
  """
  def compact_ops(events) do
    {ops, stroke} = Enum.reduce(events, {[], nil}, &compact_event/2)

    [flush_stroke(stroke) | ops]
    |> Enum.reject(&is_nil/1)
    |> Enum.reverse()
  end

  @doc """
  Expands compact ops back into renderable draw events.
  """
  def expand_ops(ops) do
    Enum.flat_map(ops, &expand_op/1)
  end

  defp compact_event(%{"event_type" => "start"} = event, {ops, stroke}) do
    new_stroke = %{
      color: event["color"],
      width: event["line_width"],
      points: [{round_coord(event["x"]), round_coord(event["y"])}]
    }

    {[flush_stroke(stroke) | ops], new_stroke}
  end

  defp compact_event(%{"event_type" => type} = event, {ops, stroke})
       when type in ["draw", "end"] do
    point = {round_coord(event["end_x"]), round_coord(event["end_y"])}

    case stroke do
      nil ->
        start = {round_coord(event["start_x"]), round_coord(event["start_y"])}

        {ops,
         %{color: event["color"], width: event["line_width"], points: [point, start]}}

      stroke ->
        {ops, %{stroke | points: [point | stroke.points]}}
    end
  end

  defp compact_event(%{"event_type" => "fill"} = event, {ops, stroke}) do
    op = ["f", event["color"], round_coord(event["x"]), round_coord(event["y"])]
    {[op, flush_stroke(stroke) | ops], nil}
  end

  defp compact_event(%{"event_type" => "clear"}, {ops, stroke}) do
    {[["c"], flush_stroke(stroke) | ops], nil}
  end

  defp compact_event(_event, acc), do: acc

  defp flush_stroke(nil), do: nil

  defp flush_stroke(stroke) do
    points =
      stroke.points
      |> Enum.reverse()
      |> simplify_points()
      |> Enum.flat_map(fn {x, y} -> [x, y] end)

    ["p", stroke.color, stroke.width, points]
  end

  # Keeps the first point, then only points at least @min_point_gap away from
  # the previously kept one, and always the final point.
  defp simplify_points([first | rest]) do
    {kept, last_kept, last_point} =
      Enum.reduce(rest, {[first], first, first}, fn point, {kept, last_kept, _last} ->
        if distance(point, last_kept) >= @min_point_gap do
          {[point | kept], point, point}
        else
          {kept, last_kept, point}
        end
      end)

    kept = if last_point != last_kept, do: [last_point | kept], else: kept
    Enum.reverse(kept)
  end

  defp simplify_points([]), do: []

  defp distance({x1, y1}, {x2, y2}) do
    :math.sqrt((x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2))
  end

  defp round_coord(value) when is_number(value), do: round(value)
  defp round_coord(_value), do: 0

  defp expand_op(["p", color, width, [x0, y0 | rest]]) do
    start = %{
      "event_type" => "start",
      "x" => x0,
      "y" => y0,
      "color" => color,
      "line_width" => width
    }

    {segments, _last} =
      rest
      |> Enum.chunk_every(2)
      |> Enum.map_reduce({x0, y0}, fn [x, y], {prev_x, prev_y} ->
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
