defmodule Flamingo.GameModes.Coop do
  @moduledoc "Simultaneous team races, using Scribble for each private canvas and guessing turn."

  alias Flamingo.{GameSettings, Scoring}
  alias Flamingo.GameModes.Scribble

  def new do
    Map.merge(GameSettings.defaults(), %{
      phase: :lobby,
      round_count: 3,
      current_round: 0,
      teams: %{},
      team_scores: %{},
      games: %{},
      completed: %{},
      gains: %{},
      used_words: MapSet.new(),
      hint_times: %{},
      final_drawings: [],
      final_result: nil
    })
  end

  def admit_member(state, _candidate, _context), do: ok(state)

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

    if state.phase == :word_choice and state.games[team] do
      case Scribble.command(state.games[team], actor, command, team_context(state, team, context)) do
        {:ok, result} ->
          state = put_in(state.games[team], result.state)
          if choices_complete?(state), do: begin_playing(state, context), else: ok(state)

        other ->
          other
      end
    else
      {:error, :not_word_choice}
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
            state = put_in(state.games[team], result.state)

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

  def timeout(%{phase: :word_choice} = state, :word_choice, context) do
    games =
      Map.new(state.games, fn {team, game} ->
        if game.phase == :word_choice do
          {:ok, result} = Scribble.timeout(game, :word_choice, team_context(state, team, context))
          {team, result.state}
        else
          {team, game}
        end
      end)

    begin_playing(%{state | games: games}, context)
  end

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

  def connection_changed(state, id, :offline, context), do: reconcile(state, id, context)
  def connection_changed(state, _, :online, _), do: ok(state)
  def remove_member(state, id, _removed, context), do: reconcile(state, id, context)

  defp reconcile(state, id, context) do
    team = state.teams[id]
    game = state.games[team]

    online =
      Enum.filter(team_ids(state, team, context.roster), &context.roster.players[&1].connected)

    if (state.phase in [:word_choice, :playing] and game) &&
         (id == game.drawer_id or Enum.all?(online, &(&1 == game.drawer_id))) do
      state =
        if game.phase == :word_choice do
          {:ok, result} = Scribble.timeout(game, :word_choice, team_context(state, team, context))
          put_in(state.games[team], result.state)
        else
          state
        end

      state = finish_team(state, team, context)

      cond do
        state.phase == :word_choice and choices_complete?(state) -> begin_playing(state, context)
        state.phase == :playing and all_finished?(state) -> reveal(state, context)
        true -> ok(state)
      end
    else
      ok(state)
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

    state = %{
      state
      | games: games,
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

  defp choices_complete?(state),
    do: Enum.all?(state.games, fn {_, game} -> game.phase != :word_choice end)

  defp all_finished?(state),
    do: Enum.all?(state.games, fn {_, game} -> game.phase == :turn_reveal end)

  defp begin_playing(state, context) do
    words = Enum.map(state.games, fn {_, game} -> game.word end)

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
        used_words: Enum.reduce(words, state.used_words, &MapSet.put(&2, &1))
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
