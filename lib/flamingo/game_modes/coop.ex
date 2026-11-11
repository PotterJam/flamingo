defmodule Flamingo.GameModes.Coop do
  @moduledoc """
  Simultaneous team races on one word, using Scribble for each private canvas
  and guessing turn. One team's drawer picks the word each round, rotating
  through the teams; chat and correct guesses are shared like Classic.
  """

  alias Flamingo.{Feed, GameSettings, Scoring}
  alias Flamingo.GameModes.Scribble

  @shared_events [:guess, :close_guess, :correct_guess, :drawing_vote]

  def new do
    Map.merge(GameSettings.defaults(), %{
      phase: :lobby,
      round_count: 3,
      current_round: 0,
      teams: %{},
      team_scores: %{},
      games: %{},
      picking_team: nil,
      word_choices: [],
      completed: %{},
      gains: %{},
      used_words: MapSet.new(),
      hint_times: %{},
      final_drawings: [],
      final_result: nil,
      feed: Feed.new()
    })
  end

  def admit_member(state, candidate, _context) do
    {feed, _} = Feed.player_joined(state.feed, candidate.id, candidate.name)
    ok(%{state | feed: feed})
  end

  def start(state, settings, context) do
    rounds = Map.get(settings, :round_count, state.round_count)
    ids = Enum.filter(context.roster.player_order, &context.roster.players[&1].connected)

    with true <- context.actor_id == context.roster.host_id || {:error, :not_host},
         true <- length(ids) >= 2 || {:error, :not_enough_players},
         true <- rounds in 1..5 || {:error, :invalid_round_count},
         {:ok, shared} <- GameSettings.validate(settings, state) do
      teams =
        ids
        |> Enum.with_index()
        |> Map.new(fn {id, index} -> {id, min(div(index, 2) + 1, div(length(ids), 2))} end)

      state = Map.merge(state, shared)

      state = %{
        state
        | teams: teams,
          round_count: rounds,
          team_scores: Map.new(Map.values(teams), &{&1, 0})
      }

      begin_round(state, context)
    else
      {:error, _} = error -> error
    end
  end

  def command(state, actor, {:select_word, _} = command, context) do
    team = state.teams[actor]

    cond do
      state.phase != :word_choice or is_nil(state.games[team]) ->
        {:error, :not_word_choice}

      team != state.picking_team ->
        {:error, :not_drawer}

      true ->
        case Scribble.command(
               state.games[team],
               actor,
               command,
               team_context(state, team, context)
             ) do
          {:ok, result} -> choose_word(state, result.state.word, context)
          other -> other
        end
    end
  end

  def command(state, actor, command, context) do
    team = state.teams[actor]
    game = state.games[team]

    cond do
      is_nil(game) ->
        {:error, :spectator}

      state.phase not in [:playing, :turn_reveal] ->
        {:error, :not_playing}

      game.phase != :playing and not match?({:vote_drawing, _}, command) ->
        if match?({:draw, _}, command), do: :ignored, else: {:error, :team_finished}

      true ->
        case Scribble.command(game, actor, command, team_context(state, team, context)) do
          {:ok, result} ->
            state = put_in(state.games[team], result.state) |> relay_feed(game, result.state)

            if result.reply == :correct do
              state = %{state | completed: Map.put(state.completed, team, context.now)}
              state = finish_team(state, team, context) |> update_scores()

              if all_finished?(state),
                do: reveal(state, context, :correct),
                else: ok(state, :correct)
            else
              {:ok,
               Map.put(
                 %{result | state: state, timers: [], status: :continue},
                 :drawing_scope,
                 {:players, team_ids(state, team, context.roster)}
               )}
            end

          other ->
            other
        end
    end
  end

  def timeout(%{phase: :word_choice} = state, :word_choice, context),
    do: choose_word(state, context.select_candidate.(state.word_choices), context)

  def timeout(%{phase: :playing} = state, :playing, context), do: reveal(state, context)

  def timeout(%{phase: :turn_reveal} = state, :turn_reveal, context) do
    drawings =
      Enum.flat_map(Enum.sort(state.games), fn {_, game} ->
        Enum.map(game.final_drawings, &%{&1 | round_number: state.current_round + 1})
      end)

    state = %{state | final_drawings: state.final_drawings ++ drawings}

    if state.current_round + 1 >= state.round_count,
      do: finish_game(state, context.roster),
      else: begin_round(%{state | current_round: state.current_round + 1}, context)
  end

  def timeout(%{phase: :playing} = state, :reveal_hint, context) do
    state =
      Enum.reduce(state.hint_times, state, fn {team, times}, acc ->
        {due, remaining} = Enum.split_while(times, &(DateTime.compare(&1, context.now) != :gt))

        acc =
          Enum.reduce(due, acc, fn _, acc ->
            case Scribble.timeout(acc.games[team], :reveal_hint, team_context(acc, team, context)) do
              {:ok, result} -> put_in(acc.games[team], result.state)
              _ -> acc
            end
          end)

        put_in(acc.hint_times[team], remaining)
      end)

    ok(state, :ok, hint_timer(state, context.now))
  end

  def timeout(_, _, _), do: :ignored

  # Like Scribble, a brief disconnect (such as a refresh) keeps the team racing;
  # only removal after the grace period ends a team's turn.
  def connection_changed(state, _, _, _), do: ok(state)

  def remove_member(state, id, removed, context) do
    {feed, _} = Feed.player_left(state.feed, id, removed.name)
    state = %{state | feed: feed}
    team = state.teams[id]
    game = state.games[team]

    cond do
      not ((state.phase in [:word_choice, :playing] and game) &&
               (id == game.drawer_id or team_ids(state, team, context.roster) == [game.drawer_id])) ->
        ok(state)

      # Before drawing starts, a team that can no longer play sits the round out;
      # if it was choosing, the word is picked for everyone.
      state.phase == :word_choice ->
        state = %{state | games: Map.delete(state.games, team)}

        if team == state.picking_team,
          do: choose_word(state, context.select_candidate.(state.word_choices), context),
          else: ok(state)

      true ->
        state = finish_team(state, team, context)
        if all_finished?(state), do: reveal(state, context), else: ok(state)
    end
  end

  def view(state, viewer, roster) do
    team = state.teams[viewer]
    game = state.games[team]
    child = game || Scribble.new()

    local_roster =
      if game,
        do: team_roster(state, team, roster),
        else: %{roster | players: %{}, player_order: []}

    view = Scribble.view(child, viewer, local_roster)
    result = state.final_result
    players = Map.new(roster.players, fn {id, player} -> {id, Map.put(player, :score, 0)} end)
    picker = state.games[state.picking_team]

    # Everyone sees every vote; a vote on another team's drawing names that team
    # and does not flash this viewer's canvas.
    feed =
      state.feed.events
      |> Enum.map(fn
        %{event: {:drawing_vote, id, name, vote}} = entry ->
          if state.teams[id] == team do
            Feed.format(entry, viewer)
          else
            verb = if vote == :up, do: "liked", else: "disliked"

            entry
            |> Feed.format(viewer)
            |> Map.merge(%{
              text: "#{name} #{verb} Team #{state.teams[id]}'s drawing",
              own_drawing?: false
            })
          end

        entry ->
          Feed.format(entry, viewer)
      end)
      |> Enum.reject(&is_nil/1)

    Map.merge(view, %{
      mode: :coop,
      game_variant: :coop,
      phase: state.phase,
      participation: if(game, do: :active, else: :spectator),
      players: players,
      player_order: roster.player_order,
      host_id: roster.host_id,
      teams: if(result, do: result.teams, else: Map.take(state.teams, roster.player_order)),
      team_scores: state.team_scores,
      team_gains: state.gains,
      team_drawers: Enum.map(state.games, fn {_, game} -> game.drawer_id end),
      word_picker_id: picker && picker.drawer_id,
      word_choices: if(team == state.picking_team, do: view.word_choices, else: []),
      correct_guesses:
        state.games
        |> Map.values()
        |> Enum.flat_map(&Map.keys(&1.correct_guesses))
        |> MapSet.new(),
      feed: feed,
      team_finished?: game != nil and game.phase == :turn_reveal,
      can_guess?:
        game != nil and game.phase == :playing and state.phase == :playing and
          viewer != game.drawer_id,
      current_round: state.current_round,
      round_count: state.round_count,
      turn_length: state.turn_length,
      word_list: state.word_list,
      score_gains: %{},
      final_players: if(result, do: result.players, else: %{}),
      final_player_order: if(result, do: result.player_order, else: []),
      final_drawings: if(result, do: result.drawings, else: [])
    })
  end

  defp begin_round(state, context) do
    choices =
      context.word_choices.(3, state.used_words,
        custom_words: state.custom_words,
        include_default_words: state.include_default_words,
        word_list: state.word_list
      )

    games =
      state.team_scores
      |> Map.keys()
      |> Enum.sort()
      |> Enum.flat_map(fn team ->
        ids =
          team_ids(state, team, context.roster)
          |> Enum.filter(&context.roster.players[&1].connected)

        if length(ids) >= 2 and choices != [] do
          drawer = Enum.at(ids, rem(state.current_round, length(ids)))
          roster = team_roster(state, team, context.roster)

          roster = %{
            roster
            | host_id: drawer,
              player_order: [drawer | List.delete(roster.player_order, drawer)]
          }

          local = %{
            context
            | roster: roster,
              actor_id: drawer,
              word_choices: fn _, _, _ -> choices end
          }

          child =
            Enum.reduce(roster.player_order, Scribble.new(), fn id, child ->
              {:ok, result} = Scribble.admit_member(child, roster.players[id], local)
              result.state
            end)

          {:ok, result} =
            Scribble.start(
              child,
              Map.take(state, [:turn_length, :custom_words, :include_default_words, :word_list]),
              local
            )

          [{team, result.state}]
        else
          []
        end
      end)
      |> Map.new()

    teams = games |> Map.keys() |> Enum.sort()

    state = %{
      state
      | games: games,
        picking_team:
          if(teams != [], do: Enum.at(teams, rem(state.current_round, length(teams)))),
        word_choices: choices,
        completed: %{},
        gains: %{},
        hint_times: %{},
        phase: :word_choice
    }

    if games == %{},
      do: finish_game(state, context.roster),
      else:
        ok(state, :ok, [:cancel_hint_timeout, {:schedule_phase_timeout, :word_choice, 10_000}])
  end

  # Every team draws the word the picking team chose.
  defp choose_word(state, word, context) do
    games =
      Map.new(state.games, fn {team, game} ->
        if game.phase == :word_choice do
          {:ok, result} =
            Scribble.command(
              game,
              game.drawer_id,
              {:select_word, word},
              team_context(state, team, context)
            )

          {team, result.state}
        else
          {team, game}
        end
      end)

    begin_playing(%{state | games: games, word_choices: []}, context)
  end

  defp all_finished?(state),
    do: Enum.all?(state.games, fn {_, game} -> game.phase == :turn_reveal end)

  defp begin_playing(state, context) do
    hints =
      Map.new(state.games, fn {team, game} ->
        {team,
         if(game.phase == :playing,
           do:
             Enum.map(
               Scribble.hint_schedule(game.word, state.turn_length),
               &DateTime.add(context.now, &1, :millisecond)
             ),
           else: []
         )}
      end)

    state = %{
      state
      | phase: :playing,
        hint_times: hints,
        used_words:
          Enum.reduce(state.games, state.used_words, fn {_, game}, used ->
            MapSet.put(used, game.word)
          end)
    }

    if all_finished?(state),
      do: reveal(state, context),
      else:
        ok(state, :ok, [
          {:schedule_phase_timeout, :playing, state.turn_length * 1000}
          | hint_timer(state, context.now)
        ])
  end

  defp finish_team(state, team, context) do
    if state.games[team].phase == :playing do
      {:ok, result} =
        Scribble.timeout(state.games[team], :playing, team_context(state, team, context))

      put_in(state.games[team], result.state)
    else
      state
    end
  end

  defp update_scores(state) do
    gains = Scoring.calculate_guesser_scores(state.completed, state.turn_length)

    scores =
      Map.new(state.team_scores, fn {team, score} ->
        {team, score - Map.get(state.gains, team, 0) + Map.get(gains, team, 0)}
      end)

    %{state | gains: gains, team_scores: scores}
  end

  defp reveal(state, context, reply \\ :ok) do
    state = Enum.reduce(Map.keys(state.games), state, &finish_team(&2, &1, context))

    state =
      case Enum.find_value(state.games, fn {_, game} -> game.word end) do
        nil -> state
        word -> %{state | feed: elem(Feed.word_revealed(state.feed, word), 0)}
      end

    ok(%{state | phase: :turn_reveal, hint_times: %{}}, reply, [
      :cancel_hint_timeout,
      {:schedule_phase_timeout, :turn_reveal, 5_000}
    ])
  end

  defp finish_game(state, roster) do
    teams = Map.take(state.teams, roster.player_order)

    players =
      Map.new(roster.players, fn {id, player} ->
        drawings = Enum.filter(state.final_drawings, &(&1.drawer_id == id))

        {id,
         player
         |> Map.take([:id, :name, :avatar])
         |> Map.merge(%{
           score: 0,
           thumbs_up: Enum.sum(Enum.map(drawings, & &1.thumbs_up)),
           thumbs_down: Enum.sum(Enum.map(drawings, & &1.thumbs_down))
         })}
      end)

    order = Enum.sort_by(roster.player_order, &(-Map.get(state.team_scores, teams[&1], 0)))

    result = %{
      players: players,
      player_order: order,
      drawings: state.final_drawings,
      teams: teams
    }

    ok(%{state | phase: :game_ended, final_result: result}, :ok, [
      :cancel_phase_timeout,
      :cancel_hint_timeout
    ])
  end

  defp hint_timer(state, now) do
    times = state.hint_times |> Map.values() |> List.flatten()

    case Enum.min_by(times, &DateTime.to_unix(&1, :millisecond), fn -> nil end) do
      nil ->
        [:cancel_hint_timeout]

      time ->
        [{:schedule_hint_timeout, :reveal_hint, max(1, DateTime.diff(time, now, :millisecond))}]
    end
  end

  # Chat is shared across teams; a team's private word reveal is not.
  defp relay_feed(state, old_game, new_game) do
    feed =
      new_game.feed.events
      |> Enum.filter(&(&1.id >= old_game.feed.next_id and elem(&1.event, 0) in @shared_events))
      |> Enum.reduce(state.feed, &elem(Feed.add(&2, &1.event), 0))

    %{state | feed: feed}
  end

  defp team_ids(state, team, roster),
    do: Enum.filter(roster.player_order, &(state.teams[&1] == team and not is_nil(team)))

  defp team_roster(state, team, roster) do
    ids = team_ids(state, team, roster)
    %{roster | players: Map.take(roster.players, ids), player_order: ids}
  end

  defp team_context(state, team, context),
    do: %{context | roster: team_roster(state, team, context.roster)}

  defp ok(state, reply \\ :ok, timers \\ []) do
    {:ok,
     %{
       state: state,
       reply: reply,
       timers: timers,
       drawing_delta: nil,
       status:
         if(state.phase == :game_ended, do: {:finished, state.final_result}, else: :continue)
     }}
  end
end
