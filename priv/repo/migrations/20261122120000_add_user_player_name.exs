defmodule Flamingo.Repo.Migrations.AddUserPlayerName do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :player_name, :string
    end
  end
end
