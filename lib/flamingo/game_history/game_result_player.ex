defmodule Flamingo.GameHistory.GameResultPlayer do
  use Ecto.Schema

  # A player's result in one game. Placement 1 is a win; players who left have
  # none. Guests have no user. What the score measures is up to the mode, and
  # `team` is set only in Teams games.
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "game_result_players" do
    field :name, :string
    field :placement, :integer
    field :score, :integer
    field :team, :integer
    belongs_to :game_result, Flamingo.GameHistory.GameResult
    belongs_to :user, Flamingo.Accounts.User
  end
end
