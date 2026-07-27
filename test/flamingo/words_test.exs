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

  test "available_words merges defaults and deduplicates case-insensitively" do
    words = Words.available_words(["apple", "orbital llama"], true)

    assert "apple" in words
    assert "orbital llama" in words
    refute "Apple" in words
    assert length(Enum.filter(words, &(String.downcase(&1) == "apple"))) == 1
  end

  test "parse_custom_words trims blank lines and removes duplicates" do
    assert {:ok, ["red panda", "flamingo"]} =
             Words.parse_custom_words(" red panda \n\nflamingo\nred panda\n")
  end

  test "parse_custom_words rejects commas and more than 1000 words" do
    assert {:error, :invalid_custom_words} = Words.parse_custom_words("cat, dog")

    too_many_words = Enum.map_join(1..1001, "\n", &"word #{&1}")
    assert {:error, :too_many_custom_words} = Words.parse_custom_words(too_many_words)
  end

  defp all_words do
    "priv/words/default.txt"
    |> File.read!()
    |> String.split("\n", trim: true)
  end
end
