defmodule Flamingo.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Flamingo.Accounts` context.
  """

  import Ecto.Query

  alias Flamingo.Accounts
  alias Flamingo.Accounts.Scope

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"

  @doc "Claims as Google returns them for a verified account."
  def google_claims(attrs \\ %{}) do
    Enum.into(attrs, %{
      "sub" => "google-#{System.unique_integer([:positive])}",
      "email" => unique_user_email(),
      "email_verified" => true
    })
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} = attrs |> google_claims() |> Accounts.sign_in_with_google()
    user
  end

  def user_scope_fixture do
    user = user_fixture()
    user_scope_fixture(user)
  end

  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    Flamingo.Repo.update_all(
      from(t in Accounts.UserToken,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    Flamingo.Repo.update_all(
      from(ut in Accounts.UserToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end
end
