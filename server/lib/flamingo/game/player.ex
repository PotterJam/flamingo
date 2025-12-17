defmodule Flamingo.Game.Player do
  defstruct [:name, :id, :pid, :ref]

  @type id :: String.t()

  @type t :: %__MODULE__{
          name: String.t(),
          id: id(),
          pid: pid(),
          ref: reference()
        }

  @spec new(String.t(), String.t(), pid(), reference()) :: t()
  def new(name, id, pid, ref) do
    %__MODULE__{name: name, id: id, pid: pid, ref: ref}
  end
end
