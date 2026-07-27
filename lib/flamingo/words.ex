defmodule Flamingo.Words do
  @max_custom_words 1_000

  @words File.read!("priv/words/default.txt")
         |> String.split("\n", trim: true)

  def random_choices(n \\ 3, excluded_words \\ MapSet.new(), options \\ []) do
    custom_words = Keyword.get(options, :custom_words, [])
    include_default_words = Keyword.get(options, :include_default_words, false)

    words = available_words(custom_words, include_default_words)

    words
    |> Enum.reject(&MapSet.member?(excluded_words, &1))
    |> Enum.take_random(n)
  end

  defp available_words([], _include_default_words), do: @words
  defp available_words(custom_words, false), do: custom_words

  defp available_words(custom_words, true) do
    Enum.uniq_by(custom_words ++ @words, &String.downcase/1)
  end

  def parse_custom_words(text) when is_binary(text) do
    words =
      text
      |> String.split(~r/\R/)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    validate_custom_words(words)
  end

  def validate_custom_words(words) when is_list(words) do
    cond do
      length(words) > @max_custom_words ->
        {:error, :too_many_custom_words}

      Enum.any?(
        words,
        &(not is_binary(&1) or &1 == "" or String.contains?(&1, [",", "\n", "\r"]))
      ) ->
        {:error, :invalid_custom_words}

      true ->
        {:ok, words}
    end
  end

  def validate_custom_words(_words), do: {:error, :invalid_custom_words}
end
