defmodule Flamingo.Game.Context do
  alias Flamingo.Game.Player

  defstruct [
    :host_id,
    :round_duration,
    players: [],
    total_rounds: 1,
    current_round: 0,
    drawing_histories: %{}
  ]

  @type t :: %__MODULE__{
          host_id: String.t() | nil,
          round_duration: pos_integer() | nil,
          players: list(Player.t()),
          total_rounds: pos_integer(),
          current_round: non_neg_integer(),
          drawing_histories: %{String.t() => list()}
        }

  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @spec add_player(t(), Player.t()) :: t()
  def add_player(ctx, player) do
    new_players = [player | ctx.players]
    host = ctx.host_id || player.id
    %{ctx | players: new_players, host_id: host}
  end

  @spec remove_player(t(), String.t()) :: t()
  def remove_player(ctx, player_id) do
    new_players = Enum.reject(ctx.players, &(&1.id == player_id))

    new_host_id =
      if ctx.host_id == player_id do
        case List.first(new_players) do
          nil -> nil
          player -> player.id
        end
      else
        ctx.host_id
      end

    %{ctx | players: new_players, host_id: new_host_id}
  end

  @spec get_player(t(), String.t()) :: Player.t() | nil
  def get_player(ctx, player_id) do
    Enum.find(ctx.players, &(&1.id == player_id))
  end

  @spec is_host?(t(), String.t()) :: boolean()
  def is_host?(ctx, player_id) do
    ctx.host_id == player_id
  end
end
