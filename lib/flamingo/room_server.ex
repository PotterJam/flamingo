defmodule Flamingo.RoomServer do
  use GenServer

  alias Flamingo.GameModes.Scribble
  alias Flamingo.Room.Members

  @disconnect_grace_ms 60_000

  defstruct [
    :room_id,
    :phase_timer,
    :hint_timer,
    :turn_end_time,
    lifecycle: :lobby,
    members: Members.new(),
    game: Scribble.new(),
    disconnect_timers: %{},
    connections: %{}
  ]

  def start_link(id), do: GenServer.start_link(__MODULE__, id, name: via(id))
  def join(id, name, avatar), do: call(id, {:join, name, avatar}, {:error, :not_found})
  def connect(id, token), do: call(id, {:connect, token}, {:error, :not_found})
  def leave(id), do: call(id, {:leave, self()}, :ok)
  def start_game(id, settings), do: GenServer.call(via(id), {:start_game, self(), settings})
  def select_word(id, word), do: GenServer.call(via(id), {:select_word, self(), word})
  def draw_event(id, event), do: GenServer.cast(via(id), {:draw_event, self(), event})
  def guess(id, text), do: GenServer.call(via(id), {:guess, self(), text})
  def snapshot(id), do: call(id, {:snapshot, self()}, {:error, :not_found})

  defp call(id, message, fallback) do
    GenServer.call(via(id), message)
  catch
    :exit, {:noproc, _} -> fallback
  end

  defp via(id), do: {:via, :global, {:flamingo_room, id}}
  @impl true
  def init(id), do: {:ok, %__MODULE__{room_id: id}}

  @impl true
  def handle_call({:join, name, avatar}, _from, state) do
    id = random(8)
    token = random(32)

    with {:ok, members} <- Members.add(state.members, id, token, name, avatar),
         context = context(state, members),
         {:ok, result} <-
           Scribble.admit_member(state.game, %{id: id, name: name}, context) do
      state =
        %{state | members: members} |> accept(result, context.now) |> commit()

      {:reply, {:ok, token, snapshot_for(state, id)}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:connect, token}, {pid, _}, state) do
    with {:ok, id} <- Members.resolve(state.members, token),
         {:ok, state, transition} <- connect_pid(state, id, pid) do
      state =
        if transition == :became_online,
          do: connection_transition(state, id, :online),
          else: state

      state = if transition == :became_online, do: commit(state, pid), else: state
      {:reply, {:ok, snapshot_for(state, id)}, state}
    else
      _ -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:snapshot, pid}, _, state) do
    case player_id(state, pid) do
      nil -> {:reply, {:error, :not_found}, state}
      id -> {:reply, {:ok, snapshot_for(state, id)}, state}
    end
  end

  def handle_call({:start_game, pid, settings}, _, state),
    do: start_game_call(state, player_id(state, pid), settings)

  def handle_call({:select_word, pid, word}, _, state),
    do: command_call(state, player_id(state, pid), {:select_word, word})

  def handle_call({:guess, pid, text}, _, state),
    do: command_call(state, player_id(state, pid), {:guess, text})

  def handle_call({:leave, pid}, _, state) do
    case player_id(state, pid) do
      nil -> {:reply, :ok, state}
      id -> {:reply, :ok, remove_member(state, id) |> commit()}
    end
  end

  @impl true
  def handle_cast({:draw_event, pid, event}, state) do
    context = context(state)

    case Scribble.command(state.game, player_id(state, pid), {:draw, event}, context) do
      {:ok, result} ->
        Enum.each(state.connections, fn {other, _} ->
          if other != pid, do: send(other, {:draw_event, result.drawing_delta})
        end)

        {:noreply, %{state | game: result.state}}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(
        {:game_timeout, :phase, key, generation},
        %{phase_timer: %{key: key, generation: generation}} = state
      ),
      do: timeout_transition(state, :phase_timer, key)

  def handle_info(
        {:game_timeout, :hint, key, generation},
        %{hint_timer: %{key: key, generation: generation}} = state
      ),
      do: timeout_transition(state, :hint_timer, key)

  def handle_info({:game_timeout, _, _, _}, state), do: {:noreply, state}

  def handle_info({:remove_player, id, generation}, state) do
    if Map.get(state.disconnect_timers, id) == generation and
         match?({:ok, _}, Members.fetch(state.members, id)) and
         not Members.online?(state.members, id),
       do: {:noreply, remove_member(state, id) |> commit()},
       else: {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, pid, _}, state) do
    case state.connections do
      %{^pid => %{player_id: id, monitor_ref: ^ref}} ->
        {:ok, members, transition} = Members.connection_removed(state.members, id)
        state = %{state | connections: Map.delete(state.connections, pid), members: members}

        if transition == :became_offline,
          do:
            {:noreply,
             state |> mark_disconnected(id) |> connection_transition(id, :offline) |> commit()},
          else: {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  defp command_call(state, nil, _), do: {:reply, {:error, :not_found}, state}

  defp command_call(state, id, command) do
    context = context(state)
    run_call(state, Scribble.command(state.game, id, command, context), context.now)
  end

  defp start_game_call(state, nil, _settings), do: {:reply, {:error, :not_found}, state}

  defp start_game_call(state, actor, settings) do
    context = context(state, state.members, actor)
    run_call(state, Scribble.start(state.game, settings, context), context.now)
  end

  defp run_call(state, {:error, reason}, _now), do: {:reply, {:error, reason}, state}
  defp run_call(state, :ignored, _now), do: {:reply, :ok, state}

  defp run_call(state, {:ok, result}, now) do
    state = accept(state, result, now) |> commit()
    {:reply, result.reply, state}
  end

  defp timeout_transition(state, timer_field, key) do
    state = cancel_slot(state, timer_field)
    context = context(state)

    state =
      case Scribble.timeout(state.game, key, context) do
        {:ok, result} -> accept(state, result, context.now)
        _ -> state
      end

    {:noreply, commit(state)}
  end

  defp accept(state, result, now) do
    lifecycle =
      case result.status do
        :continue ->
          if(result.state.phase == :lobby, do: :lobby, else: :playing)

        {:finished, final_result} ->
          {:finished, final_result}
      end

    %{state | game: result.state, lifecycle: lifecycle} |> apply_timers(result.timers, now)
  end

  defp context(state, members \\ nil, actor \\ nil) do
    %{
      roster: Members.snapshot(members || state.members),
      actor_id: actor,
      now: DateTime.utc_now(),
      word_choices: fn n, used, custom, defaults ->
        Flamingo.Words.random_choices(n, used,
          custom_words: custom,
          include_default_words: defaults
        )
      end,
      select_candidate: fn candidates -> Enum.random(candidates) end
    }
  end

  defp connection_transition(state, id, status) do
    context = context(state)
    {:ok, result} = Scribble.connection_changed(state.game, id, status, context)
    accept(state, result, context.now)
  end

  defp remove_member(state, id) do
    {:ok, members, seat} = Members.remove(state.members, id)

    Enum.each(state.connections, fn {_, c} ->
      if c.player_id == id, do: Process.demonitor(c.monitor_ref, [:flush])
    end)

    connections = Map.reject(state.connections, fn {_, c} -> c.player_id == id end)

    state = %{
      state
      | members: members,
        connections: connections,
        disconnect_timers: Map.delete(state.disconnect_timers, id)
    }

    context = context(state)
    {:ok, result} = Scribble.remove_member(state.game, id, %{id: id, name: seat.name}, context)

    accept(state, result, context.now)
  end

  defp connect_pid(state, id, pid) do
    case Map.fetch(state.connections, pid) do
      {:ok, %{player_id: ^id}} ->
        {:ok, state, :unchanged}

      {:ok, _} ->
        {:error, :already_connected}

      :error ->
        ref = Process.monitor(pid)
        {:ok, members, transition} = Members.connection_added(state.members, id)

        {:ok,
         %{
           state
           | members: members,
             connections: Map.put(state.connections, pid, %{player_id: id, monitor_ref: ref}),
             disconnect_timers:
               if(transition == :became_online,
                 do: Map.delete(state.disconnect_timers, id),
                 else: state.disconnect_timers
               )
         }, transition}
    end
  end

  defp mark_disconnected(state, id) do
    generation = make_ref()
    Process.send_after(self(), {:remove_player, id, generation}, @disconnect_grace_ms)
    %{state | disconnect_timers: Map.put(state.disconnect_timers, id, generation)}
  end

  defp apply_timers(state, intents, now),
    do: Enum.reduce(intents, state, &apply_timer(&1, &2, now))

  defp apply_timer(:cancel_phase_timeout, state, _now), do: cancel_slot(state, :phase_timer)
  defp apply_timer(:cancel_hint_timeout, state, _now), do: cancel_slot(state, :hint_timer)

  defp apply_timer({:schedule_phase_timeout, key, delay}, state, now),
    do: schedule(state, :phase_timer, :phase, key, delay, now)

  defp apply_timer({:schedule_hint_timeout, key, delay}, state, now),
    do: schedule(state, :hint_timer, :hint, key, delay, now)

  defp schedule(state, field, slot, key, delay, now) do
    state = cancel_slot(state, field)
    generation = make_ref()
    ref = Process.send_after(self(), {:game_timeout, slot, key, generation}, delay)
    state = Map.put(state, field, %{key: key, generation: generation, ref: ref})

    if slot == :phase,
      do: %{state | turn_end_time: DateTime.add(now, delay, :millisecond)},
      else: state
  end

  defp cancel_slot(state, field) do
    if timer = Map.get(state, field), do: Process.cancel_timer(timer.ref)
    state = Map.put(state, field, nil)
    if field == :phase_timer, do: %{state | turn_end_time: nil}, else: state
  end

  defp player_id(state, pid) do
    case Map.get(state.connections, pid) do
      %{player_id: id} -> id
      nil -> nil
    end
  end

  defp snapshot_for(state, id),
    do:
      Scribble.view(state.game, id, Members.snapshot(state.members))
      |> Map.put(:turn_end_time, state.turn_end_time)

  defp commit(state, excluded \\ nil) do
    state.connections
    |> Enum.group_by(fn {_, c} -> c.player_id end)
    |> Enum.each(fn {id, cs} ->
      snap = snapshot_for(state, id)
      Enum.each(cs, fn {pid, _} -> if pid != excluded, do: send(pid, {:room_snapshot, snap}) end)
    end)

    state
  end

  defp random(n), do: :crypto.strong_rand_bytes(n) |> Base.url_encode64(padding: false)
end
