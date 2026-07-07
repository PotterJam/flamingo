defmodule Flamingo.ScoringTest do
  use ExUnit.Case, async: true

  alias Flamingo.Scoring

  @turn_length 45

  defp guess_times(offsets_ms) do
    base = ~U[2026-01-01 12:00:00.000000Z]

    offsets_ms
    |> Enum.with_index()
    |> Map.new(fn {offset, idx} ->
      {"player-#{idx}", DateTime.add(base, offset, :millisecond)}
    end)
  end

  test "first guesser always gets the full first score" do
    scores =
      Scoring.calculate_round_scores(
        guess_times([0]),
        "drawer",
        ["drawer", "player-0"],
        @turn_length
      )

    assert scores["player-0"] == 400
  end

  test "early ranks are rewarded steeply" do
    guesses = guess_times([0, 500, 1_000, 1_500, 2_000])
    order = ["drawer" | Map.keys(guesses)]

    scores = Scoring.calculate_round_scores(guesses, "drawer", order, @turn_length)

    assert scores["player-0"] == 400
    # near-immediate follow-ups keep most of their rank score
    assert scores["player-1"] in 230..240
    assert scores["player-2"] in 180..192
    assert scores["player-3"] in 145..154
    assert scores["player-4"] in 115..123
  end

  test "scores never increase with rank" do
    guesses = guess_times([0, 40_000, 40_500, 41_000, 42_000, 43_000])
    order = ["drawer" | Map.keys(guesses)]

    scores = Scoring.calculate_round_scores(guesses, "drawer", order, @turn_length)

    ranked =
      guesses
      |> Enum.sort_by(fn {_id, time} -> DateTime.to_unix(time, :microsecond) end)
      |> Enum.map(fn {id, _} -> scores[id] end)

    assert ranked == Enum.sort(ranked, :desc)
  end

  test "slow guesses are penalised but floored" do
    guesses = guess_times([0, 44_000])
    order = ["drawer" | Map.keys(guesses)]

    scores = Scoring.calculate_round_scores(guesses, "drawer", order, @turn_length)

    assert scores["player-0"] == 400
    # rank score 240 minus nearly the full time penalty
    assert scores["player-1"] <= 145
    assert scores["player-1"] >= 50
  end

  test "very late stragglers bottom out at the minimum" do
    guesses = guess_times(Enum.map(0..9, &(&1 * 4_000)))
    order = ["drawer" | Map.keys(guesses)]

    scores = Scoring.calculate_round_scores(guesses, "drawer", order, @turn_length)

    last = scores["player-9"]
    assert last == 50
  end

  test "drawer scoring scales with how many players guessed" do
    order = ["drawer", "a", "b", "c"]

    assert %{"drawer" => -100} =
             Scoring.calculate_round_scores(%{}, "drawer", order, @turn_length)

    one = guess_times([0]) |> Scoring.calculate_round_scores("drawer", order, @turn_length)
    assert one["drawer"] == 100

    all =
      guess_times([0, 1_000, 2_000])
      |> Scoring.calculate_round_scores("drawer", order, @turn_length)

    assert all["drawer"] == 350
  end
end
