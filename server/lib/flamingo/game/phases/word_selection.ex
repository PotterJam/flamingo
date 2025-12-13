defmodule Flamingo.Game.Phases.WordSelection do
  @behaviour Flamingo.Game.Phase

  alias Flamingo.Game.{Context, Player}

  @word_choice_count 3
  @selection_timeout_ms 10_000

  defstruct [:drawer, :word_choices]

  @type t :: %__MODULE__{
          drawer: Player.t(),
          word_choices: list(String.t())
        }

  @type action :: {:select_word, String.t()}

  @type effect ::
          {:send_to, String.t(), :turn_setup, map()}
          | {:broadcast_except, String.t(), :turn_setup, map()}
          | {:set_timeout, non_neg_integer()}

  @impl true
  def init(ctx) do
    {%__MODULE__{}, ctx, []}
  end

  @impl true
  def handle_action(_state, _ctx, _action, _elapsed) do
    {:error, :not_implemented}
  end

  @impl true
  def handle_timeout(_state, _ctx) do
    {:error, :not_implemented}
  end

  def word_choice_count, do: @word_choice_count
  def selection_timeout_ms, do: @selection_timeout_ms
end
