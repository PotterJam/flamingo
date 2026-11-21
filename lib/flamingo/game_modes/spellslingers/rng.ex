defmodule Flamingo.GameModes.Spellslingers.Rng do
  @moduledoc "Seeded random helpers. Each returns its result with the next rng state."

  def shuffle(list, rng) do
    {keyed, rng} =
      Enum.map_reduce(list, rng, fn item, rng ->
        {r, rng} = :rand.uniform_s(rng)
        {{r, item}, rng}
      end)

    {keyed |> Enum.sort() |> Enum.map(&elem(&1, 1)), rng}
  end

  def pick(list, rng) do
    {index, rng} = :rand.uniform_s(length(list), rng)
    {Enum.at(list, index - 1), rng}
  end

  def roll_wind(rng) do
    {value, rng} = :rand.uniform_s(21, rng)
    {value - 11, rng}
  end
end
