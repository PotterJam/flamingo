defmodule Flamingo.SavedLobbies.SavedLobbyMember do
  @moduledoc """
  A signed-in account that has sat in a saved lobby's room.
  """

  use Ecto.Schema

  @primary_key false
  @foreign_key_type :binary_id
  schema "saved_lobby_members" do
    belongs_to :saved_lobby, Flamingo.SavedLobbies.SavedLobby, primary_key: true
    belongs_to :user, Flamingo.Accounts.User, primary_key: true
    field :last_joined_at, :utc_datetime
  end
end
