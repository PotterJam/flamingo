defmodule Flamingo.GameSettingsTest do
  use ExUnit.Case, async: true

  alias Flamingo.GameSettings
  alias Flamingo.GameModes.{Scribble, Telephone}

  test "defaults and both ends of the turn length range are valid" do
    assert {:ok, defaults} = GameSettings.validate(%{})
    assert defaults == GameSettings.defaults()
    assert defaults.turn_length == 30

    for seconds <- [15, 120] do
      assert {:ok, %{turn_length: ^seconds}} = GameSettings.validate(%{turn_length: seconds})
    end
  end

  test "partial settings retain current values and exclude mode-specific fields" do
    current = %{
      turn_length: 90,
      custom_words: ["cat", "dog"],
      include_default_words: true,
      word_list: :films,
      round_count: 5
    }

    assert {:ok, settings} =
             GameSettings.validate(%{word_list: :landmarks, round_count: 2}, current)

    assert settings == current |> Map.delete(:round_count) |> Map.put(:word_list, :landmarks)
  end

  test "invalid shared settings return their existing errors" do
    cases = [
      {%{turn_length: 14}, :invalid_turn_length},
      {%{turn_length: 121}, :invalid_turn_length},
      {%{turn_length: "30"}, :invalid_turn_length},
      {%{turn_length: nil}, :invalid_turn_length},
      {%{turn_length: 30.5}, :invalid_turn_length},
      {%{custom_words: "cat"}, :invalid_custom_words},
      {%{custom_words: ["cat, dog"]}, :invalid_custom_words},
      {%{custom_words: List.duplicate("cat", 3001)}, :too_many_custom_words},
      {%{include_default_words: "false"}, :invalid_include_default_words},
      {%{word_list: :unknown}, :invalid_word_list}
    ]

    for {settings, reason} <- cases do
      assert {:error, ^reason} = GameSettings.validate(settings)
    end
  end

  test "both modes apply shared settings, retain them on restart, and reject invalid input" do
    roster = %{
      players: %{
        "a" => %{id: "a", name: "Alice", connected: true},
        "b" => %{id: "b", name: "Bob", connected: true}
      },
      player_order: ["a", "b"],
      host_id: "a"
    }

    context = %{
      roster: roster,
      actor_id: "a",
      now: ~U[2026-01-01 00:00:00Z],
      word_choices: fn _, _, _ -> ["cat", "dog", "bird"] end,
      select_candidate: &List.first/1
    }

    for mode <- [Scribble, Telephone] do
      assert Map.take(mode.new(), Map.keys(GameSettings.defaults())) == GameSettings.defaults()

      state =
        Enum.reduce(roster.player_order, mode.new(), fn id, state ->
          {:ok, %{state: state}} = mode.admit_member(state, roster.players[id], context)
          state
        end)

      assert {:error, :invalid_turn_length} = mode.start(state, %{turn_length: 14}, context)
      assert {:error, :invalid_word_list} = mode.start(state, %{word_list: :unknown}, context)

      assert {:error, :not_host} =
               mode.start(state, %{turn_length: 14}, %{context | actor_id: "b"})

      settings = %{
        turn_length: 90,
        custom_words: ["cat", "dog"],
        include_default_words: true,
        word_list: :films
      }

      assert {:ok, %{state: started}} = mode.start(state, settings, context)
      assert Map.take(started, Map.keys(settings)) == settings

      assert {:ok, %{state: restarted}} =
               mode.start(%{started | phase: :game_ended}, %{}, context)

      assert Map.take(restarted, Map.keys(settings)) == settings
    end
  end
end
