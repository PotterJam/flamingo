defmodule Flamingo.WordsTest do
  use ExUnit.Case, async: true

  alias Flamingo.Words

  test "random_choices returns expected number of unused words when enough remain" do
    words = all_words()
    excluded_words = words |> Enum.drop(3) |> MapSet.new()

    choices = Words.random_choices(3, excluded_words)

    assert length(choices) == 3
    assert Enum.all?(choices, &(not MapSet.member?(excluded_words, &1)))
  end

  test "random_choices handles exhausted unused words" do
    excluded_words = MapSet.new(all_words())
    assert Words.random_choices(3, excluded_words) == []
  end

  defp all_words do
    "priv/words/default.txt"
    |> File.read!()
    |> String.split("\n", trim: true)
  end
end
