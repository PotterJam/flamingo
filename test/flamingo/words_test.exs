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

  test "random_choices uses the selected built-in word list" do
    film_words = all_words(:films)
    excluded_words = film_words |> Enum.drop(3) |> MapSet.new()

    choices = Words.random_choices(3, excluded_words, word_list: :films)

    assert Enum.sort(choices) == film_words |> Enum.take(3) |> Enum.sort()
  end

  test "random_choices merges defaults and deduplicates case-insensitively" do
    excluded_words = all_words() |> Enum.reject(&(&1 in ["Apple", "bow"])) |> MapSet.new()

    choices =
      Words.random_choices(3, excluded_words,
        custom_words: ["Bow", "orbital llama"],
        include_default_words: true
      )

    assert Enum.sort(choices) == Enum.sort(["Apple", "Bow", "orbital llama"])
  end

  test "random_choices merges custom words with the selected built-in word list" do
    film_words = all_words(:films)
    [first, second | excluded] = film_words

    choices =
      Words.random_choices(3, MapSet.new(excluded),
        custom_words: [String.downcase(first), "orbital llama"],
        include_default_words: true,
        word_list: :films
      )

    assert Enum.sort(choices) == Enum.sort([String.downcase(first), second, "orbital llama"])
  end

  test "validate_word_list accepts built-in lists and rejects unknown lists" do
    assert {:ok, :default} = Words.validate_word_list(:default)
    assert {:ok, :films} = Words.validate_word_list(:films)
    assert {:error, :invalid_word_list} = Words.validate_word_list(:unknown)
  end

  test "parse_custom_words trims blank lines and removes duplicates" do
    assert {:ok, ["red panda", "flamingo"]} =
             Words.parse_custom_words(" red panda \n\nflamingo\nred panda\n")
  end

  test "parse_custom_words rejects commas and more than 3000 words" do
    assert {:error, :invalid_custom_words} = Words.parse_custom_words("cat, dog")

    too_many_words = Enum.map_join(1..3001, "\n", &"word #{&1}")
    assert {:error, :too_many_custom_words} = Words.parse_custom_words(too_many_words)
  end

  defp all_words(word_list \\ :default) do
    "priv/words/#{word_list}.txt"
    |> File.read!()
    |> String.split("\n", trim: true)
  end
end
