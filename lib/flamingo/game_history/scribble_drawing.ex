defmodule Flamingo.GameHistory.ScribbleDrawing do
  use Ecto.Schema

  # The id is the one the room gave the drawing when its turn started.
  # `payload` is the drawing's share link encoding (`Flamingo.DrawingShare`).
  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id
  schema "scribble_drawings" do
    field :turn, :integer
    field :round_number, :integer
    field :word, :string
    field :constraint, :string
    field :payload, :string
    field :thumbs_up, :integer
    field :thumbs_down, :integer
    belongs_to :game_result, Flamingo.GameHistory.GameResult
    belongs_to :drawer, Flamingo.GameHistory.GameResultPlayer
  end
end
