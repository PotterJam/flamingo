defmodule Flamingo.Game.Player do
  defstruct [:name, :id, score: 0]

  @type t :: %__MODULE__{
          name: String.t(),
          id: String.t(),
          score: integer()
        }

  @spec new(String.t(), String.t()) :: t()
  def new(name, id) do
    %__MODULE__{name: name, id: id}
  end
end

defmodule Flamingo.Game do
  defstruct [:word, players: [], revealed: []]

  alias Flamingo.Game.Player

  @type t :: %__MODULE__{
          word: String.t(),
          players: list(Player.t()),
          revealed: list(integer())
        }

  # Actions will come in the form `{ :guess, { "player_id", "blah" }`
  # This function will then respond with an array of mutations that have happened, and the updated state
  # Mutations will look like `[{:send_to, {:incorrect_guess, "player_id"}}]`

  @spec run(t(), {atom(), dynamic()}, non_neg_integer()) :: {list(dynamic()), t()}

  def run(state, {:joined, {player_id, player_name}}, _elapsed) do
    new_state = %{
      state
      | players: [Player.new(player_name, player_id) | state.players]
    }

    {[{:players_update, {:new, {player_id, player_name}}}], new_state}
  end

  def run(_state, _action, _elapsed) do
    {:error, :unknown_action}
  end
end
