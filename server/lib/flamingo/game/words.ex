defmodule Flamingo.Game.Words do
  @words ~w(cat dog house tree apple banana computer elephant guitar hospital
            mountain ocean penguin rainbow sandwich telephone umbrella volcano
            waterfall zebra)

  @spec random_choices(pos_integer()) :: list(String.t())
  def random_choices(count \\ 3), do: Enum.take_random(@words, count)
end
