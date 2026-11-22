defmodule Flamingo.GameHistory.ScribbleResult do
  use Ecto.Schema

  # A Classic, Roulette or Teams game's details.
  @primary_key false
  @foreign_key_type :binary_id
  schema "scribble_results" do
    belongs_to :game_result, Flamingo.GameHistory.GameResult, primary_key: true
    field :round_count, :integer
  end
end
