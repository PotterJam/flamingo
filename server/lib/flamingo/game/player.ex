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
