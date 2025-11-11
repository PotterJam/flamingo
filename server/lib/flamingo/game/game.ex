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
  defstruct [:word, players: [], revealed: [], pending_drawing: [], word_list: []]

  alias Flamingo.Game.Player

  @type t :: %__MODULE__{
          word: String.t() | nil,
          players: list(Player.t()),
          revealed: list(integer()),
          pending_drawing: list(Player.t()),
          word_list: list(String.t())
        }

  # Actions will come in the form `{ :guess, { "player_id", "blah" }`
  # This function will then respond with an array of mutations that have happened, and the updated state
  # Mutations will look like `[{:send_to, {:incorrect_guess, "player_id"}}]`

  @spec new(list(String.t())) :: t()
  def new(word_list) do
    %__MODULE__{word_list: word_list}
  end

  @spec run(t(), {atom(), dynamic()}, non_neg_integer()) :: {list(dynamic()), t()}

  def run(state, {:joined, {player_id, player_name}}, _elapsed) do
    player = Player.new(player_name, player_id)
    new_players = [player | state.players]
    new_pending = [player | state.pending_drawing]

    new_state = %{
      state
      | players: new_players,
        pending_drawing: new_pending
    }

    {[{:players_update, {:new, player}}], new_state}
  end

  def run(state, {:start}, _elapsed) do
    next_drawer = Enum.random(state.pending_drawing)
    still_to_draw = List.delete(state.pending_drawing, next_drawer)

    word_choices = Enum.take_random(state.word_list, 3)

    new_state = %{state | pending_drawing: still_to_draw}

    {[{:word_choices, {next_drawer, word_choices}}], new_state}
  end

  def run(state, {:choose_word, word}, _elapsed) do
    remaining_words = List.delete(state.word_list, word)
    new_state = %{state | word: word, word_list: remaining_words}
    {[{:start_round}], new_state}
  end

  def run(_state, _action, _elapsed) do
    {:error, :unknown_action}
  end
end
