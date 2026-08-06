defmodule Flamingo.GameModes.Scribble do
  @moduledoc """
  Pure Scribble transitions. Every accepted transition reports whether the
  mode should `:continue` or has `{:finished, result}`.
  """

  alias Flamingo.{DrawingShare, Feed, Scoring, Words}

  @min_turn_length 15
  @max_turn_length 120

  def new do
    %{
      phase: :lobby,
      participants: %{},
      scores: %{},
      round_count: 3,
      turn_length: 30,
      custom_words: [],
      include_default_words: false,
      drawer_id: nil,
      current_round: 0,
      drawn_this_round: MapSet.new(),
      word: nil,
      word_choices: [],
      used_words: MapSet.new(),
      current_drawing: [],
      correct_guesses: %{},
      revealed_indices: [],
      pending_hint_delays: [],
      score_gains: %{},
      final_drawings: [],
      final_result: nil,
      feed: Feed.new()
    }
  end

  def admit_member(state, %{id: id} = candidate, _context) do
    participation =
      if state.phase in [:word_choice, :playing, :turn_reveal], do: :spectator, else: :active

    state = %{
      state
      | participants: Map.put(state.participants, id, participation),
        scores: Map.put(state.scores, id, 0)
    }

    {feed, _} = Feed.player_joined(state.feed, id, candidate.name)
    ok(%{state | feed: feed})
  end

  def connection_changed(state, seat_id, :offline, context) do
    transition(state, reconcile_completion(state, seat_id, context), :ok)
  end

  def connection_changed(state, _seat_id, :online, _context), do: ok(state)

  def remove_member(state, seat_id, removed, context) do
    state = %{
      state
      | participants: Map.delete(state.participants, seat_id),
        scores: Map.delete(state.scores, seat_id),
        correct_guesses: Map.delete(state.correct_guesses, seat_id),
        score_gains: Map.delete(state.score_gains, seat_id)
    }

    {feed, _} = Feed.player_left(state.feed, seat_id, removed.name)
    state = %{state | feed: feed}

    next =
      cond do
        state.phase in [:word_choice, :playing] and seat_id == state.drawer_id ->
          if state.phase == :playing,
            do: enter_reveal(state, context),
            else: next_turn(state, context)

        state.phase == :playing ->
          reconcile_completion(state, seat_id, context)

        true ->
          {state, []}
      end

    transition(state, next, :ok)
  end

  def start(state, settings, context) do
    round_count = Map.get(settings, :round_count, state.round_count)
    turn_length = Map.get(settings, :turn_length, state.turn_length)
    custom_words = Map.get(settings, :custom_words, state.custom_words)
    defaults = Map.get(settings, :include_default_words, state.include_default_words)
    roster = context.roster

    with true <- context.actor_id == roster.host_id || {:error, :not_host},
         true <- online_count(roster) >= 2 || {:error, :not_enough_players},
         true <- round_count in 1..5 || {:error, :invalid_round_count},
         true <-
           turn_length in @min_turn_length..@max_turn_length || {:error, :invalid_turn_length},
         {:ok, custom_words} <- Words.validate_custom_words(custom_words),
         true <- is_boolean(defaults) || {:error, :invalid_include_default_words} do
      participants = Map.new(state.participants, fn {id, _} -> {id, :active} end)

      state = %{
        state
        | round_count: round_count,
          turn_length: turn_length,
          custom_words: custom_words,
          include_default_words: defaults,
          participants: participants,
          drawer_id: Enum.find(roster.player_order, &active?(participants, &1)),
          current_round: 0,
          drawn_this_round: MapSet.new(),
          used_words: MapSet.new(),
          final_drawings: [],
          final_result: nil
      }

      transition(state, enter_word_choice(state, context), :ok)
    else
      {:error, _} = error -> error
    end
  end

  def command(state, actor, {:select_word, word}, _context) do
    cond do
      state.phase != :word_choice -> {:error, :not_word_choice}
      actor != state.drawer_id -> {:error, :not_drawer}
      word not in state.word_choices -> {:error, :invalid_word}
      true -> transition(state, enter_playing(state, word), :ok)
    end
  end

  def command(state, actor, {:draw, event}, _context) do
    if state.phase == :playing and actor == state.drawer_id and active?(state, actor) do
      drawing =
        if event["event_type"] == "undo",
          do: undo(state.current_drawing),
          else: state.current_drawing ++ [event]

      if drawing == state.current_drawing,
        do: :ignored,
        else: ok(%{state | current_drawing: drawing}, :ok, [], nil, event)
    else
      :ignored
    end
  end

  def command(state, actor, {:guess, text}, context) when is_binary(text) do
    cond do
      state.phase != :playing ->
        {:error, :not_playing}

      Map.get(state.participants, actor) == :spectator ->
        {:error, :spectator}

      Map.get(state.participants, actor) != :active ->
        {:error, :not_found}

      actor == state.drawer_id ->
        {:error, :drawer_cannot_guess}

      Map.has_key?(state.correct_guesses, actor) ->
        {:error, :already_guessed}

      correct?(text, state.word) ->
        player = context.roster.players[actor]
        guesses = Map.put(state.correct_guesses, actor, context.now)
        {feed, _} = Feed.correct_guess(state.feed, actor, player.name)
        state = %{state | correct_guesses: guesses, feed: feed}

        transition(
          state,
          if(all_online_guessed?(state, context.roster),
            do: enter_reveal(state, context),
            else: {state, []}
          ),
          :correct
        )

      close?(text, state.word) ->
        {feed, _} = Feed.close_guess(state.feed, actor, text)
        ok(%{state | feed: feed}, :close)

      true ->
        player = context.roster.players[actor]
        {feed, _} = Feed.guess(state.feed, actor, player.name, text)
        ok(%{state | feed: feed}, :incorrect)
    end
  end

  def command(_state, _actor, {:guess, _}, _context), do: {:error, :invalid_guess}

  def timeout(state, :word_choice, context) when state.phase == :word_choice do
    case choose(context, state.word_choices) do
      nil -> :ignored
      word -> transition(state, enter_playing(state, word), :ok)
    end
  end

  def timeout(state, :playing, context) when state.phase == :playing,
    do: transition(state, enter_reveal(state, context), :ok)

  def timeout(state, :turn_reveal, context) when state.phase == :turn_reveal,
    do: transition(state, next_turn(state, context), :ok)

  def timeout(state, :reveal_hint, context) when state.phase == :playing do
    available = Enum.reject(letter_positions(state.word), &(&1 in state.revealed_indices))

    if available == [] or
         length(state.revealed_indices) >= div(length(letter_positions(state.word)), 2),
       do: ok(%{state | pending_hint_delays: []}, :ok, [:cancel_hint_timeout]),
       else:
         schedule_hint(%{
           state
           | revealed_indices: [choose(context, available) | state.revealed_indices]
         })
  end

  def timeout(_state, _key, _context), do: :ignored

  def view(state, viewer, roster) do
    visible =
      viewer == state.drawer_id or Map.has_key?(state.correct_guesses, viewer) or
        state.phase in [:turn_reveal, :game_ended]

    result = if state.phase == :game_ended, do: state.final_result

    %{
      mode: :scribble,
      phase: state.phase,
      viewer_id: viewer,
      participation: Map.get(state.participants, viewer),
      players:
        Map.new(roster.players, fn {id, p} ->
          {id, Map.put(p, :score, Map.fetch!(state.scores, id))}
        end),
      player_order: roster.player_order,
      host_id: roster.host_id,
      drawer_id: state.drawer_id,
      round_count: state.round_count,
      turn_length: state.turn_length,
      current_round: state.current_round,
      custom_words: if(viewer == roster.host_id, do: state.custom_words, else: []),
      include_default_words:
        if(viewer == roster.host_id, do: state.include_default_words, else: false),
      word_choices:
        if(state.phase == :word_choice and viewer == state.drawer_id,
          do: state.word_choices,
          else: []
        ),
      word: project_word(state.word, state.revealed_indices, visible),
      word_visible?: visible,
      correct_guesses: MapSet.new(Map.keys(state.correct_guesses)),
      revealed_indices: state.revealed_indices,
      score_gains: if(state.phase == :turn_reveal, do: state.score_gains, else: %{}),
      current_drawing: state.current_drawing,
      final_players: if(result, do: result.players, else: %{}),
      final_player_order: if(result, do: result.player_order, else: []),
      final_drawings: if(result, do: result.drawings, else: []),
      feed: state.feed.events |> Enum.map(&Feed.format(&1, viewer)) |> Enum.reject(&is_nil/1)
    }
  end

  def hint_schedule(word, length) do
    n = div(length(letter_positions(word)), 2)
    for k <- 1..n//1, do: trunc(length * 1000 * (0.35 + 0.55 * (k - 0.5) / n))
  end

  defp enter_word_choice(state, context) do
    choices =
      context.word_choices.(3, state.used_words, state.custom_words, state.include_default_words)

    if choices == [],
      do: game_ended(state, context.roster),
      else: begin_choice(state, choices, context.roster)
  end

  defp begin_choice(state, choices, roster) do
    state = %{
      state
      | phase: :word_choice,
        word_choices: choices,
        word: nil,
        correct_guesses: %{},
        revealed_indices: [],
        pending_hint_delays: []
    }

    {feed, _} = Feed.new_turn(state.feed, state.drawer_id, roster.players[state.drawer_id].name)

    {%{state | feed: feed},
     [:cancel_hint_timeout, {:schedule_phase_timeout, :word_choice, 10_000}]}
  end

  defp enter_playing(state, word) do
    offsets = hint_schedule(word, state.turn_length)
    deltas = elem(Enum.map_reduce(offsets, 0, fn x, p -> {x - p, x} end), 0)

    state = %{
      state
      | phase: :playing,
        word: word,
        used_words: MapSet.put(state.used_words, word),
        word_choices: [],
        current_drawing: [],
        correct_guesses: %{},
        revealed_indices: [],
        pending_hint_delays: deltas
    }

    case deltas do
      [delay | rest] ->
        {%{state | pending_hint_delays: rest},
         [
           {:schedule_phase_timeout, :playing, state.turn_length * 1000},
           {:schedule_hint_timeout, :reveal_hint, delay}
         ]}

      [] ->
        {state,
         [{:schedule_phase_timeout, :playing, state.turn_length * 1000}, :cancel_hint_timeout]}
    end
  end

  defp schedule_hint(%{pending_hint_delays: [delay | rest]} = state),
    do:
      ok(%{state | pending_hint_delays: rest}, :ok, [
        {:schedule_hint_timeout, :reveal_hint, delay}
      ])

  defp schedule_hint(state), do: ok(state, :ok, [:cancel_hint_timeout])

  defp enter_reveal(state, context) do
    active_order = Enum.filter(context.roster.player_order, &active?(state, &1))

    gains =
      Scoring.calculate_round_scores(
        state.correct_guesses,
        state.drawer_id,
        active_order,
        state.turn_length
      )
      |> Map.filter(fn {id, _} -> Map.has_key?(state.scores, id) end)

    scores = Map.new(state.scores, fn {id, score} -> {id, score + Map.get(gains, id, 0)} end)

    drawing = %{
      drawer_id: state.drawer_id,
      word: state.word,
      round_number: state.current_round + 1,
      ops: DrawingShare.compact_ops(state.current_drawing)
    }

    {feed, _} = Feed.word_revealed(state.feed, state.word)

    {%{
       state
       | phase: :turn_reveal,
         drawn_this_round: MapSet.put(state.drawn_this_round, state.drawer_id),
         final_drawings: state.final_drawings ++ [drawing],
         score_gains: gains,
         scores: scores,
         feed: feed,
         pending_hint_delays: []
     }, [:cancel_hint_timeout, {:schedule_phase_timeout, :turn_reveal, 5_000}]}
  end

  defp next_turn(state, context) do
    participants = Map.new(state.participants, fn {id, _} -> {id, :active} end)
    state = %{state | score_gains: %{}, participants: participants}

    next =
      Enum.find(
        context.roster.player_order,
        &(active?(state, &1) and not MapSet.member?(state.drawn_this_round, &1) and
            online?(context.roster, &1))
      )

    cond do
      next ->
        enter_word_choice(%{state | drawer_id: next}, context)

      state.current_round + 1 >= state.round_count ->
        game_ended(state, context.roster)

      first =
          Enum.find(
            context.roster.player_order,
            &(active?(state, &1) and online?(context.roster, &1))
          ) ->
        enter_word_choice(
          %{
            state
            | current_round: state.current_round + 1,
              drawn_this_round: MapSet.new(),
              drawer_id: first
          },
          context
        )

      true ->
        game_ended(state, context.roster)
    end
  end

  defp game_ended(state, roster) do
    players =
      Map.new(roster.players, fn {id, p} ->
        {id,
         p |> Map.take([:id, :name, :avatar]) |> Map.put(:score, Map.fetch!(state.scores, id))}
      end)

    {%{
       state
       | phase: :game_ended,
         pending_hint_delays: [],
         final_result: %{
           players: players,
           player_order: roster.player_order,
           drawings: state.final_drawings
         }
     }, [:cancel_phase_timeout, :cancel_hint_timeout]}
  end

  defp reconcile_completion(state, id, context),
    do:
      if(
        state.phase == :playing and id != state.drawer_id and
          all_online_guessed?(state, context.roster),
        do: enter_reveal(state, context),
        else: {state, []}
      )

  defp all_online_guessed?(state, roster) do
    ids =
      Enum.filter(
        roster.player_order,
        &(&1 != state.drawer_id and active?(state, &1) and online?(roster, &1))
      )

    ids != [] and Enum.all?(ids, &Map.has_key?(state.correct_guesses, &1))
  end

  defp active?(%{participants: participants}, id), do: active?(participants, id)
  defp active?(participants, id), do: Map.get(participants, id) == :active

  defp online?(roster, id), do: roster.players[id].connected
  defp online_count(roster), do: Enum.count(roster.players, fn {_, p} -> p.connected end)
  defp choose(context, candidates), do: context.select_candidate.(candidates)

  defp transition(_old, {new, timers}, reply), do: ok(new, reply, timers)

  defp ok(state, reply \\ :ok, timers \\ [], status \\ nil, delta \\ nil) do
    status =
      status ||
        if(state.phase == :game_ended, do: {:finished, state.final_result}, else: :continue)

    {:ok, %{state: state, reply: reply, timers: timers, status: status, drawing_delta: delta}}
  end

  defp undo(events) do
    idx =
      events
      |> Enum.reverse()
      |> Enum.find_index(&(&1["event_type"] in ["start", "fill", "clear"]))

    if idx, do: Enum.take(events, length(events) - idx - 1), else: events
  end

  defp letter_positions(word),
    do:
      word
      |> String.graphemes()
      |> Enum.with_index()
      |> Enum.filter(fn {c, _} -> c =~ ~r/[a-zA-Z]/ end)
      |> Enum.map(&elem(&1, 1))

  defp project_word(nil, _, _), do: nil
  defp project_word(word, _, true), do: word

  defp project_word(word, indices, false),
    do:
      word
      |> String.graphemes()
      |> Enum.with_index()
      |> Enum.map_join(fn {c, i} -> if c == " " or i in indices, do: c, else: "_" end)

  defp correct?(guess, word),
    do: String.downcase(String.trim(guess)) == String.downcase(word)

  defp normalize(t), do: t |> String.downcase() |> String.replace(~r/[^\p{L}\p{N}]/u, "")

  defp close?(a, b) do
    x = String.graphemes(normalize(a))
    y = String.graphemes(normalize(b))
    longer = if(length(x) > length(y), do: x, else: y)
    shorter = if(length(x) > length(y), do: y, else: x)

    x != y and
      ((length(x) == length(y) and
          Enum.zip(x, y) |> Enum.count(fn {left, right} -> left != right end) == 1) or
         (abs(length(x) - length(y)) == 1 and
            Enum.any?(0..max(length(x), length(y)), fn i ->
              List.delete_at(longer, i) == shorter
            end)))
  end
end
