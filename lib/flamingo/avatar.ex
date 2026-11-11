defmodule Flamingo.Avatar do
  @moduledoc """
  Defines the interchangeable animal parts used to build a player's avatar.
  """

  @parts ~w(head body legs feet)
  @animals ~w(flamingo cat frog bunny duck)
  @colors ~w(#f472b6 #fb7185 #c084fc #fb923c #2dd4bf #facc15 #60a5fa #a3e635)

  @traits Map.new(@parts, &{&1, 0..(length(@animals) - 1)})
          |> Map.merge(Map.new(@parts, &{"#{&1}_color", 0..(length(@colors) - 1)}))

  @custom_traits Map.new(@parts, &{"#{&1}_drawing", String.to_atom("#{&1}_drawing")})

  @trait_atoms Map.new(@traits, fn {trait, _range} -> {trait, String.to_atom(trait)} end)

  @default %{
    "head" => 0,
    "head_color" => 0,
    "head_drawing" => "",
    "body" => 0,
    "body_color" => 0,
    "body_drawing" => "",
    "legs" => 0,
    "legs_color" => 0,
    "legs_drawing" => "",
    "feet" => 0,
    "feet_color" => 0,
    "feet_drawing" => ""
  }

  def default, do: @default

  def normalize(avatar) when is_map(avatar) do
    traits =
      Map.new(@traits, fn {trait, range} ->
        value = Map.get(avatar, trait, Map.get(avatar, Map.fetch!(@trait_atoms, trait)))
        {trait, normalize_value(value, Map.fetch!(@default, trait), range)}
      end)

    drawings =
      Map.new(@custom_traits, fn {trait, atom} ->
        {trait, normalize_drawing(Map.get(avatar, trait, Map.get(avatar, atom)))}
      end)

    Map.merge(traits, drawings)
  end

  def normalize(_avatar), do: normalize(@default)

  def random do
    @traits
    |> Map.new(fn {trait, range} -> {trait, Enum.random(range)} end)
    |> normalize()
  end

  def parts, do: @parts
  def animals, do: Enum.with_index(@animals)
  def colors, do: Enum.with_index(@colors)

  def animal_label(value),
    do: Enum.at(@animals, normalize_value(value, 0, 0..(length(@animals) - 1)))

  def color(value),
    do: Enum.at(@colors, normalize_value(value, 0, 0..(length(@colors) - 1)))

  def max(trait), do: @traits |> Map.fetch!(trait) |> Enum.max()

  defp normalize_value(value, default, range) when is_integer(value) do
    if value in range, do: value, else: default
  end

  defp normalize_value(value, default, range) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> normalize_value(number, default, range)
      _ -> default
    end
  end

  defp normalize_value(_value, default, _range), do: default

  def drawing_strokes(value, default_width \\ 6) do
    cond do
      value == "" ->
        []

      valid_path?(value) ->
        [%{"path" => value, "width" => default_width}]

      true ->
        case Jason.decode(value) do
          {:ok, strokes} when is_list(strokes) ->
            if Enum.all?(strokes, &valid_stroke?/1), do: strokes, else: []

          _ ->
            []
        end
    end
  end

  defp valid_stroke?(%{"path" => path, "width" => width} = stroke)
       when map_size(stroke) == 2 and width in [2, 4, 6, 10],
       do: is_binary(path) and path != "" and valid_path?(path)

  defp valid_stroke?(_), do: false

  defp valid_path?(value), do: Regex.match?(~r/\A[ML0-9 .-]*\z/, value)

  defp normalize_drawing(value) when is_binary(value) and byte_size(value) <= 24_000 do
    if drawing_strokes(value) == [], do: "", else: value
  end

  defp normalize_drawing(_value), do: ""
end
