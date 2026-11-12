defmodule Flamingo.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users" do
    field :google_sub, :string
    field :email, :string
    field :avatar, :map
    field :authenticated_at, :utc_datetime, virtual: true

    timestamps(type: :utc_datetime)
  end

  @doc """
  A changeset for a Google sign-in. Google's `sub` identifies the account;
  the email is only shown to the user, so it is refreshed on every sign-in.
  """
  def google_changeset(user, attrs) do
    user
    |> cast(attrs, [:google_sub, :email])
    |> validate_required([:google_sub, :email])
  end
end
