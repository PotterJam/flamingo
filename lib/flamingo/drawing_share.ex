defmodule Flamingo.DrawingShare do
  @moduledoc false

  @type drawing :: %{
          required(:drawer_name) => String.t(),
          required(:word) => String.t(),
          required(:round_number) => pos_integer(),
          required(:events) => list(map())
        }

  def encode(drawing) do
    drawing
    |> payload()
    |> Jason.encode!()
    |> Base.url_encode64(padding: false)
  end

  def decode(encoded) when is_binary(encoded) do
    with {:ok, json} <- Base.url_decode64(encoded, padding: false),
         {:ok, payload} <- Jason.decode(json),
         {:ok, drawing} <- normalize(payload) do
      {:ok, drawing}
    else
      _ -> {:error, :invalid_drawing}
    end
  end

  def decode(_encoded), do: {:error, :invalid_drawing}

  defp payload(drawing) do
    %{
      "drawer_name" => Map.fetch!(drawing, :drawer_name),
      "word" => Map.fetch!(drawing, :word),
      "round_number" => Map.fetch!(drawing, :round_number),
      "events" => Map.fetch!(drawing, :events)
    }
  end

  defp normalize(%{
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

  defp normalize(_payload), do: {:error, :invalid_drawing}
end
