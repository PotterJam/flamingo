defmodule Flamingo.Game.Phases.Lobby do
  @behaviour Flamingo.Game.Phase

  require Logger

  alias Flamingo.Game.{Context, Player}

  defstruct []

  @type t :: %__MODULE__{}

  @impl true
  def init(ctx) do
    {%__MODULE__{}, ctx, []}
  end

  @impl true
  def handle_action(state, ctx, {:player_joined, {player_id, player_name}}, _elapsed) do
    player = Player.new(player_name, player_id)
    new_ctx = Context.add_player(ctx, player)

    effects = [
      {:send_to, player_id, :game_info, game_info(new_ctx, player_id)},
      {:broadcast_all, :player_update, player_list(new_ctx)}
    ]

    {:continue, state, new_ctx, effects}
  end

  def handle_action(state, ctx, {:player_left, player_id}, _elapsed) do
    new_ctx = Context.remove_player(ctx, player_id)

    effects = [
      {:broadcast_all, :player_update, player_list(new_ctx)}
    ]

    {:continue, state, new_ctx, effects}
  end

  def handle_action(_state, ctx, {:start_game, player_id, config}, _elapsed) do
    cond do
      not Context.is_host?(ctx, player_id) ->
        {:error, :not_host}

      length(ctx.players) < 2 ->
        {:error, :not_enough_players}

      true ->
        new_ctx = %{ctx | total_rounds: config.round_count, round_duration: config.round_duration}
        {:transition, Flamingo.Game.Phases.WordSelection, %{}, new_ctx, []}
    end
  end

  def handle_action(_state, _ctx, action, _elapsed) do
    Logger.warning("Lobby received unknown action: #{inspect(action)}")
    {:error, :unknown_action}
  end

  defp game_info(ctx, player_id) do
    %{
      host_id: ctx.host_id,
      is_host: Context.is_host?(ctx, player_id),
      players: player_list(ctx)
    }
  end

  defp player_list(ctx) do
    Enum.map(ctx.players, fn p -> %{id: p.id, name: p.name, score: p.score} end)
  end
end
