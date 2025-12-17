defmodule Flamingo.Game.GameServer do
  use GenServer

  require Logger

  alias Flamingo.Game.{
    EffectExecutor,
    Settings,
    Player,
    GameState,
    RoundState
  }

  @type room_id :: String.t()

  @type t :: %__MODULE__{
          room_id: room_id(),
          phase: atom(),
          settings: Settings.t(),
          game_state: GameState.t(),
          round_state: RoundState.t() | nil,
          players: %{Player.id() => Player.t()}
        }

  defstruct [
    :room_id,
    :phase,
    :settings,
    :game_state,
    :round_state,
    players: []
  ]

  @spec start_link(room_id()) :: GenServer.on_start()
  def start_link(room_id) do
    GenServer.start_link(__MODULE__, room_id, name: via_tuple(room_id))
  end

  @spec register_player(room_id(), String.t(), pid()) :: {:ok, Player.id()} | {:error, term()}
  def register_player(room_id, player_name, socket_pid) do
    GenServer.call(via_tuple(room_id), {:register_player, player_name, socket_pid})
  end

  @spec unregister_player(room_id(), Player.id()) :: :ok
  def unregister_player(room_id, player_id) do
    GenServer.cast(via_tuple(room_id), {:unregister_player, player_id})
  end

  @spec dispatch(room_id(), term()) :: :ok
  def dispatch(room_id, action) do
    GenServer.cast(via_tuple(room_id), {:dispatch, action})
  end

  defp via_tuple(room_id) do
    {:via, Registry, {Flamingo.RoomRegistry, room_id}}
  end

  @impl true
  def init(room_id) do
    Logger.info("GameServer starting for room #{room_id}")

    state = %__MODULE__{
      room_id: room_id
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:register_player, player_name, socket_pid}, _from, state) do
    player_id = UUID.uuid4()
    ref = Process.monitor(socket_pid)

    players =
      Map.put(state.players, player_id, Player.new(player_name, player_id, socket_pid, ref))

    game_state = GameState.new_player(state.game_state, player_id)

    state = %{state | players: players, game_state: game_state}

    # TODO: tell other players about new player
    # TODO: if in drawing phase add them to yet_to_draw
    {:reply, {:ok, player_id}, state}
  end

  @impl true
  def handle_cast({:unregister_player, player_id}, state) do
    case Map.get(state.players, player_id) do
      nil ->
        {:noreply, state}

      %{ref: ref} ->
        Process.demonitor(ref, [:flush])
        players = Map.delete(state.players, player_id)
        state = %{state | players: players}

        # TODO: tell other players about lost player
        # TODO: if in drawing phase then remove from yet_to_draw
        {:noreply, state}
    end
  end

  def handle_cast({:dispatch, action}, state) do
    {:noreply, dispatch_action(state, action)}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Enum.find(state.players, fn {_id, %{ref: r}} -> r == ref end) do
      {player_id, _} ->
        players = Map.delete(state.players, player_id)
        state = %{state | players: players}
        # TODO: tell other players about lost player
        # TODO: if in drawing phase then remove from yet_to_draw
        {:noreply, state}

      nil ->
        {:noreply, state}
    end
  end

  def handle_info(:timeout, state) do
    if function_exported?(state.phase_module, :handle_timeout, 2) do
      case apply(state.phase_module, :handle_timeout, [state.phase_state, state.context]) do
        {:continue, phase_state, ctx, effects} ->
          state = %{state | phase_state: phase_state, context: ctx, timeout_ref: nil}
          state = maybe_set_timeout(state, effects)
          EffectExecutor.execute_all(effects, state)
          {:noreply, state}

        {:transition, new_module, phase_state, ctx, effects} ->
          state = handle_transition(state, new_module, phase_state, ctx, effects)
          {:noreply, state}
      end
    else
      {:noreply, %{state | timeout_ref: nil}}
    end
  end

  def handle_info(msg, state) do
    Logger.warning("GameServer received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  defp dispatch_action(state, action) do
    elapsed = elapsed_time(state.started_at)

    result =
      apply(state.phase_module, :handle_action, [
        state.phase_state,
        state.context,
        action,
        elapsed
      ])

    case result do
      {:continue, phase_state, ctx, effects} ->
        state = %{state | phase_state: phase_state, context: ctx}
        state = maybe_set_timeout(state, effects)
        EffectExecutor.execute_all(effects, state)
        state

      {:transition, new_module, phase_state, ctx, effects} ->
        handle_transition(state, new_module, phase_state, ctx, effects)

      {:error, reason} ->
        Logger.warning("Phase action failed: #{inspect(reason)}")
        state
    end
  end

  defp handle_transition(state, new_module, _incoming_phase_state, ctx, transition_effects) do
    if state.timeout_ref, do: Process.cancel_timer(state.timeout_ref)

    {phase_state, new_ctx, init_effects} = new_module.init(ctx)

    state = %{
      state
      | phase_module: new_module,
        phase_state: phase_state,
        context: new_ctx,
        started_at: System.monotonic_time(:millisecond),
        timeout_ref: nil
    }

    EffectExecutor.execute_all(transition_effects, state)

    state = maybe_set_timeout(state, init_effects)
    EffectExecutor.execute_all(init_effects, state)

    state
  end

  defp maybe_set_timeout(state, effects) do
    case Enum.find(effects, fn e -> match?({:set_timeout, _}, e) end) do
      {:set_timeout, ms} ->
        ref = Process.send_after(self(), :timeout, ms)
        %{state | timeout_ref: ref}

      nil ->
        state
    end
  end

  defp elapsed_time(started_at), do: System.monotonic_time(:millisecond) - started_at
end
