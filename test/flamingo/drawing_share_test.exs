defmodule Flamingo.DrawingShareTest do
  use ExUnit.Case, async: true

  alias Flamingo.DrawingShare

  test "encodes drawings into URL-safe base64 and decodes them" do
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
        }
      ]
    }

    encoded = DrawingShare.encode(drawing)

    refute encoded =~ "+"
    refute encoded =~ "/"
    refute encoded =~ "="

    assert {:ok, ^drawing} = DrawingShare.decode(encoded)
  end

  test "rejects invalid drawing payloads" do
    assert {:error, :invalid_drawing} = DrawingShare.decode("not-base64")

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
  end
end
