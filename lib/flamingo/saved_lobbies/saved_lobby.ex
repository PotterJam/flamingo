defmodule Flamingo.SavedLobbies.SavedLobby do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "saved_lobbies" do
    field :name, :string
    belongs_to :creator, Flamingo.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  A changeset for naming a saved lobby. The name is also its link, so it is
  normalized to lowercase words joined by hyphens.

  ## Options

    * `:validate_unique` - Set to false to skip the database uniqueness check.
      Defaults to `true`.
  """
  def changeset(saved_lobby, attrs, opts \\ []) do
    changeset =
      saved_lobby
      |> cast(attrs, [:name])
      |> update_change(:name, &normalize_name/1)
      |> validate_required([:name])
      |> validate_length(:name, min: 3, max: 30, message: "must be 3 to 30 characters")
      |> validate_format(:name, ~r/^[a-z0-9]+(-[a-z0-9]+)*$/,
        message: "use letters, numbers and single hyphens"
      )

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:name, Flamingo.Repo, message: "is already taken")
      |> unique_constraint(:name, message: "is already taken")
    else
      changeset
    end
  end

  def normalize_name(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/\s+/, "-")
  end
end
