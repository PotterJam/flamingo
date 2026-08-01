defmodule Flamingo.RoomServer do
  use GenServer

  alias Flamingo.Feed

  @min_turn_length 15
  @max_turn_length 120

  # Letter hints are revealed evenly across this window of the turn, so every
  # round length gets a full spread of hints rather than a fixed interval that
  # only fits long rounds.
  @hint_window_start 0.35
  @hint_window_end 0.9

  # How long a disconnected player keeps their seat (and score) before being
  # removed. Covers flaky connections and page reloads mid-game.
  @disconnect_grace_ms 60_000

  defstruct [
    :room_id,
    :host_id,
    :drawer_id,
    :word,
    :phase_timer_ref,
    :turn_end_time,
    mode: :scribble,
    phase: :lobby,
    players: %{},
    resume_tokens: %{},
    player_order: [],
    round_count: 3,
    turn_length: 30,
    current_round: 0,
    drawn_this_round: MapSet.new(),
    current_drawing: [],
    word_choices: [],
    custom_words: [],
    include_default_words: false,
    used_words: MapSet.new(),
    correct_guesses: %{},
    revealed_indices: [],
    hint_timer_ref: nil,
    pending_hint_delays: [],
    disconnect_timers: %{},
    connections: %{},
    score_gains: %{},
    final_drawings: [],
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

  def connect(room_id, resume_token) do
    GenServer.call(via(room_id), {:connect, resume_token})
  catch
    :exit, {:noproc, _} -> {:error, :not_found}
  end

  def leave(room_id) do
    GenServer.call(via(room_id), {:leave, self()})
  catch
    :exit, {:noproc, _} -> :ok
  end

  def start_game(room_id, settings) do
    GenServer.call(via(room_id), {:start_game, self(), settings})
  end

  def select_word(room_id, word) do
    GenServer.call(via(room_id), {:select_word, self(), word})
  end

  def draw_event(room_id, event) do
    GenServer.cast(via(room_id), {:draw_event, self(), event})
  end

  def guess(room_id, text) do
    GenServer.call(via(room_id), {:guess, self(), text})
  end

  def get_state(room_id) do
    GenServer.call(via(room_id), :get_state)
  catch
    :exit, {:noproc, _} -> {:error, :not_found}
  end

  def snapshot(room_id) do
    GenServer.call(via(room_id), {:snapshot, self()})
  catch
    :exit, {:noproc, _} -> {:error, :not_found}
  end

  def whereis(room_id) do
    GenServer.whereis(via(room_id))
  end

  @doc """
  Millisecond offsets from turn start at which letters are revealed, spread
  evenly across the middle of the turn. Up to half the word's letters are
  revealed, so shorter rounds and longer words both get useful hints.
  """
  def hint_schedule(word, turn_length) do
    max_reveals = word |> letter_positions() |> length() |> div(2)
    turn_ms = turn_length * 1000
    window = @hint_window_end - @hint_window_start

    for k <- 1..max_reveals//1 do
      trunc(turn_ms * (@hint_window_start + window * (k - 0.5) / max_reveals))
    end
  end

  # Rooms are registered globally so that any clustered node can route calls
  # to the machine actually hosting the room. Fly runs more than one machine,
  # and a reconnecting player's socket may land on any of them.
  defp via(room_id) do
    {:via, :global, {:flamingo_room, room_id}}
  end

  @impl true
  def init(room_id) do
    {:ok, %__MODULE__{room_id: room_id}}
  end

  @impl true
  def handle_call({:join, player_name}, _from, state) do
    player_id = generate_player_id()
    resume_token = generate_resume_token()
    player = %{id: player_id, name: player_name, score: 0, connected: false}

    players = Map.put(state.players, player_id, player)
    resume_tokens = Map.put(state.resume_tokens, resume_token, player_id)
    player_order = state.player_order ++ [player_id]
    host_id = state.host_id || player_id

    new_state = %{
      state
      | players: players,
        resume_tokens: resume_tokens,
        player_order: player_order,
        host_id: host_id
    }

    {feed, _entry} = Feed.player_joined(new_state.feed, player_id, player_name)
    new_state = %{new_state | feed: feed}

    new_state = commit(new_state)
    {:reply, {:ok, resume_token, snapshot_for(new_state, player_id)}, new_state}
  end

  def handle_call({:connect, resume_token}, {pid, _tag}, state) do
    with {:ok, player_id} <- resolve_token(state, resume_token),
         {:ok, new_state} <- connect_pid(state, player_id, pid) do
      new_state =
        if new_state.players != state.players, do: commit(new_state, pid), else: new_state

      {:reply, {:ok, snapshot_for(new_state, player_id)}, new_state}
    else
      _error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call({:snapshot, pid}, _from, state) do
    snapshot_reply(state, player_id_for_connection(state, pid))
  end

  def handle_call({:start_game, pid, settings}, _from, state) do
    start_game(state, player_id_for_connection(state, pid), settings)
  end

  def handle_call({:select_word, pid, word}, _from, state) do
    select_word(state, player_id_for_connection(state, pid), word)
  end

  def handle_call({:guess, pid, text}, _from, state) do
    guess(state, player_id_for_connection(state, pid), text)
  end

  def handle_call({:leave, pid}, _from, state) do
    leave(state, player_id_for_connection(state, pid))
  end

  defp snapshot_reply(state, nil), do: {:reply, {:error, :not_found}, state}

  defp snapshot_reply(state, player_id) do
    {:reply, {:ok, snapshot_for(state, player_id)}, state}
  end

  defp start_game(state, nil, _settings), do: {:reply, {:error, :not_found}, state}

  defp start_game(state, player_id, settings) do
    round_count = Map.get(settings, :round_count, state.round_count)
    turn_length = Map.get(settings, :turn_length, state.turn_length)
    custom_words = Map.get(settings, :custom_words, state.custom_words)

    include_default_words =
      Map.get(settings, :include_default_words, state.include_default_words)

    with :ok <- validate_host(state, player_id),
         :ok <- validate_player_count(state),
         :ok <- validate_round_count(round_count),
         :ok <- validate_turn_length(turn_length),
         {:ok, custom_words} <- Flamingo.Words.validate_custom_words(custom_words),
         :ok <- validate_include_default_words(include_default_words) do
      drawer_id = List.first(state.player_order)

      new_state =
        %{
          state
          | round_count: round_count,
            turn_length: turn_length,
            custom_words: custom_words,
            include_default_words: include_default_words,
            drawer_id: drawer_id,
            current_round: 0,
            drawn_this_round: MapSet.new(),
            used_words: MapSet.new(),
            final_drawings: []
        }
        |> enter_word_choice()

      new_state = commit(new_state)
      {:reply, :ok, new_state}
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  defp select_word(state, nil, _word), do: {:reply, {:error, :not_found}, state}

  defp select_word(state, player_id, word) do
    cond do
      state.phase != :word_choice ->
        {:reply, {:error, :not_word_choice}, state}

      player_id != state.drawer_id ->
        {:reply, {:error, :not_drawer}, state}

      word not in state.word_choices ->
        {:reply, {:error, :invalid_word}, state}

      true ->
        new_state = state |> enter_playing(word) |> commit()
        {:reply, :ok, new_state}
    end
  end

  defp guess(state, nil, _text), do: {:reply, {:error, :not_found}, state}

  defp guess(state, player_id, text) when is_binary(text) do
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
        {feed, _entry} = Feed.correct_guess(state.feed, player_id, player.name)
        new_state = %{state | correct_guesses: correct_guesses, feed: feed}

        new_state =
          if all_connected_guessed?(new_state),
            do: enter_turn_reveal(new_state),
            else: new_state

        {:reply, :correct, commit(new_state)}

      close_guess?(text, state.word) ->
        {feed, _entry} = Feed.close_guess(state.feed, player_id)
        new_state = %{state | feed: feed}
        {:reply, :close, commit(new_state)}

      true ->
        player = Map.get(state.players, player_id)
        {feed, _entry} = Feed.guess(state.feed, player_id, player.name, text)
        new_state = %{state | feed: feed}
        {:reply, :incorrect, commit(new_state)}
    end
  end

  defp guess(state, _player_id, _text), do: {:reply, {:error, :invalid_guess}, state}

  defp leave(state, nil), do: {:reply, :ok, state}

  defp leave(state, player_id) do
    {:reply, :ok, state |> remove_player(player_id) |> commit()}
  end

  @impl true
  def handle_info({:word_choice_timeout, ref}, %{phase_timer_ref: ref} = state) do
    word = Enum.random(state.word_choices)
    {:noreply, state |> enter_playing(word) |> commit()}
  end

  def handle_info({:word_choice_timeout, _stale_ref}, state) do
    {:noreply, state}
  end

  def handle_info({:playing_timeout, ref}, %{phase_timer_ref: ref} = state) do
    {:noreply, state |> enter_turn_reveal() |> commit()}
  end

  def handle_info({:playing_timeout, _stale_ref}, state) do
    {:noreply, state}
  end

  def handle_info({:turn_reveal_timeout, ref}, %{phase_timer_ref: ref} = state) do
    {:noreply, state |> enter_next_turn() |> commit()}
  end

  def handle_info({:turn_reveal_timeout, _stale_ref}, state) do
    {:noreply, state}
  end

  def handle_info({:reveal_hint, ref}, %{phase: :playing, hint_timer_ref: ref} = state) do
    case maybe_reveal_letter(state) do
      {:ok, new_state} ->
        {:noreply, new_state |> schedule_next_hint() |> commit()}

      :maxed ->
        {:noreply, %{state | hint_timer_ref: nil, pending_hint_delays: []}}
    end
  end

  def handle_info({:reveal_hint, _stale_ref}, state) do
    {:noreply, state}
  end

  def handle_info({:remove_player, player_id, ref}, state) do
    player = Map.get(state.players, player_id)

    if player && !player.connected && Map.get(state.disconnect_timers, player_id) == ref do
      {:noreply, state |> remove_player(player_id) |> commit()}
    else
      {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    case state.connections do
      %{^pid => %{player_id: player_id, monitor_ref: ^ref}} ->
        connections = Map.delete(state.connections, pid)
        state = %{state | connections: connections}

        if player_connected?(state, player_id) or not Map.has_key?(state.players, player_id) do
          {:noreply, state}
        else
          {:noreply, state |> mark_disconnected(player_id) |> commit()}
        end

      _connections ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:draw_event, pid, event}, state) do
    {:noreply, draw_event(state, player_id_for_connection(state, pid), event)}
  end

  defp draw_event(state, nil, _event), do: state

  defp draw_event(state, player_id, %{"event_type" => "undo"}) do
    if player_id != state.drawer_id do
      state
    else
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

      if new_drawing == state.current_drawing do
        state
      else
        %{state | current_drawing: new_drawing} |> commit()
      end
    end
  end

  defp draw_event(state, player_id, event) do
    if player_id == state.drawer_id do
      new_state = %{state | current_drawing: state.current_drawing ++ [event]}
      commit(new_state)
    else
      state
    end
  end

  defp connect_pid(state, player_id, pid) do
    case Map.fetch(state.connections, pid) do
      {:ok, %{player_id: ^player_id}} ->
        {:ok, state}

      {:ok, _connection} ->
        {:error, :already_connected}

      :error ->
        ref = Process.monitor(pid)
        connection = %{player_id: player_id, monitor_ref: ref}

        state = %{
          state
          | connections: Map.put(state.connections, pid, connection)
        }

        {:ok, mark_connected(state, player_id)}
    end
  end

  defp player_id_for_connection(state, pid) do
    case Map.get(state.connections, pid) do
      %{player_id: player_id} -> player_id
      nil -> nil
    end
  end

  defp player_connected?(state, player_id) do
    Enum.any?(state.connections, fn {_pid, connection} ->
      connection.player_id == player_id
    end)
  end

  defp mark_connected(state, player_id) do
    player = Map.fetch!(state.players, player_id)

    if player.connected do
      state
    else
      players = Map.put(state.players, player_id, %{player | connected: true})
      disconnect_timers = Map.delete(state.disconnect_timers, player_id)
      new_state = %{state | players: players, disconnect_timers: disconnect_timers}
      new_state
    end
  end

  defp mark_disconnected(state, player_id) do
    player = Map.fetch!(state.players, player_id)
    players = Map.put(state.players, player_id, %{player | connected: false})

    ref = make_ref()
    Process.send_after(self(), {:remove_player, player_id, ref}, @disconnect_grace_ms)
    disconnect_timers = Map.put(state.disconnect_timers, player_id, ref)

    new_state = %{state | players: players, disconnect_timers: disconnect_timers}
    reconcile_turn_completion(new_state, player_id)
  end

  defp remove_player(state, player_id) do
    player_name = Map.get(state.players, player_id).name

    Enum.each(state.connections, fn {_pid, connection} ->
      if connection.player_id == player_id do
        Process.demonitor(connection.monitor_ref, [:flush])
      end
    end)

    connections =
      Map.reject(state.connections, fn {_pid, connection} ->
        connection.player_id == player_id
      end)

    players = Map.delete(state.players, player_id)
    player_order = List.delete(state.player_order, player_id)

    host_id =
      if state.host_id == player_id,
        do: List.first(player_order),
        else: state.host_id

    correct_guesses = Map.delete(state.correct_guesses, player_id)
    disconnect_timers = Map.delete(state.disconnect_timers, player_id)

    resume_tokens =
      Map.reject(state.resume_tokens, fn {_token, seat_id} -> seat_id == player_id end)

    new_state = %{
      state
      | players: players,
        player_order: player_order,
        host_id: host_id,
        resume_tokens: resume_tokens,
        correct_guesses: correct_guesses,
        disconnect_timers: disconnect_timers,
        connections: connections
    }

    {feed, _entry} = Feed.player_left(new_state.feed, player_id, player_name)
    new_state = %{new_state | feed: feed}

    cond do
      state.phase in [:word_choice, :playing] and player_id == state.drawer_id ->
        skip_removed_drawer(new_state)

      state.phase == :playing ->
        reconcile_turn_completion(new_state, player_id)

      true ->
        new_state
    end
  end

  defp skip_removed_drawer(state) do
    case state.phase do
      :word_choice -> enter_next_turn(state)
      :playing -> enter_turn_reveal(state)
    end
  end

  defp reconcile_turn_completion(state, player_id) do
    if state.phase == :playing and player_id != state.drawer_id and
         all_connected_guessed?(state) do
      enter_turn_reveal(state)
    else
      state
    end
  end

  defp all_connected_guessed?(state) do
    connected_guessers =
      Enum.filter(state.player_order, fn pid ->
        pid != state.drawer_id and Map.fetch!(state.players, pid).connected
      end)

    connected_guessers != [] and
      Enum.all?(connected_guessers, &Map.has_key?(state.correct_guesses, &1))
  end

  defp enter_word_choice(state) do
    word_choices =
      Flamingo.Words.random_choices(3, state.used_words,
        custom_words: state.custom_words,
        include_default_words: state.include_default_words
      )

    if word_choices == [] do
      enter_game_ended(state)
    else
      start_word_choice(state, word_choices)
    end
  end

  defp start_word_choice(state, word_choices) do
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
        hint_timer_ref: nil,
        pending_hint_delays: []
    }

    drawer_name = Map.get(new_state.players, new_state.drawer_id).name
    {feed, _entry} = Feed.new_turn(new_state.feed, new_state.drawer_id, drawer_name)
    new_state = %{new_state | feed: feed}

    new_state
  end

  defp enter_playing(state, word) do
    ref = make_ref()
    Process.send_after(self(), {:playing_timeout, ref}, state.turn_length * 1000)
    turn_end_time = DateTime.add(DateTime.utc_now(), state.turn_length, :second)

    new_state =
      %{
        state
        | phase: :playing,
          word: word,
          used_words: MapSet.put(state.used_words, word),
          word_choices: [],
          phase_timer_ref: ref,
          turn_end_time: turn_end_time,
          current_drawing: [],
          correct_guesses: %{},
          revealed_indices: [],
          hint_timer_ref: nil,
          pending_hint_delays: hint_delays(word, state.turn_length)
      }
      |> schedule_next_hint()

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
      |> Map.filter(fn {pid, _gain} -> Map.has_key?(state.players, pid) end)

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
        final_drawings: state.final_drawings ++ [completed_drawing(state)],
        score_gains: score_gains,
        players: players,
        hint_timer_ref: nil,
        pending_hint_delays: []
    }

    {feed, _entry} = Feed.word_revealed(new_state.feed, state.word)
    new_state = %{new_state | feed: feed}

    new_state
  end

  defp enter_next_turn(state) do
    state = %{state | score_gains: %{}}

    next_drawer =
      Enum.find(state.player_order, fn pid ->
        not MapSet.member?(state.drawn_this_round, pid) and
          Map.fetch!(state.players, pid).connected
      end)

    cond do
      next_drawer ->
        %{state | drawer_id: next_drawer}
        |> enter_word_choice()

      state.current_round + 1 >= state.round_count ->
        enter_game_ended(state)

      true ->
        first_connected =
          Enum.find(state.player_order, fn pid ->
            Map.fetch!(state.players, pid).connected
          end)

        if first_connected do
          %{
            state
            | current_round: state.current_round + 1,
              drawn_this_round: MapSet.new(),
              drawer_id: first_connected
          }
          |> enter_word_choice()
        else
          enter_game_ended(state)
        end
    end
  end

  defp enter_game_ended(state) do
    new_state = %{
      state
      | phase: :game_ended,
        phase_timer_ref: nil,
        turn_end_time: nil,
        hint_timer_ref: nil,
        pending_hint_delays: []
    }

    new_state
  end

  # Raw draw events are dropped here: the compact ops are all the game-end
  # screen and share links need, and they're orders of magnitude smaller.
  defp completed_drawing(state) do
    %{
      drawer_id: state.drawer_id,
      word: state.word,
      round_number: state.current_round + 1,
      ops: Flamingo.DrawingShare.compact_ops(state.current_drawing)
    }
  end

  defp validate_host(state, player_id) do
    if player_id == state.host_id, do: :ok, else: {:error, :not_host}
  end

  defp validate_player_count(state) do
    connected_count = Enum.count(state.players, fn {_pid, player} -> player.connected end)
    if connected_count >= 2, do: :ok, else: {:error, :not_enough_players}
  end

  defp validate_round_count(count) when count >= 1 and count <= 5, do: :ok
  defp validate_round_count(_), do: {:error, :invalid_round_count}

  defp validate_turn_length(length)
       when length >= @min_turn_length and length <= @max_turn_length,
       do: :ok

  defp validate_turn_length(_), do: {:error, :invalid_turn_length}

  defp validate_include_default_words(value) when is_boolean(value), do: :ok
  defp validate_include_default_words(_value), do: {:error, :invalid_include_default_words}

  defp generate_player_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  defp generate_resume_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  defp resolve_token(state, resume_token) do
    case Map.fetch(state.resume_tokens, resume_token) do
      {:ok, player_id} when is_map_key(state.players, player_id) -> {:ok, player_id}
      _ -> :error
    end
  end

  defp hint_delays(word, turn_length) do
    {deltas, _prev} =
      word
      |> hint_schedule(turn_length)
      |> Enum.map_reduce(0, fn offset, prev -> {offset - prev, offset} end)

    deltas
  end

  defp schedule_next_hint(%{pending_hint_delays: []} = state) do
    %{state | hint_timer_ref: nil}
  end

  defp schedule_next_hint(%{pending_hint_delays: [delay | rest]} = state) do
    ref = make_ref()
    Process.send_after(self(), {:reveal_hint, ref}, delay)
    %{state | hint_timer_ref: ref, pending_hint_delays: rest}
  end

  defp letter_positions(word) do
    word
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.filter(fn {ch, _idx} -> ch =~ ~r/[a-zA-Z]/ end)
    |> Enum.map(&elem(&1, 1))
  end

  defp maybe_reveal_letter(state) do
    letter_positions = letter_positions(state.word)

    max_reveals = div(length(letter_positions), 2)
    available = Enum.reject(letter_positions, &(&1 in state.revealed_indices))

    if length(state.revealed_indices) < max_reveals and available != [] do
      idx = Enum.random(available)
      {:ok, %{state | revealed_indices: [idx | state.revealed_indices]}}
    else
      :maxed
    end
  end

  defp snapshot_for(state, player_id) do
    word_visible? =
      player_id == state.drawer_id or Map.has_key?(state.correct_guesses, player_id) or
        state.phase in [:turn_reveal, :game_ended]

    %{
      mode: state.mode,
      phase: state.phase,
      viewer_id: player_id,
      players: state.players,
      player_order: state.player_order,
      host_id: state.host_id,
      drawer_id: state.drawer_id,
      round_count: state.round_count,
      turn_length: state.turn_length,
      current_round: state.current_round,
      custom_words: if(player_id == state.host_id, do: state.custom_words, else: []),
      include_default_words:
        if(player_id == state.host_id, do: state.include_default_words, else: false),
      word_choices:
        if(state.phase == :word_choice and player_id == state.drawer_id,
          do: state.word_choices,
          else: []
        ),
      word: project_word(state.word, state.revealed_indices, word_visible?),
      word_visible?: word_visible?,
      turn_end_time: state.turn_end_time,
      correct_guesses: MapSet.new(Map.keys(state.correct_guesses)),
      revealed_indices: state.revealed_indices,
      score_gains: if(state.phase == :turn_reveal, do: state.score_gains, else: %{}),
      current_drawing: state.current_drawing,
      final_drawings: if(state.phase == :game_ended, do: state.final_drawings, else: []),
      feed:
        state.feed.events
        |> Enum.map(&Feed.format(&1, player_id))
        |> Enum.reject(&is_nil/1)
    }
  end

  defp project_word(nil, _revealed_indices, _visible?), do: nil
  defp project_word(word, _revealed_indices, true), do: word

  defp project_word(word, revealed_indices, false) do
    revealed_indices = MapSet.new(revealed_indices)

    word
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.map_join(fn {character, index} ->
      if character == " " or MapSet.member?(revealed_indices, index),
        do: character,
        else: "_"
    end)
  end

  defp commit(state, excluded_pid \\ nil) do
    state.connections
    |> Enum.group_by(fn {_pid, connection} -> connection.player_id end)
    |> Enum.each(fn {player_id, player_connections} ->
      snapshot = snapshot_for(state, player_id)

      Enum.each(player_connections, fn {pid, _connection} ->
        if pid != excluded_pid, do: send(pid, {:room_snapshot, snapshot})
      end)
    end)

    state
  end

  defp close_guess?(guess, word) do
    normalized_guess = normalize_guess(guess)
    normalized_word = normalize_guess(word)

    normalized_guess != normalized_word and
      one_edit_different?(normalized_guess, normalized_word)
  end

  defp normalize_guess(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}]/u, "")
  end

  defp one_edit_different?(left, right) do
    left_chars = String.graphemes(left)
    right_chars = String.graphemes(right)

    cond do
      length(left_chars) == length(right_chars) ->
        one_substitution?(left_chars, right_chars)

      length(left_chars) + 1 == length(right_chars) ->
        one_insert_or_delete?(left_chars, right_chars)

      length(left_chars) == length(right_chars) + 1 ->
        one_insert_or_delete?(right_chars, left_chars)

      true ->
        false
    end
  end

  defp one_substitution?(left_chars, right_chars) do
    left_chars
    |> Enum.zip(right_chars)
    |> Enum.count(fn {left_char, right_char} -> left_char != right_char end) == 1
  end

  defp one_insert_or_delete?(shorter_chars, longer_chars) do
    Enum.any?(0..length(longer_chars), fn index ->
      List.delete_at(longer_chars, index) == shorter_chars
    end)
  end
end
