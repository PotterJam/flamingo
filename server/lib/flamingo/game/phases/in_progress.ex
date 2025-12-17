defmodule Flamingo.Game.Phases.InProgress do
  @behaviour Flamingo.Game.Phase

  require Logger

  alias Flamingo.Game.{Context, Words}

  @selection_timeout_ms 10_000

  defstruct [
    :sub_phase,
    :drawer_id,
    :word_choices,
    :word,
    yet_to_draw: [],
    hints_revealed: 0
  ]

  @type sub_phase :: :word_selection | :drawing

  @type t :: %__MODULE__{
          sub_phase: sub_phase(),
          drawer_id: String.t() | nil,
          word_choices: list(String.t()) | nil,
          word: String.t() | nil,
          yet_to_draw: list(String.t()),
          hints_revealed: non_neg_integer()
        }

  @type draw_event :: map()

  @type action ::
          {:select_word, {String.t(), String.t()}}
          | {:guess, {String.t(), String.t()}}
          | {:chat, {String.t(), String.t()}}
          | {:draw_event, {String.t(), draw_event()}}

  @type effect ::
          {:broadcast_all, atom(), map()}
          | {:broadcast_except, String.t(), atom(), map()}
          | {:send_to, String.t(), atom(), map()}
          | {:broadcast_guessers, atom(), map()}
          | {:set_timeout, non_neg_integer()}

  @impl true
  def init(ctx) do
    yet_to_draw =
      if ctx.current_round == 0 do
        ctx.players |> Enum.map(& &1.id) |> Enum.shuffle()
      else
        []
      end

    [drawer_id | rest] = yet_to_draw
    drawer = Context.get_player(ctx, drawer_id)
    word_choices = Words.random_choices(3)

    new_ctx = %{
      ctx
      | current_round: ctx.current_round + 1,
        current_drawer_id: drawer_id
    }

    state = %__MODULE__{
      sub_phase: :word_selection,
      drawer_id: drawer_id,
      word_choices: word_choices,
      yet_to_draw: rest,
      hints_revealed: 0
    }

    turn_end_time = System.system_time(:millisecond) + @selection_timeout_ms
    base_payload = build_turn_setup_payload(new_ctx, turn_end_time)

    effects = [
      {:send_to, drawer_id, :turn_setup, Map.put(base_payload, :word_choices, word_choices)},
      {:broadcast_except, drawer_id, :turn_setup, Map.put(base_payload, :word_choices, [])},
      {:broadcast_all, :chat,
       %{sender_name: "", message: "#{drawer.name} is choosing a word.", is_system: true}},
      {:set_timeout, @selection_timeout_ms}
    ]

    {state, new_ctx, effects}
  end

  @impl true
  def handle_action(state, ctx, {:select_word, {player_id, word}}, _elapsed) do
    cond do
      state.sub_phase != :word_selection ->
        {:error, :not_in_word_selection}

      player_id != state.drawer_id ->
        {:error, :not_drawer}

      word not in state.word_choices ->
        {:error, :invalid_word}

      true ->
        transition_to_drawing(state, ctx, word)
    end
  end

  def handle_action(state, _ctx, {:guess, _}, _elapsed) when state.sub_phase == :word_selection do
    {:error, :not_in_drawing_phase}
  end

  def handle_action(state, _ctx, {:chat, _}, _elapsed) when state.sub_phase == :word_selection do
    {:error, :not_in_drawing_phase}
  end

  def handle_action(state, _ctx, {:draw_event, _}, _elapsed)
      when state.sub_phase == :word_selection do
    {:error, :not_in_drawing_phase}
  end

  def handle_action(_state, _ctx, _action, _elapsed) do
    {:error, :not_implemented}
  end

  @impl true
  def handle_timeout(state, ctx) when state.sub_phase == :word_selection do
    word = Enum.random(state.word_choices)
    Logger.info("Word selection timeout - auto-selecting: #{word}")
    transition_to_drawing(state, ctx, word)
  end

  def handle_timeout(_state, _ctx) do
    {:error, :not_implemented}
  end

  defp transition_to_drawing(state, ctx, word) do
    turn_end_time = System.system_time(:millisecond) + ctx.round_duration * 1000
    word_outline = generate_word_outline(word)

    base_payload = build_turn_start_payload(ctx, turn_end_time, word_outline)

    effects = [
      {:send_to, state.drawer_id, :turn_start, Map.put(base_payload, :word, word)},
      {:broadcast_except, state.drawer_id, :turn_start, base_payload},
      {:set_timeout, ctx.round_duration * 1000}
    ]

    new_state = %{state | sub_phase: :drawing, word: word, word_choices: nil}
    {:continue, new_state, ctx, effects}
  end

  defp build_turn_setup_payload(ctx, turn_end_time) do
    %{
      game_phase: "RoundSetup",
      current_drawer_id: ctx.current_drawer_id,
      players: build_player_list(ctx),
      turn_end_time: turn_end_time
    }
  end

  defp build_turn_start_payload(ctx, turn_end_time, word_outline) do
    %{
      game_phase: "RoundInProgress",
      current_drawer_id: ctx.current_drawer_id,
      players: build_player_list(ctx),
      turn_end_time: turn_end_time,
      word_outline: word_outline,
      total_rounds: ctx.total_rounds,
      current_round: ctx.current_round
    }
  end

  defp build_player_list(ctx) do
    Enum.map(ctx.players, fn p -> %{id: p.id, name: p.name, score: p.score} end)
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
