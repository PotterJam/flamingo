defmodule Flamingo.Words do
  @words File.read!("priv/words/default.txt")
         |> String.split("\n", trim: true)

  def random_choices(n \\ 3, excluded_words \\ MapSet.new()) do
    @words
    |> Enum.reject(&MapSet.member?(excluded_words, &1))
    |> Enum.take_random(n)
  end
end
