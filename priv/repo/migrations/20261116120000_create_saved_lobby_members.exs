defmodule Flamingo.Repo.Migrations.CreateSavedLobbyMembers do
  use Ecto.Migration

  def change do
    create table(:saved_lobby_members, primary_key: false) do
      add :saved_lobby_id, references(:saved_lobbies, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :last_joined_at, :utc_datetime, null: false
    end

    create index(:saved_lobby_members, [:user_id])
  end
end
