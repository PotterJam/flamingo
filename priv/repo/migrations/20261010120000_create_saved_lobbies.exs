defmodule Flamingo.Repo.Migrations.CreateSavedLobbies do
  use Ecto.Migration

  def change do
    create table(:saved_lobbies, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :creator_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:saved_lobbies, [:name])
    create index(:saved_lobbies, [:creator_id])
  end
end
