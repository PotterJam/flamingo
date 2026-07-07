defmodule Flamingo.DrawingShareTest do
  use ExUnit.Case, async: true

  alias Flamingo.DrawingShare

  defp encode_drawing(events) do
    DrawingShare.encode(%{
      drawer_name: "Alice",
      word: "flamingo",
      round_number: 2,
      ops: DrawingShare.compact_ops(events)
    })
  end

  test "encodes drawings into URL-safe compressed payloads and decodes them" do
    events = [
      %{
        "event_type" => "start",
        "x" => 10,
        "y" => 20,
        "color" => "#000000",
        "line_width" => 9
      },
      %{
        "event_type" => "draw",
        "start_x" => 10,
        "start_y" => 20,
        "end_x" => 30,
        "end_y" => 40,
        "color" => "#000000",
        "line_width" => 9
      },
      %{"event_type" => "fill", "x" => 100, "y" => 120, "color" => "#EF120B"},
      %{"event_type" => "clear"}
    ]

    encoded = encode_drawing(events)

    assert String.starts_with?(encoded, "z")
    refute encoded =~ "+"
    refute encoded =~ "/"
    refute encoded =~ "="

    assert {:ok, decoded} = DrawingShare.decode(encoded)
    assert decoded.drawer_name == "Alice"
    assert decoded.word == "flamingo"
    assert decoded.round_number == 2

    assert [
             %{"event_type" => "start", "x" => 10, "y" => 20},
             %{
               "event_type" => "draw",
               "start_x" => 10,
               "start_y" => 20,
               "end_x" => 30,
               "end_y" => 40
             },
             %{"event_type" => "fill", "x" => 100, "y" => 120, "color" => "#EF120B"},
             %{"event_type" => "clear"}
           ] = decoded.events
  end

  test "strokes are delta-encoded and simplified down to their shape" do
    jittery_points =
      for i <- 0..99 do
        %{
          "event_type" => "draw",
          "start_x" => 10 + i * 2.0,
          "start_y" => 20 + rem(i, 2) * 0.4,
          "end_x" => 10 + (i + 1) * 2.0,
          "end_y" => 20 + rem(i + 1, 2) * 0.4,
          "color" => "#000000",
          "line_width" => 9
        }
      end

    events =
      [
        %{
          "event_type" => "start",
          "x" => 10.4,
          "y" => 20.2,
          "color" => "#000000",
          "line_width" => 9
        }
      ] ++ jittery_points

    # A jittery near-straight line collapses to its two endpoints,
    # delta-encoded: [x0, y0, dx, dy].
    assert [["p", "#000000", 9, [10, 20, 200, 0]]] = DrawingShare.compact_ops(events)
  end

  test "total points are capped so busy drawings stay small" do
    # 40 dense wavy strokes: thousands of raw points, but each wave flattens
    # to a couple of points once the tolerance escalates.
    wave = fn stroke, i -> 250 + stroke * 2 + :math.sin(i / 10) * 20 end

    events =
      Enum.flat_map(1..40, fn stroke ->
        [
          %{
            "event_type" => "start",
            "x" => 10,
            "y" => wave.(stroke, 0),
            "color" => "#000000",
            "line_width" => 9
          }
          | for i <- 1..200 do
              %{
                "event_type" => "draw",
                "start_x" => 10 + (i - 1) * 3,
                "start_y" => wave.(stroke, i - 1),
                "end_x" => 10 + i * 3,
                "end_y" => wave.(stroke, i),
                "color" => "#000000",
                "line_width" => 9
              }
            end
        ]
      end)

    ops = DrawingShare.compact_ops(events)

    total_points =
      ops
      |> Enum.map(fn
        ["p", _color, _width, nums] -> div(length(nums), 2)
        _op -> 0
      end)
      |> Enum.sum()

    assert total_points <= 200
  end

  test "compresses large drawings by 100x or more" do
    events =
      [
        %{"event_type" => "start", "x" => 0, "y" => 0, "color" => "#000000", "line_width" => 9}
      ] ++
        for i <- 1..5000 do
          %{
            "event_type" => "draw",
            "start_x" => rem(i - 1, 700) * 1.0,
            "start_y" => rem((i - 1) * 3, 500) * 1.0,
            "end_x" => rem(i, 700) * 1.0,
            "end_y" => rem(i * 3, 500) * 1.0,
            "color" => "#000000",
            "line_width" => 9
          }
        end

    raw_size = events |> Jason.encode!() |> byte_size()
    encoded_size = events |> encode_drawing() |> byte_size()

    assert encoded_size < div(raw_size, 100)
    assert encoded_size < 2048
  end

  test "decodes legacy uncompressed links" do
    payload = %{
      "drawer_name" => "Alice",
      "word" => "flamingo",
      "round_number" => 2,
      "events" => [
        %{
          "event_type" => "start",
          "x" => 10,
          "y" => 20,
          "color" => "#000000",
          "line_width" => 9
        }
      ]
    }

    encoded = payload |> Jason.encode!() |> Base.url_encode64(padding: false)

    assert {:ok, decoded} = DrawingShare.decode(encoded)
    assert decoded.drawer_name == "Alice"
    assert decoded.word == "flamingo"
    assert decoded.round_number == 2
    assert [%{"event_type" => "start"}] = decoded.events
  end

  test "rejects invalid drawing payloads" do
    assert {:error, :invalid_drawing} = DrawingShare.decode("not-base64")
    assert {:error, :invalid_drawing} = DrawingShare.decode("znot-valid-zlib")

    encoded =
      %{"drawer_name" => "Alice", "word" => "flamingo", "round_number" => 1, "events" => ["bad"]}
      |> Jason.encode!()
      |> Base.url_encode64(padding: false)

    assert {:error, :invalid_drawing} = DrawingShare.decode(encoded)

    encoded =
      %{"word" => "flamingo", "round_number" => 1, "events" => []}
      |> Jason.encode!()
      |> Base.url_encode64(padding: false)

    assert {:error, :invalid_drawing} = DrawingShare.decode(encoded)

    bad_ops =
      %{"v" => 2, "n" => "Alice", "w" => "flamingo", "r" => 1, "o" => [["x", 1]]}
      |> Jason.encode!()
      |> :zlib.compress()
      |> Base.url_encode64(padding: false)

    assert {:error, :invalid_drawing} = DrawingShare.decode("z" <> bad_ops)
  end
end
