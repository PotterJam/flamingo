defmodule Flamingo.Feed do
  defstruct events: [], next_id: 1

  def new(), do: %__MODULE__{}

  def player_joined(feed, player_id, name), do: add(feed, {:player_joined, player_id, name})

  def player_left(feed, player_id, name), do: add(feed, {:player_left, player_id, name})

  def new_turn(feed, player_id, name), do: add(feed, {:new_turn, player_id, name})

  def guess(feed, player_id, name, text), do: add(feed, {:guess, player_id, name, text})

  def close_guess(feed, player_id), do: add(feed, {:close_guess, player_id})

  def correct_guess(feed, player_id, name), do: add(feed, {:correct_guess, player_id, name})

  def word_revealed(feed, word), do: add(feed, {:word_revealed, word})

  defp add(feed, event) do
    entry = %{id: feed.next_id, event: event}
    {%{feed | events: feed.events ++ [entry], next_id: feed.next_id + 1}, entry}
  end

  def format(%{id: id, event: event}, viewer) do
    case format_event(event, viewer) do
      nil -> nil
      {kind, text} -> %{id: id, kind: kind, text: text}
    end
  end

  defp format_event({:player_joined, _player_id, name}, _viewer), do: {:info, "#{name} joined"}
  defp format_event({:player_left, _player_id, name}, _viewer), do: {:info, "#{name} left"}

  defp format_event({:new_turn, _player_id, name}, _viewer),
    do: {:system, "It's #{name}'s turn to draw"}

  defp format_event({:guess, _player_id, name, text}, _viewer), do: {:guess, "#{name}: #{text}"}

  defp format_event({:close_guess, player_id}, viewer) when player_id == viewer,
    do: {:close, "You were close"}

  defp format_event({:close_guess, _player_id}, _viewer), do: nil

  defp format_event({:correct_guess, player_id, _name}, viewer) when player_id == viewer,
    do: {:correct, "You guessed it"}

  defp format_event({:correct_guess, _player_id, name}, _viewer),
    do: {:correct, "#{name} guessed the word"}

  defp format_event({:word_revealed, word}, _viewer), do: {:system, "The word was #{word}"}
end
