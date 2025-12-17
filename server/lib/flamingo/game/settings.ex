defmodule Flamingo.Game.Settings do
  defstruct rounds: 1,
            round_length: 45

  @type t :: %__MODULE__{
          rounds: non_neg_integer(),
          round_length: non_neg_integer()
        }

  @spec new(non_neg_integer(), non_neg_integer()) :: t()
  def new(rounds, round_length) do
    %__MODULE__{rounds: rounds, round_length: round_length}
  end
end
