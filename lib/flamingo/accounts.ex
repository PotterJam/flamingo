defmodule Flamingo.Accounts do
  @moduledoc """
  The Accounts context. Google proves who someone is; we keep their account
  and our own revocable login sessions.
  """

  import Ecto.Query, warn: false
  alias Flamingo.Repo

  alias Flamingo.Accounts.{Scope, User, UserToken}

  ## Sign-in

  @doc """
  Finds or creates the account for a Google sign-in and refreshes its email.

  Takes the claims Google returned. Only accounts whose email Google has
  verified may sign in.
  """
  def sign_in_with_google(%{"sub" => sub, "email" => email, "email_verified" => true}) do
    %User{}
    |> User.google_changeset(%{google_sub: sub, email: email})
    |> Repo.insert(
      on_conflict: {:replace, [:email, :updated_at]},
      conflict_target: :google_sub,
      returning: true
    )
  end

  def sign_in_with_google(_claims), do: {:error, :unverified_email}

  ## Settings

  def update_avatar(%Scope{user: user}, avatar) do
    user
    |> Ecto.Changeset.change(avatar: Flamingo.Avatar.normalize(avatar))
    |> Repo.update()
  end

  @doc """
  Deletes the account, returning its session tokens so their sockets can be
  disconnected. Requires a sign-in within the last 10 minutes.
  """
  def delete_user(%Scope{user: user}) do
    if sudo_mode?(user, -10) do
      Repo.transact(fn ->
        tokens = Repo.all_by(UserToken, user_id: user.id)

        with {:ok, _user} <- Repo.delete(user) do
          {:ok, tokens}
        end
      end)
    else
      {:error, :reauthenticate}
    end
  end

  @doc """
  Checks whether the user signed in within the given number of minutes
  (negative, defaulting to 20 minutes ago).
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end
end
