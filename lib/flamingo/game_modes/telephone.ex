defmodule Flamingo.GameModes.Telephone do
  @moduledoc "Pure transitions for the Telephone drawing game."

  alias Flamingo.{DrawingShare, Words}

  @categories [:derailment, :best_save, :worst_drawing]

  def new do
    %{
      phase: :lobby,
      participants: %{},
      turn_length: 30,
      custom_words: [],
      include_default_words: false,
      players: %{},
      player_order: [],
      host_id: nil,
      prompt_choices: %{},
      selected_prompts: %{},
      chains: [],
      pass_order: [],
      current_step: nil,
      current_drawings: %{},
      guesses: %{},
      submitted: MapSet.new(),
      reveal_chain_index: nil,
      reveal_entry_index: nil,
      votes: %{},
      awards: %{},
      final_result: nil
    }
  end

  def admit_member(state, %{id: id}, context) do
    participation = if state.phase == :lobby, do: :active, else: :spectator

    ok(%{
      state
      | participants: Map.put(state.participants, id, participation),
        host_id: state.host_id || context.roster.host_id
    })
  end

  def connection_changed(state, _id, _connection, context), do: reconcile(state, context)

  def remove_member(state, id, _removed, context) do
    host_id = if state.host_id == id, do: context.roster.host_id, else: state.host_id

    state = %{
      state
      | participants: Map.delete(state.participants, id),
        host_id: host_id
    }

    reconcile(state, context)
  end

  def start(%{phase: phase}, _settings, _context) when phase not in [:lobby, :game_ended],
    do: {:error, :game_in_progress}

  def start(state, settings, context) do
    roster = context.roster
    turn_length = Map.get(settings, :turn_length, state.turn_length)
    custom_words = Map.get(settings, :custom_words, state.custom_words)
    defaults = Map.get(settings, :include_default_words, state.include_default_words)

    order = Enum.filter(roster.player_order, &online?(roster, &1))

    with true <- context.actor_id == roster.host_id || {:error, :not_host},
         true <- length(order) >= 2 || {:error, :not_enough_players},
         true <- turn_length in 15..120 || {:error, :invalid_turn_length},
         {:ok, custom_words} <- Words.validate_custom_words(custom_words),
         true <- is_boolean(defaults) || {:error, :invalid_include_default_words},
         prompts when is_list(prompts) <-
           context.word_choices.(length(order) * 3, MapSet.new(), custom_words, defaults),
         prompts = Enum.uniq_by(prompts, &prompt_key/1),
         true <- length(prompts) >= length(order) || {:error, :not_enough_prompts} do
      players =
        Map.new(order, fn id ->
          {id, roster.players[id] |> Map.take([:id, :name, :avatar])}
        end)

      prompt_choices = distribute_choices(prompts, order)

      pass_order = random_order(order, context)

      state = %{
        state
        | phase: :telephone_prompt,
          participants: Map.new(roster.player_order, &{&1, participation(&1, order)}),
          turn_length: turn_length,
          custom_words: custom_words,
          include_default_words: defaults,
          players: players,
          player_order: order,
          host_id: roster.host_id,
          prompt_choices: prompt_choices,
          selected_prompts: %{},
          chains: [],
          pass_order: pass_order,
          current_step: nil,
          current_drawings: %{},
          guesses: %{},
          submitted: MapSet.new(),
          reveal_chain_index: nil,
          reveal_entry_index: nil,
          votes: %{},
          awards: %{},
          final_result: nil
      }

      ok(state, :ok, prompt_timers())
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_prompts}
    end
  end

  def command(state, actor, {:select_prompt, prompt}, context) when is_binary(prompt) do
    prompt = String.trim(prompt)
    choices = Map.get(state.prompt_choices, actor, [])

    cond do
      state.phase != :telephone_prompt ->
        {:error, :not_prompt_choice}

      not eligible?(state, actor) ->
        {:error, :spectator}

      MapSet.member?(state.submitted, actor) ->
        {:error, :already_submitted}

      prompt == "" or String.length(prompt) > 100 ->
        {:error, :invalid_prompt}

      prompt not in choices and offered_to_other_player?(state, actor, prompt) ->
        {:error, :prompt_taken}

      selected_prompt?(state, prompt) ->
        {:error, :prompt_taken}

      true ->
        state = %{
          state
          | selected_prompts: Map.put(state.selected_prompts, actor, prompt),
            submitted: MapSet.put(state.submitted, actor)
        }

        reconcile(state, context)
    end
  end

  def command(_state, _actor, {:select_prompt, _prompt}, _context),
    do: {:error, :invalid_prompt}

  def command(state, actor, {:draw, event}, _context) when is_map(event) do
    if state.phase == :telephone_draw and eligible?(state, actor) and
         not MapSet.member?(state.submitted, actor) and valid_draw_event?(event) do
      old = Map.get(state.current_drawings, actor, [])
      drawing = if event["event_type"] == "undo", do: undo(old), else: old ++ [event]

      if drawing == old do
        :ignored
      else
        state = %{state | current_drawings: Map.put(state.current_drawings, actor, drawing)}
        ok(state, :ok, [], %{actor_id: actor, event: event}, :actor)
      end
    else
      :ignored
    end
  end

  def command(_state, _actor, {:draw, _event}, _context), do: {:error, :invalid_draw_event}

  def command(state, actor, :submit_drawing, context) do
    if state.phase == :telephone_draw and eligible?(state, actor) and
         not MapSet.member?(state.submitted, actor) do
      submit(state, actor, nil, context)
    else
      {:error, :cannot_submit}
    end
  end

  def command(state, actor, {:submit_guess, text}, context) when is_binary(text) do
    text = String.trim(text)

    cond do
      state.phase != :telephone_guess -> {:error, :not_guess_phase}
      not eligible?(state, actor) -> {:error, :spectator}
      MapSet.member?(state.submitted, actor) -> {:error, :already_submitted}
      text == "" -> {:error, :invalid_guess}
      String.length(text) > 100 -> {:error, :invalid_guess}
      true -> submit(state, actor, text, context)
    end
  end

  def command(_state, _actor, {:submit_guess, _}, _context), do: {:error, :invalid_guess}

  def command(state, actor, :start_reveal, _context) do
    cond do
      state.phase != :telephone_return -> {:error, :not_return}
      actor != state.host_id -> {:error, :not_host}
      true -> ok(enter_reveal(state))
    end
  end

  def command(state, actor, :advance_reveal, _context) do
    cond do
      state.phase != :telephone_reveal -> {:error, :not_reveal}
      actor != state.host_id -> {:error, :not_host}
      final_reveal?(state) -> finish(state)
      true -> ok(advance_reveal(state))
    end
  end

  def command(state, actor, {:vote, category, entry_id}, _context) do
    with true <- state.phase == :telephone_reveal || {:error, :not_reveal},
         true <- eligible?(state, actor) || {:error, :spectator},
         true <- category in @categories || {:error, :invalid_category},
         {:ok, entry} <- revealed_entry(state, entry_id),
         true <- not is_nil(entry.player_id) || {:error, :invalid_entry},
         true <-
           (category != :worst_drawing or entry.type == :drawing) ||
             {:error, :invalid_entry} do
      votes = Map.put(state.votes, {actor, category}, entry_id)
      ok(%{state | votes: votes})
    else
      {:error, _} = error -> error
    end
  end

  def command(_state, _actor, _command, _context), do: {:error, :invalid_command}

  def timeout(state, :telephone_step, context)
      when state.phase in [:telephone_draw, :telephone_guess],
      do: transition(advance_step(state), context)

  def timeout(%{phase: :telephone_prompt} = state, :telephone_prompt, context),
    do: transition(enter_drawing(state), context)

  def timeout(_state, _key, _context), do: :ignored

  def view(state, viewer, roster) do
    assignment = assignment(state, viewer)

    assignment =
      if assignment && state.phase == :telephone_draw do
        Map.put(assignment, :current_drawing, Map.get(state.current_drawings, viewer, []))
      else
        assignment
      end

    %{
      mode: :telephone,
      phase: state.phase,
      viewer_id: viewer,
      participation: Map.get(state.participants, viewer),
      players: state.players,
      player_order: state.player_order,
      host_id: state.host_id || roster.host_id,
      turn_length: state.turn_length,
      current_step: state.current_step,
      step_count: length(state.player_order),
      submitted_ids: state.submitted,
      prompt_choices:
        if(state.phase == :telephone_prompt and eligible?(state, viewer),
          do: Map.get(state.prompt_choices, viewer, []),
          else: []
        ),
      assignment: assignment,
      reveal: reveal_projection(state),
      votes: viewer_votes(state, viewer),
      vote_counts: vote_counts(state),
      awards: if(state.phase == :game_ended, do: state.awards, else: %{}),
      custom_words:
        if(viewer == (state.host_id || roster.host_id), do: state.custom_words, else: []),
      include_default_words:
        if(viewer == (state.host_id || roster.host_id),
          do: state.include_default_words,
          else: false
        )
    }
  end

  defp submit(state, actor, guess, context) do
    state =
      state
      |> Map.update!(:submitted, &MapSet.put(&1, actor))
      |> maybe_store_guess(actor, guess)

    reconcile(state, context)
  end

  defp maybe_store_guess(state, _actor, nil), do: state

  defp maybe_store_guess(state, actor, guess),
    do: Map.put(state, :guesses, Map.put(Map.get(state, :guesses, %{}), actor, guess))

  defp reconcile(%{phase: :telephone_prompt} = state, context) do
    online = Enum.filter(state.player_order, &online?(context.roster, &1))

    if online != [] and Enum.all?(online, &MapSet.member?(state.submitted, &1)),
      do: transition(enter_drawing(state), context),
      else: ok(state)
  end

  defp reconcile(state, context) when state.phase in [:telephone_draw, :telephone_guess] do
    online = Enum.filter(state.player_order, &online?(context.roster, &1))

    if online != [] and Enum.all?(online, &MapSet.member?(state.submitted, &1)),
      do: transition(advance_step(state), context),
      else: ok(state)
  end

  defp reconcile(state, _context), do: ok(state)

  defp transition({state, timers}, _context), do: ok(state, :ok, timers)

  defp enter_drawing(state) do
    chains =
      state.player_order
      |> Enum.with_index()
      |> Enum.map(fn {origin, index} ->
        prompt =
          Map.get(state.selected_prompts, origin) ||
            state.prompt_choices |> Map.fetch!(origin) |> List.first()

        %{
          id: "telephone-chain-#{index}",
          origin_player_id: origin,
          entries: [entry(index, 0, :prompt, nil, prompt)]
        }
      end)

    state = %{
      state
      | phase: :telephone_draw,
        chains: chains,
        current_step: 0,
        current_drawings: Map.new(state.player_order, &{&1, []}),
        guesses: %{},
        submitted: MapSet.new()
    }

    {state, step_timers(state)}
  end

  defp advance_step(state) do
    n = length(state.player_order)

    chains =
      Enum.reduce(state.player_order, state.chains, fn actor, chains ->
        chain_index = chain_index(state, actor)
        value = contribution(state, actor)
        type = if state.phase == :telephone_draw, do: :drawing, else: :guess

        update_in(
          chains,
          [Access.at(chain_index), :entries],
          &(&1 ++ [entry(chain_index, state.current_step + 1, type, actor, value)])
        )
      end)

    next = state.current_step + 1

    if next >= n do
      {%{
         state
         | phase: :telephone_return,
           chains: chains,
           current_step: nil,
           submitted: MapSet.new(),
           current_drawings: %{},
           reveal_chain_index: nil,
           reveal_entry_index: nil
       }, [:cancel_phase_timeout, :cancel_hint_timeout]}
    else
      phase = if rem(next, 2) == 0, do: :telephone_draw, else: :telephone_guess

      drawings =
        if phase == :telephone_draw, do: Map.new(state.player_order, &{&1, []}), else: %{}

      next_state = %{
        state
        | phase: phase,
          chains: chains,
          current_step: next,
          submitted: MapSet.new(),
          current_drawings: drawings,
          guesses: %{}
      }

      {next_state, step_timers(next_state)}
    end
  end

  defp contribution(%{phase: :telephone_draw} = state, actor) do
    events = Map.get(state.current_drawings, actor, [])

    if MapSet.member?(state.submitted, actor) or events != [],
      do: DrawingShare.compact_ops(events),
      else: nil
  end

  defp contribution(state, actor),
    do: if(MapSet.member?(state.submitted, actor), do: Map.get(state.guesses, actor), else: nil)

  defp assignment(state, actor) when state.phase in [:telephone_draw, :telephone_guess] do
    case chain_index(state, actor) do
      nil ->
        nil

      chain_index ->
        chain = Enum.at(state.chains, chain_index)
        source = List.last(chain.entries)

        %{
          chain_id: chain.id,
          type: if(state.phase == :telephone_draw, do: :drawing, else: :guess),
          source: source
        }
    end
  end

  defp assignment(%{phase: :telephone_return} = state, actor) do
    case Enum.find(state.chains, &(&1.origin_player_id == actor)) do
      nil ->
        nil

      chain ->
        %{
          chain_id: chain.id,
          type: :return,
          origin: List.first(chain.entries),
          source: List.last(chain.entries)
        }
    end
  end

  defp assignment(_state, _actor), do: nil

  defp chain_index(state, actor) do
    case Enum.find_index(state.pass_order, &(&1 == actor)) do
      nil ->
        nil

      actor_index ->
        origin_index = Integer.mod(actor_index - state.current_step, length(state.pass_order))
        origin = Enum.at(state.pass_order, origin_index)
        Enum.find_index(state.player_order, &(&1 == origin))
    end
  end

  defp entry(chain, index, type, player, value),
    do: %{
      id: "telephone-chain-#{chain}-entry-#{index}",
      type: type,
      player_id: player,
      value: value
    }

  defp eligible?(state, actor),
    do: actor in state.player_order and Map.get(state.participants, actor) == :active

  defp participation(id, order), do: if(id in order, do: :active, else: :spectator)

  defp online?(roster, id), do: match?(%{connected: true}, roster.players[id])

  defp step_timers(state),
    do: [
      :cancel_hint_timeout,
      {:schedule_phase_timeout, :telephone_step, state.turn_length * 1000}
    ]

  defp prompt_timers,
    do: [
      :cancel_hint_timeout,
      {:schedule_phase_timeout, :telephone_prompt, 15_000}
    ]

  defp distribute_choices(prompts, order) do
    choices = Map.new(order, &{&1, []})

    prompts
    |> Enum.take(length(order) * 3)
    |> Enum.with_index()
    |> Enum.reduce(choices, fn {prompt, index}, choices ->
      player = Enum.at(order, Integer.mod(index, length(order)))
      Map.update!(choices, player, &(&1 ++ [prompt]))
    end)
  end

  defp offered_to_other_player?(state, actor, prompt) do
    key = prompt_key(prompt)

    state.prompt_choices
    |> Map.delete(actor)
    |> Map.values()
    |> List.flatten()
    |> Enum.any?(&(prompt_key(&1) == key))
  end

  defp selected_prompt?(state, prompt) do
    key = prompt_key(prompt)
    Enum.any?(state.selected_prompts, fn {_player, selected} -> prompt_key(selected) == key end)
  end

  defp prompt_key(prompt), do: prompt |> String.trim() |> String.downcase()

  defp random_order([], _context), do: []

  defp random_order(remaining, context) do
    selected = context.select_candidate.(remaining)
    [selected | random_order(List.delete(remaining, selected), context)]
  end

  defp enter_reveal(state) do
    %{
      state
      | phase: :telephone_reveal,
        reveal_chain_index: 0,
        reveal_entry_index: 0
    }
  end

  defp advance_reveal(state) do
    chain = Enum.at(state.chains, state.reveal_chain_index)

    if state.reveal_entry_index + 1 < length(chain.entries),
      do: %{state | reveal_entry_index: state.reveal_entry_index + 1},
      else: %{state | reveal_chain_index: state.reveal_chain_index + 1, reveal_entry_index: 0}
  end

  defp final_reveal?(state),
    do:
      state.reveal_chain_index == length(state.chains) - 1 and
        state.reveal_entry_index == length(List.last(state.chains).entries) - 1

  defp reveal_projection(%{phase: phase} = state)
       when phase in [:telephone_reveal, :game_ended] do
    chain = Enum.at(state.chains, state.reveal_chain_index || length(state.chains) - 1)

    %{
      chain_index: state.reveal_chain_index,
      entry_index: state.reveal_entry_index,
      chain_count: length(state.chains),
      entry_count: length(chain.entries),
      chain: %{
        chain
        | entries:
            Enum.take(chain.entries, (state.reveal_entry_index || length(chain.entries) - 1) + 1)
      }
    }
  end

  defp reveal_projection(_state), do: nil

  defp revealed_entry(state, id) do
    entries =
      state.chains
      |> Enum.take(state.reveal_chain_index + 1)
      |> Enum.with_index()
      |> Enum.flat_map(fn {chain, i} ->
        Enum.take(
          chain.entries,
          if(i == state.reveal_chain_index,
            do: state.reveal_entry_index + 1,
            else: length(chain.entries)
          )
        )
      end)

    case Enum.find(entries, &(&1.id == id)),
      do: (
        nil -> {:error, :entry_not_revealed}
        entry -> {:ok, entry}
      )
  end

  defp viewer_votes(state, viewer),
    do: Map.new(@categories, &{&1, Map.get(state.votes, {viewer, &1})})

  defp vote_counts(state),
    do:
      Enum.reduce(state.votes, %{}, fn {{_, category}, id}, acc ->
        Map.update(acc, category, %{id => 1}, &Map.update(&1, id, 1, fn n -> n + 1 end))
      end)

  defp finish(state) do
    awards = Map.new(@categories, &{&1, award(state, &1)})

    result = %{
      chains: state.chains,
      players: state.players,
      player_order: state.player_order,
      votes: state.votes,
      awards: awards
    }

    ok(%{state | phase: :game_ended, awards: awards, final_result: result}, :ok, [
      :cancel_phase_timeout,
      :cancel_hint_timeout
    ])
  end

  defp award(state, category) do
    counts = Map.get(vote_counts(state), category, %{})
    ordered = Enum.flat_map(state.chains, & &1.entries)

    case Enum.max_by(ordered, &Map.get(counts, &1.id, 0), fn -> nil end) do
      nil ->
        nil

      entry ->
        if Map.get(counts, entry.id, 0) == 0,
          do: nil,
          else: %{entry: entry, player_id: entry.player_id, votes: counts[entry.id]}
    end
  end

  defp ok(state, reply \\ :ok, timers \\ [], delta \\ nil, scope \\ nil) do
    status = if state.phase == :game_ended, do: {:finished, state.final_result}, else: :continue

    {:ok,
     %{
       state: state,
       reply: reply,
       timers: timers,
       status: status,
       drawing_delta: delta,
       drawing_scope: scope
     }}
  end

  defp undo(events) do
    idx =
      events
      |> Enum.reverse()
      |> Enum.find_index(&(&1["event_type"] in ["start", "fill", "clear"]))

    if idx, do: Enum.take(events, length(events) - idx - 1), else: events
  end

  defp valid_draw_event?(%{"event_type" => type}) when type in ["clear", "undo"], do: true

  defp valid_draw_event?(%{"event_type" => "start"} = event),
    do:
      valid_number?(event["x"]) and valid_number?(event["y"]) and
        valid_pen?(event["color"], event["line_width"])

  defp valid_draw_event?(%{"event_type" => type} = event) when type in ["draw", "end"],
    do:
      Enum.all?(~w(start_x start_y end_x end_y), &valid_number?(event[&1])) and
        valid_pen?(event["color"], event["line_width"])

  defp valid_draw_event?(%{"event_type" => "fill"} = event),
    do: valid_number?(event["x"]) and valid_number?(event["y"]) and valid_color?(event["color"])

  defp valid_draw_event?(_event), do: false
  defp valid_number?(value), do: is_number(value) and value >= -100 and value <= 1_000

  defp valid_pen?(color, width),
    do: valid_color?(color) and is_number(width) and width > 0 and width <= 50

  defp valid_color?(color), do: is_binary(color) and color =~ ~r/^#[0-9A-Fa-f]{6}$/
end
