defmodule Flamingo.Game.RoundState do
  alias Flamingo.Game.Player

  defstruct [
    :current_drawer_id,
    yet_to_draw: []
  ]

  @type t :: %__MODULE__{
          current_drawer_id: Player.t(),
          yet_to_draw: list(Player.t())
        }

  @spec init(list(Player.t())) :: t()
  def init(players) do
    current_drawer_id = Enum.random(players)
    yet_to_draw = List.delete(players, current_drawer_id)
    %__MODULE__{current_drawer_id: current_drawer_id, yet_to_draw: yet_to_draw}
  end
end
