defmodule Flamingo.GameHistory.GameResult do
  use Ecto.Schema

  # One finished game in a saved lobby. Modes keep their own details in their
  # own tables, keyed by this row.
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "game_results" do
    # Ids from `FlamingoWeb.GameModes`, for the modes that have winners.
    field :mode, Ecto.Enum, values: [:classic, :constraint_roulette, :coop, :spellslingers]
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime
    belongs_to :saved_lobby, Flamingo.SavedLobbies.SavedLobby
    has_many :players, Flamingo.GameHistory.GameResultPlayer
    has_one :scribble_result, Flamingo.GameHistory.ScribbleResult
    has_one :spellslingers_result, Flamingo.GameHistory.SpellslingersResult
    has_many :drawings, Flamingo.GameHistory.ScribbleDrawing
  end
end
