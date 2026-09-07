defmodule Flamingo.GameSettings do
  @moduledoc "Shared game settings policy. Mode-specific rules remain in each game mode."

  alias Flamingo.Words

  @turn_length_range 15..120
  @defaults %{
    turn_length: 30,
    custom_words: [],
    include_default_words: false,
    word_list: :default
  }

  def defaults, do: @defaults
  def turn_length_range, do: @turn_length_range

  @doc "Validates shared settings, retaining current values for omitted settings."
  def validate(settings, current \\ @defaults) do
    settings =
      current
      |> Map.take(Map.keys(@defaults))
      |> Map.merge(Map.take(settings, Map.keys(@defaults)))

    with true <- settings.turn_length in @turn_length_range || {:error, :invalid_turn_length},
         {:ok, _} <- Words.validate_custom_words(settings.custom_words),
         true <-
           is_boolean(settings.include_default_words) || {:error, :invalid_include_default_words},
         {:ok, _} <- Words.validate_word_list(settings.word_list) do
      {:ok, settings}
    end
  end
end
