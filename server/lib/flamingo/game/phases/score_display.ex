defmodule Flamingo.Game.Phases.ScoreDisplay do
  @behaviour Flamingo.Game.Phase

  alias Flamingo.Game.{Context, Player}

  @display_duration_ms 5_000

  defstruct [:round_scores]

  @type t :: %__MODULE__{
          round_scores: %{String.t() => integer()}
        }

  @type action :: :continue

  @type effect ::
          {:broadcast_all, :round_score_display, map()}
          | {:broadcast_all, :turn_end, map()}
          | {:set_timeout, non_neg_integer()}

  @impl true
  def init(ctx) do
    {%__MODULE__{round_scores: %{}}, ctx, []}
  end

  @impl true
  def handle_action(_state, _ctx, _action, _elapsed) do
    {:error, :not_implemented}
  end

  @impl true
  def handle_timeout(_state, _ctx) do
    {:error, :not_implemented}
  end

  def display_duration_ms, do: @display_duration_ms
end
