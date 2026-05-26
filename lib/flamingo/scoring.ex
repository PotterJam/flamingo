defmodule Flamingo.Scoring do
  @base_score 300
  @min_gap 25
  @min_score 50
  @max_time_penalty 250
  @first_bonus 100

  def calculate_round_scores(correct_guesses, drawer_id, player_order, turn_length) do
    guesser_scores = calculate_guesser_scores(correct_guesses, turn_length)

    total_possible = length(player_order) - 1

    drawer_score =
      cond do
        total_possible == 0 ->
          0

        map_size(correct_guesses) == 0 ->
          -100

        map_size(correct_guesses) == 1 ->
          100

        true ->
          ratio = (map_size(correct_guesses) - 1) / (total_possible - 1)
          100 + trunc(ratio * 250)
      end

    Map.put(guesser_scores, drawer_id, drawer_score)
  end

  defp calculate_guesser_scores(correct_guesses, _turn_length)
       when map_size(correct_guesses) == 0 do
    %{}
  end

  defp calculate_guesser_scores(correct_guesses, turn_length) do
    sorted =
      correct_guesses
      |> Enum.sort_by(fn {_id, time} -> DateTime.to_unix(time, :microsecond) end)

    {_first_id, first_time} = hd(sorted)
    turn_duration_us = turn_length * 1_000_000

    {scores, _prev} =
      sorted
      |> Enum.with_index()
      |> Enum.reduce({%{}, nil}, fn {{player_id, guess_time}, idx}, {acc, prev_score} ->
        time_taken_us = DateTime.diff(guess_time, first_time, :microsecond)
        time_ratio = time_taken_us / turn_duration_us
        time_ratio = max(0.0, min(1.0, time_ratio))

        score = @base_score - trunc(@max_time_penalty * time_ratio)

        score =
          if idx == 0 do
            score + @first_bonus
          else
            if prev_score - score < @min_gap do
              prev_score - @min_gap
            else
              score
            end
          end

        score = max(score, @min_score)
        {Map.put(acc, player_id, score), score}
      end)

    scores
  end
end
