defmodule Flamingo.Game.Phases.Lobby do
  @behaviour Flamingo.Game.Phase

  alias Flamingo.Game.{Context, Player}

  defstruct []

  @type t :: %__MODULE__{}

  @type action ::
          {:player_joined, {String.t(), String.t()}}
          | {:player_left, String.t()}
          | {:start_game, %{round_count: pos_integer(), round_duration: pos_integer()}}

  @type effect ::
          {:broadcast_all, :player_update, list(Player.t())}
          | {:send_to, String.t(), :game_info, map()}

  @impl true
  def init(ctx) do
    {%__MODULE__{}, ctx, []}
  end

  @impl true
  def handle_action(_state, _ctx, _action, _elapsed) do
    {:error, :not_implemented}
  end
end
