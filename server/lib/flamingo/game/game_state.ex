defmodule Flamingo.Game.GameState do
  alias Flamingo.Game.Player

  defstruct [
    :host_id,
    current_round: 0,
    player_scores: %{},
    drawing_histories: %{}
  ]

  @type t :: %__MODULE__{
          host_id: Player.id() | nil,
          current_round: non_neg_integer(),
          player_scores: %{Player.id() => non_neg_integer()},
          drawing_histories: %{Player.id() => list()}
        }

  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @spec new_player(t(), Player.id()) :: t()
  def new_player(state, new_player),
    do: %{state | player_scores: Map.put(state.player_scores, new_player, 0)}

  @spec is_host?(t(), Player.id()) :: boolean()
  def is_host?(ctx, player_id) do
    ctx.host_id == player_id
  end
end
