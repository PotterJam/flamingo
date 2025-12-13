defmodule Flamingo.Game.Phases.InProgress do
  @behaviour Flamingo.Game.Phase

  alias Flamingo.Game.{Context, Player}

  defstruct [:hints_revealed]

  @type t :: %__MODULE__{
          hints_revealed: non_neg_integer()
        }

  @type draw_event :: map()

  @type action ::
          {:guess, {String.t(), String.t()}}
          | {:chat, {String.t(), String.t()}}
          | {:draw_event, {String.t(), draw_event()}}

  @type effect ::
          {:broadcast_all, :chat, map()}
          | {:broadcast_except, String.t(), :draw_event, map()}
          | {:send_to, String.t(), :word_reveal, map()}
          | {:broadcast_all, :player_correct, map()}
          | {:broadcast_all, :player_update, list(Player.t())}
          | {:broadcast_guessers, :turn_help, map()}
          | {:set_timeout, non_neg_integer()}

  @impl true
  def init(ctx) do
    state = %__MODULE__{hints_revealed: 0}
    {state, ctx, []}
  end

  @impl true
  def handle_action(_state, _ctx, _action, _elapsed) do
    {:error, :not_implemented}
  end

  @impl true
  def handle_timeout(_state, _ctx) do
    {:error, :not_implemented}
  end

  @spec generate_word_outline(String.t(), list(integer())) :: String.t()
  def generate_word_outline(word, revealed_indices \\ []) do
    word
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.map(fn {char, idx} ->
      cond do
        char == " " -> " "
        idx in revealed_indices -> char
        true -> "_"
      end
    end)
    |> Enum.join(" ")
  end
end
