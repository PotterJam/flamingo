defmodule Flamingo.Repo.Migrations.CreateGameHistory do
  use Ecto.Migration

  def change do
    # Shared by every mode with winners; standings only read these two.
    create table(:game_results, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :saved_lobby_id, references(:saved_lobbies, type: :binary_id, on_delete: :delete_all),
        null: false

      # The lobby's game mode id, such as "classic" or "spellslingers".
      add :mode, :string, null: false
      add :started_at, :utc_datetime, null: false
      add :finished_at, :utc_datetime, null: false
    end

    create index(:game_results, [:saved_lobby_id, :finished_at])

    create table(:game_result_players, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :game_result_id, references(:game_results, type: :binary_id, on_delete: :delete_all),
        null: false

      # Null for guests.
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :name, :string, null: false
      # 1 is a win; null for players who left.
      add :placement, :integer
      # What a score measures is up to the mode.
      add :score, :integer
      # Teams only.
      add :team, :integer
    end

    create index(:game_result_players, [:game_result_id])
    create index(:game_result_players, [:user_id])

    # Classic, Roulette and Teams.
    create table(:scribble_results, primary_key: false) do
      add :game_result_id,
          references(:game_results, type: :binary_id, on_delete: :delete_all),
          primary_key: true

      add :round_count, :integer, null: false
    end

    create table(:scribble_drawings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :game_result_id, references(:game_results, type: :binary_id, on_delete: :delete_all),
        null: false

      add :drawer_id,
          references(:game_result_players, type: :binary_id, on_delete: :delete_all),
          null: false

      add :turn, :integer, null: false
      add :round_number, :integer, null: false
      add :word, :string, null: false
      add :constraint, :string
      add :payload, :text, null: false
      add :thumbs_up, :integer, null: false, default: 0
      add :thumbs_down, :integer, null: false, default: 0
    end

    create index(:scribble_drawings, [:game_result_id])
    create index(:scribble_drawings, [:drawer_id])

    create table(:spellslingers_results, primary_key: false) do
      add :game_result_id,
          references(:game_results, type: :binary_id, on_delete: :delete_all),
          primary_key: true

      add :map, :string, null: false
    end
  end
end
