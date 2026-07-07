defmodule Flamingo.Scoring do
  @first_score 400
  @base_score 300
  @rank_decay 0.8
  @min_gap 10
  @min_score 50
  @max_time_penalty 100

  @doc """
  Scores a completed turn.

  Guessers are scored primarily by finishing position so being early feels
  great: the first guesser always banks #{@first_score}, and each later rank
  decays multiplicatively from #{@base_score}. A smaller time penalty (up to
  #{@max_time_penalty}) punishes guesses that trail long after the first
  correct answer. Scores never increase with rank and never drop below
  #{@min_score}.
  """
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
      |> Enum.reduce({%{}, @first_score}, fn {{player_id, guess_time}, rank}, {acc, prev_score} ->
        score =
          if rank == 0 do
            @first_score
          else
            time_taken_us = DateTime.diff(guess_time, first_time, :microsecond)
            time_ratio = time_taken_us / turn_duration_us
            time_ratio = max(0.0, min(1.0, time_ratio))

            rank_score = trunc(@base_score * :math.pow(@rank_decay, rank))

            (rank_score - trunc(@max_time_penalty * time_ratio))
            |> min(prev_score - @min_gap)
            |> max(@min_score)
          end

        {Map.put(acc, player_id, score), score}
      end)

    scores
  end
end
