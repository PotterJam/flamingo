defmodule Flamingo.GameServer do
  use GenServer

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
    correct_guesses: %{}
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

    broadcast(
      state.room_id,
      {:players_updated, new_state.players, new_state.player_order, new_state.host_id}
    )

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

      player_id == state.drawer_id ->
        {:reply, {:error, :drawer_cannot_guess}, state}

      Map.has_key?(state.correct_guesses, player_id) ->
        {:reply, {:error, :already_guessed}, state}

      String.downcase(String.trim(text)) == String.downcase(state.word) ->
        correct_guesses = Map.put(state.correct_guesses, player_id, DateTime.utc_now())
        new_state = %{state | correct_guesses: correct_guesses}
        broadcast(state.room_id, {:correct_guess, player_id})

        non_drawer_count = length(state.player_order) - 1
        all_guessed? = map_size(correct_guesses) >= non_drawer_count

        new_state = if all_guessed?, do: enter_turn_reveal(new_state), else: new_state
        {:reply, :correct, new_state}

      true ->
        broadcast(state.room_id, {:incorrect_guess, player_id, text})
        {:reply, :incorrect, state}
    end
  end

  def handle_call({:guess, _player_id, _text}, _from, state) do
    {:reply, {:error, :invalid_guess}, state}
  end

  def handle_call({:leave, player_id}, _from, state) do
    if not Map.has_key?(state.players, player_id) do
      {:reply, :ok, state}
    else
      players = Map.delete(state.players, player_id)
      player_order = List.delete(state.player_order, player_id)

      host_id =
        if state.host_id == player_id,
          do: List.first(player_order),
          else: state.host_id

      new_state = %{state | players: players, player_order: player_order, host_id: host_id}

      broadcast(
        state.room_id,
        {:players_updated, new_state.players, new_state.player_order, new_state.host_id}
      )

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
        correct_guesses: %{}
    }

    broadcast(
      new_state.room_id,
      {:word_choice_started, new_state.drawer_id, word_choices, turn_end_time,
       new_state.round_count, new_state.turn_length, new_state.current_round}
    )

    new_state
  end

  defp enter_playing(state, word) do
    ref = make_ref()
    Process.send_after(self(), {:playing_timeout, ref}, state.turn_length * 1000)
    turn_end_time = DateTime.add(DateTime.utc_now(), state.turn_length, :second)

    new_state = %{
      state
      | phase: :playing,
        word: word,
        word_choices: [],
        phase_timer_ref: ref,
        turn_end_time: turn_end_time,
        current_drawing: [],
        correct_guesses: %{}
    }

    broadcast(state.room_id, {:turn_started, state.drawer_id, word, turn_end_time})
    new_state
  end

  defp enter_turn_reveal(state) do
    ref = make_ref()
    Process.send_after(self(), {:turn_reveal_timeout, ref}, 5_000)
    turn_end_time = DateTime.add(DateTime.utc_now(), 5, :second)

    new_state = %{
      state
      | phase: :turn_reveal,
        phase_timer_ref: ref,
        turn_end_time: turn_end_time,
        drawn_this_round: MapSet.put(state.drawn_this_round, state.drawer_id)
    }

    broadcast(state.room_id, {:turn_reveal, state.word, turn_end_time})
    new_state
  end

  defp enter_next_turn(state) do
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

  defp broadcast(room_id, message) do
    Phoenix.PubSub.broadcast(Flamingo.PubSub, "game:#{room_id}", message)
  end
end
