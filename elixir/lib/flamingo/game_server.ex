defmodule Flamingo.GameServer do
  use GenServer

  alias Flamingo.Feed

  defstruct [
    :room_id,
    :host_id,
    :drawer_id,
    :word,
    :phase_timer_ref,
    :turn_end_time,
    phase: :lobby,
    players: %{},
    player_order: [],
    round_count: 3,
    turn_length: 30,
    current_round: 0,
    drawn_this_round: MapSet.new(),
    current_drawing: [],
    word_choices: [],
    correct_guesses: %{},
    revealed_indices: [],
    hint_timer_ref: nil,
    score_gains: %{},
    feed: Feed.new()
  ]

  def start_link(room_id) do
    GenServer.start_link(__MODULE__, room_id, name: via(room_id))
  end

  def join(room_id, player_name) do
    GenServer.call(via(room_id), {:join, player_name})
  catch
    :exit, {:noproc, _} -> {:error, :not_found}
  end

  def rejoin(room_id, player_id) do
    GenServer.call(via(room_id), {:rejoin, player_id})
  catch
    :exit, {:noproc, _} -> {:error, :not_found}
  end

  def leave(room_id, player_id) do
    GenServer.call(via(room_id), {:leave, player_id})
  catch
    :exit, {:noproc, _} -> :ok
  end

  def start_game(room_id, player_id, settings) do
    GenServer.call(via(room_id), {:start_game, player_id, settings})
  end

  def select_word(room_id, player_id, word) do
    GenServer.call(via(room_id), {:select_word, player_id, word})
  end

  def draw_event(room_id, player_id, event) do
    GenServer.cast(via(room_id), {:draw_event, player_id, event})
  end

  def guess(room_id, player_id, text) do
    GenServer.call(via(room_id), {:guess, player_id, text})
  end

  def get_state(room_id) do
    GenServer.call(via(room_id), :get_state)
  catch
    :exit, {:noproc, _} -> {:error, :not_found}
  end

  defp via(room_id) do
    {:via, Registry, {Flamingo.GameRegistry, room_id}}
  end

  @impl true
  def init(room_id) do
    {:ok, %__MODULE__{room_id: room_id}}
  end

  @impl true
  def handle_call({:join, player_name}, _from, state) do
    player_id = generate_player_id()
    player = %{id: player_id, name: player_name, score: 0}

    players = Map.put(state.players, player_id, player)
    player_order = state.player_order ++ [player_id]
    host_id = state.host_id || player_id

    new_state = %{state | players: players, player_order: player_order, host_id: host_id}

    {feed, event} = Feed.player_joined(new_state.feed, player_id, player_name)
    new_state = %{new_state | feed: feed}

    broadcast(
      state.room_id,
      {:players_updated, new_state.players, new_state.player_order, new_state.host_id}
    )

    broadcast(state.room_id, {:feed_event, event})

    {:reply, {:ok, player_id, new_state}, new_state}
  end

  def handle_call({:rejoin, player_id}, _from, state) do
    if Map.has_key?(state.players, player_id) do
      {:reply, {:ok, state}, state}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call({:start_game, player_id, settings}, _from, state) do
    round_count = Map.get(settings, :round_count, state.round_count)
    turn_length = Map.get(settings, :turn_length, state.turn_length)

    with :ok <- validate_host(state, player_id),
         :ok <- validate_player_count(state),
         :ok <- validate_round_count(round_count),
         :ok <- validate_turn_length(turn_length) do
      drawer_id = List.first(state.player_order)

      new_state =
        %{
          state
          | round_count: round_count,
            turn_length: turn_length,
            drawer_id: drawer_id,
            current_round: 0,
            drawn_this_round: MapSet.new()
        }
        |> enter_word_choice()

      {:reply, :ok, new_state}
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({:select_word, player_id, word}, _from, state) do
    cond do
      state.phase != :word_choice ->
        {:reply, {:error, :not_word_choice}, state}

      player_id != state.drawer_id ->
        {:reply, {:error, :not_drawer}, state}

      word not in state.word_choices ->
        {:reply, {:error, :invalid_word}, state}

      true ->
        new_state = enter_playing(state, word)
        {:reply, :ok, new_state}
    end
  end

  def handle_call({:guess, player_id, text}, _from, state) when is_binary(text) do
    cond do
      state.phase != :playing ->
        {:reply, {:error, :not_playing}, state}

      not Map.has_key?(state.players, player_id) ->
        {:reply, {:error, :not_found}, state}

      player_id == state.drawer_id ->
        {:reply, {:error, :drawer_cannot_guess}, state}

      Map.has_key?(state.correct_guesses, player_id) ->
        {:reply, {:error, :already_guessed}, state}

      String.downcase(String.trim(text)) == String.downcase(state.word) ->
        player = Map.get(state.players, player_id)
        correct_guesses = Map.put(state.correct_guesses, player_id, DateTime.utc_now())
        {feed, event} = Feed.correct_guess(state.feed, player_id, player.name)
        new_state = %{state | correct_guesses: correct_guesses, feed: feed}
        broadcast(state.room_id, {:correct_guess, player_id})
        broadcast(state.room_id, {:feed_event, event})

        non_drawers =
          Enum.reject(state.player_order, &(&1 == state.drawer_id))

        all_guessed? =
          Enum.all?(non_drawers, &Map.has_key?(correct_guesses, &1))

        new_state = if all_guessed?, do: enter_turn_reveal(new_state), else: new_state
        {:reply, :correct, new_state}

      true ->
        player = Map.get(state.players, player_id)
        {feed, event} = Feed.guess(state.feed, player_id, player.name, text)
        new_state = %{state | feed: feed}
        broadcast(state.room_id, {:incorrect_guess, player_id, text})
        broadcast(state.room_id, {:feed_event, event})
        {:reply, :incorrect, new_state}
    end
  end

  def handle_call({:guess, _player_id, _text}, _from, state) do
    {:reply, {:error, :invalid_guess}, state}
  end

  def handle_call({:leave, player_id}, _from, state) do
    if not Map.has_key?(state.players, player_id) do
      {:reply, :ok, state}
    else
      player_name = Map.get(state.players, player_id).name
      players = Map.delete(state.players, player_id)
      player_order = List.delete(state.player_order, player_id)

      host_id =
        if state.host_id == player_id,
          do: List.first(player_order),
          else: state.host_id

      correct_guesses = Map.delete(state.correct_guesses, player_id)

      new_state = %{
        state
        | players: players,
          player_order: player_order,
          host_id: host_id,
          correct_guesses: correct_guesses
      }

      {feed, event} = Feed.player_left(new_state.feed, player_id, player_name)
      new_state = %{new_state | feed: feed}

      broadcast(
        state.room_id,
        {:players_updated, new_state.players, new_state.player_order, new_state.host_id}
      )

      broadcast(state.room_id, {:feed_event, event})

      new_state =
        if state.phase == :playing and player_id != state.drawer_id do
          non_drawers = Enum.reject(player_order, &(&1 == state.drawer_id))

          if non_drawers != [] and
               Enum.all?(non_drawers, &Map.has_key?(correct_guesses, &1)) do
            enter_turn_reveal(new_state)
          else
            new_state
          end
        else
          new_state
        end

      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_info({:word_choice_timeout, ref}, %{phase_timer_ref: ref} = state) do
    word = Enum.random(state.word_choices)
    {:noreply, enter_playing(state, word)}
  end

  def handle_info({:word_choice_timeout, _stale_ref}, state) do
    {:noreply, state}
  end

  def handle_info({:playing_timeout, ref}, %{phase_timer_ref: ref} = state) do
    {:noreply, enter_turn_reveal(state)}
  end

  def handle_info({:playing_timeout, _stale_ref}, state) do
    {:noreply, state}
  end

  def handle_info({:turn_reveal_timeout, ref}, %{phase_timer_ref: ref} = state) do
    {:noreply, enter_next_turn(state)}
  end

  def handle_info({:turn_reveal_timeout, _stale_ref}, state) do
    {:noreply, state}
  end

  def handle_info({:reveal_hint, ref}, %{hint_timer_ref: ref} = state) do
    case maybe_reveal_letter(state) do
      {:ok, new_state} ->
        broadcast(state.room_id, {:hint_revealed, new_state.revealed_indices})
        next_ref = schedule_hint_timer()
        {:noreply, %{new_state | hint_timer_ref: next_ref}}

      :maxed ->
        {:noreply, %{state | hint_timer_ref: nil}}
    end
  end

  def handle_info({:reveal_hint, _stale_ref}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_cast(
        {:draw_event, player_id, %{"event_type" => "undo"}},
        %{drawer_id: player_id} = state
      ) do
    boundary_types = MapSet.new(["start", "fill", "clear"])

    idx =
      state.current_drawing
      |> Enum.reverse()
      |> Enum.find_index(fn e -> MapSet.member?(boundary_types, e["event_type"]) end)

    new_drawing =
      case idx do
        nil -> state.current_drawing
        n -> Enum.take(state.current_drawing, length(state.current_drawing) - n - 1)
      end

    new_state = %{state | current_drawing: new_drawing}
    broadcast(state.room_id, {:draw_event, player_id, %{"event_type" => "undo"}})
    {:noreply, new_state}
  end

  def handle_cast({:draw_event, player_id, event}, %{drawer_id: player_id} = state) do
    new_state = %{state | current_drawing: state.current_drawing ++ [event]}
    broadcast(state.room_id, {:draw_event, player_id, event})
    {:noreply, new_state}
  end

  def handle_cast({:draw_event, _player_id, _event}, state) do
    {:noreply, state}
  end

  defp enter_word_choice(state) do
    word_choices = Flamingo.Words.random_choices()
    ref = make_ref()
    Process.send_after(self(), {:word_choice_timeout, ref}, 10_000)
    turn_end_time = DateTime.add(DateTime.utc_now(), 10, :second)

    new_state = %{
      state
      | phase: :word_choice,
        word_choices: word_choices,
        phase_timer_ref: ref,
        turn_end_time: turn_end_time,
        word: nil,
        correct_guesses: %{},
        revealed_indices: [],
        hint_timer_ref: nil
    }

    drawer_name = Map.get(new_state.players, new_state.drawer_id).name
    {feed, event} = Feed.new_turn(new_state.feed, new_state.drawer_id, drawer_name)
    new_state = %{new_state | feed: feed}

    broadcast(
      new_state.room_id,
      {:word_choice_started, new_state.drawer_id, word_choices, turn_end_time,
       new_state.round_count, new_state.turn_length, new_state.current_round}
    )

    broadcast(new_state.room_id, {:feed_event, event})

    new_state
  end

  defp enter_playing(state, word) do
    ref = make_ref()
    Process.send_after(self(), {:playing_timeout, ref}, state.turn_length * 1000)
    turn_end_time = DateTime.add(DateTime.utc_now(), state.turn_length, :second)
    hint_ref = schedule_hint_timer()

    new_state = %{
      state
      | phase: :playing,
        word: word,
        word_choices: [],
        phase_timer_ref: ref,
        turn_end_time: turn_end_time,
        current_drawing: [],
        correct_guesses: %{},
        revealed_indices: [],
        hint_timer_ref: hint_ref
    }

    broadcast(state.room_id, {:turn_started, state.drawer_id, word, turn_end_time})
    new_state
  end

  defp enter_turn_reveal(state) do
    ref = make_ref()
    Process.send_after(self(), {:turn_reveal_timeout, ref}, 5_000)
    turn_end_time = DateTime.add(DateTime.utc_now(), 5, :second)

    score_gains =
      Flamingo.Scoring.calculate_round_scores(
        state.correct_guesses,
        state.drawer_id,
        state.player_order,
        state.turn_length
      )

    players =
      Map.new(state.players, fn {pid, player} ->
        gain = Map.get(score_gains, pid, 0)
        {pid, %{player | score: player.score + gain}}
      end)

    new_state = %{
      state
      | phase: :turn_reveal,
        phase_timer_ref: ref,
        turn_end_time: turn_end_time,
        drawn_this_round: MapSet.put(state.drawn_this_round, state.drawer_id),
        score_gains: score_gains,
        players: players
    }

    {feed, event} = Feed.word_revealed(new_state.feed, state.word)
    new_state = %{new_state | feed: feed}

    broadcast(state.room_id, {:turn_reveal, state.word, turn_end_time, score_gains, players})
    broadcast(state.room_id, {:feed_event, event})
    new_state
  end

  defp enter_next_turn(state) do
    state = %{state | score_gains: %{}}

    next_drawer =
      Enum.find(state.player_order, fn pid ->
        not MapSet.member?(state.drawn_this_round, pid)
      end)

    if next_drawer do
      %{state | drawer_id: next_drawer}
      |> enter_word_choice()
    else
      new_round = state.current_round + 1

      if new_round >= state.round_count do
        enter_game_ended(state)
      else
        %{
          state
          | current_round: new_round,
            drawn_this_round: MapSet.new(),
            drawer_id: List.first(state.player_order)
        }
        |> enter_word_choice()
      end
    end
  end

  defp enter_game_ended(state) do
    new_state = %{
      state
      | phase: :game_ended,
        phase_timer_ref: nil,
        turn_end_time: nil
    }

    broadcast(state.room_id, {:game_ended, state.players})
    new_state
  end

  defp validate_host(state, player_id) do
    if player_id == state.host_id, do: :ok, else: {:error, :not_host}
  end

  defp validate_player_count(state) do
    if map_size(state.players) >= 2, do: :ok, else: {:error, :not_enough_players}
  end

  defp validate_round_count(count) when count >= 1 and count <= 5, do: :ok
  defp validate_round_count(_), do: {:error, :invalid_round_count}

  defp validate_turn_length(length) when length >= 30, do: :ok
  defp validate_turn_length(_), do: {:error, :invalid_turn_length}

  defp generate_player_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  defp schedule_hint_timer do
    ref = make_ref()
    Process.send_after(self(), {:reveal_hint, ref}, 20_000)
    ref
  end

  defp maybe_reveal_letter(state) do
    letter_positions =
      state.word
      |> String.graphemes()
      |> Enum.with_index()
      |> Enum.filter(fn {ch, _idx} -> ch =~ ~r/[a-zA-Z]/ end)
      |> Enum.map(&elem(&1, 1))

    max_reveals = div(length(letter_positions), 2)
    available = Enum.reject(letter_positions, &(&1 in state.revealed_indices))

    if length(state.revealed_indices) < max_reveals and available != [] do
      idx = Enum.random(available)
      {:ok, %{state | revealed_indices: [idx | state.revealed_indices]}}
    else
      :maxed
    end
  end

  defp broadcast(room_id, message) do
    Phoenix.PubSub.broadcast(Flamingo.PubSub, "game:#{room_id}", message)
  end
end
