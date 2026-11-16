defmodule Flamingo.SavedLobbies do
  @moduledoc """
  Saved lobbies give a room a permanent, named link.
  """

  import Ecto.Query

  alias Flamingo.Accounts.Scope
  alias Flamingo.{Repo, Rooms}
  alias Flamingo.SavedLobbies.{SavedLobby, SavedLobbyMember}

  def get_saved_lobby_by_name(name) when is_binary(name) do
    Repo.get_by(SavedLobby, name: SavedLobby.normalize_name(name))
  end

  @doc """
  Records that the signed-in user is sitting in the named saved lobby's room.
  """
  def record_member(%Scope{user: user}, name) when is_binary(name) do
    now = DateTime.utc_now(:second)

    rows =
      from l in SavedLobby,
        where: l.name == ^name,
        select: %{
          saved_lobby_id: l.id,
          user_id: type(^user.id, :binary_id),
          last_joined_at: type(^now, :utc_datetime)
        }

    Repo.insert_all(SavedLobbyMember, rows,
      on_conflict: {:replace, [:last_joined_at]},
      conflict_target: [:saved_lobby_id, :user_id]
    )

    :ok
  end

  @doc """
  Lists the saved lobbies the user created or has sat in, most recent first.
  """
  def list_saved_lobbies_for_user(%Scope{user: user}) do
    Repo.all(
      from l in SavedLobby,
        left_join: m in SavedLobbyMember,
        on: m.saved_lobby_id == l.id and m.user_id == ^user.id,
        where: l.creator_id == ^user.id or not is_nil(m.user_id),
        order_by: [desc: coalesce(m.last_joined_at, l.inserted_at), asc: l.name],
        select: %{
          name: l.name,
          created?: l.creator_id == ^user.id,
          last_joined_at: type(coalesce(m.last_joined_at, l.inserted_at), :utc_datetime)
        }
    )
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
