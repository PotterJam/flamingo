defmodule Flamingo.GameHistory.SpellslingersResult do
  use Ecto.Schema

  # A Spellslingers duel's details.
  @primary_key false
  @foreign_key_type :binary_id
  schema "spellslingers_results" do
    belongs_to :game_result, Flamingo.GameHistory.GameResult, primary_key: true
    field :map, :string
  end
end
