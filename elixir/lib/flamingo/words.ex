defmodule Flamingo.Words do
  @words File.read!("priv/words/default.txt")
         |> String.split("\n", trim: true)

  def random_choices(n \\ 3) do
    Enum.take_random(@words, n)
  end
end
