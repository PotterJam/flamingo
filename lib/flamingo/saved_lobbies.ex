defmodule Flamingo.SavedLobbies do
  @moduledoc """
  Saved lobbies give a room a permanent, named link.
  """

  alias Flamingo.Accounts.Scope
  alias Flamingo.{Repo, Rooms}
  alias Flamingo.SavedLobbies.SavedLobby

  def get_saved_lobby_by_name(name) when is_binary(name) do
    Repo.get_by(SavedLobby, name: SavedLobby.normalize_name(name))
  end

  def change_saved_lobby(attrs \\ %{}, opts \\ []) do
    SavedLobby.changeset(%SavedLobby{}, attrs, opts)
  end

  @doc """
  Saves the caller's current room under a new name.

  Must be called from the host's connected process, which the room uses to
  authorize the save. The record is rolled back if the room refuses it.
  """
  def save_room(%Scope{user: user}, room_id, attrs) do
    changeset = SavedLobby.changeset(%SavedLobby{creator_id: user.id}, attrs)

    Repo.transact(fn ->
      with {:ok, saved_lobby} <- Repo.insert(changeset),
           :ok <- Rooms.save_lobby(room_id, saved_lobby.name) do
        {:ok, saved_lobby}
      end
    end)
  end
end
