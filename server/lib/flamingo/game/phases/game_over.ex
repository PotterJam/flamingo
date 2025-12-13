defmodule Flamingo.Game.Phases.GameOver do
  @behaviour Flamingo.Game.Phase

  alias Flamingo.Game.{Context, Player}

  defstruct []

  @type t :: %__MODULE__{}

  @type action :: :return_to_lobby

  @type effect ::
          {:broadcast_all, :game_finished, map()}

  @impl true
  def init(ctx) do
    {%__MODULE__{}, ctx, []}
  end

  @impl true
  def handle_action(_state, _ctx, _action, _elapsed) do
    {:error, :not_implemented}
  end
end
