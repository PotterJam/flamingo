defmodule Flamingo.DrawingShareTest do
  use ExUnit.Case, async: true

  alias Flamingo.DrawingShare

  test "encodes drawings into URL-safe compressed payloads and decodes them" do
    drawing = %{
      drawer_name: "Alice",
      word: "flamingo",
      round_number: 2,
      events: [
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
    }

    encoded = DrawingShare.encode(drawing)

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

  test "rounds coordinates and drops sub-pixel jitter" do
    jittery_points =
      for i <- 0..99 do
        %{
          "event_type" => "draw",
          "start_x" => 10 + i * 0.1,
          "start_y" => 20,
          "end_x" => 10 + (i + 1) * 0.1,
          "end_y" => 20,
          "color" => "#000000",
          "line_width" => 9
        }
      end

    drawing = %{
      drawer_name: "Alice",
      word: "flamingo",
      round_number: 1,
      events:
        [
          %{
            "event_type" => "start",
            "x" => 10.4,
            "y" => 20.2,
            "color" => "#000000",
            "line_width" => 9
          }
        ] ++ jittery_points
    }

    assert [["p", "#000000", 9, points]] = DrawingShare.compact_ops(drawing.events)

    # 101 raw points collapse to a handful of integer coordinates
    assert length(points) < 20
    assert Enum.all?(points, &is_integer/1)
    # stroke endpoints survive simplification
    assert Enum.take(points, 2) == [10, 20]
    assert Enum.take(points, -2) == [20, 20]
  end

  test "compresses large drawings far below the raw event encoding" do
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

    drawing = %{drawer_name: "Alice", word: "flamingo", round_number: 1, events: events}

    raw_size = drawing |> Jason.encode!() |> byte_size()
    encoded_size = drawing |> DrawingShare.encode() |> byte_size()

    assert encoded_size < div(raw_size, 10)
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
