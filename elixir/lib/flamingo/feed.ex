defmodule Flamingo.Feed do
  defstruct events: []

  def new(), do: %__MODULE__{}

  def player_joined(feed, player_id, name) do
    event = {:player_joined, player_id, name}
    {%{feed | events: feed.events ++ [event]}, event}
  end

  def player_left(feed, player_id, name) do
    event = {:player_left, player_id, name}
    {%{feed | events: feed.events ++ [event]}, event}
  end

  def new_turn(feed, player_id, name) do
    event = {:new_turn, player_id, name}
    {%{feed | events: feed.events ++ [event]}, event}
  end

  def guess(feed, player_id, name, text) do
    event = {:guess, player_id, name, text}
    {%{feed | events: feed.events ++ [event]}, event}
  end

  def correct_guess(feed, player_id, name) do
    event = {:correct_guess, player_id, name}
    {%{feed | events: feed.events ++ [event]}, event}
  end

  def word_revealed(feed, word) do
    event = {:word_revealed, word}
    {%{feed | events: feed.events ++ [event]}, event}
  end

  def format({:player_joined, _player_id, name}, _viewer), do: {:info, "#{name} joined"}
  def format({:player_left, _player_id, name}, _viewer), do: {:info, "#{name} left"}

  def format({:new_turn, _player_id, name}, _viewer), do: {:system, "It's #{name}'s turn to draw"}
  def format({:guess, _player_id, name, text}, _viewer), do: {:guess, "#{name}: #{text}"}

  def format({:correct_guess, player_id, _name}, viewer) when player_id == viewer,
    do: {:correct, "You guessed it"}

  def format({:correct_guess, _player_id, name}, _viewer),
    do: {:correct, "#{name} guessed the word"}

  def format({:word_revealed, word}, _viewer), do: {:system, "The word was #{word}"}
end
