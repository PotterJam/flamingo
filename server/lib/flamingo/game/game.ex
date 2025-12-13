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

  # Input actions
  @type joined_action :: {:joined, {String.t(), String.t()}}
  @type start_action :: {:start}
  @type choose_word_action :: {:choose_word, String.t()}
  @type action :: joined_action | start_action | choose_word_action

  # Result actions
  @type players_update :: {:players_update, {:new, Player.t()}}
  @type word_choices :: {:word_choices, {Player.t(), list(String.t())}}
  @type start_round :: {:start_round}
  @type mutation :: players_update | word_choices | start_round

  @spec new(list(String.t())) :: t()
  def new(word_list) do
    %__MODULE__{word_list: word_list}
  end

  @spec run(t(), action(), non_neg_integer()) ::
          {list(mutation()), t()} | {:error, :unknown_action}

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
