defmodule Flamingo.DevTools do
  @moduledoc """
  Who may use in-game developer tools, such as changing a game's rules
  mid-game. Any game mode can check it; the allowlist is the
  `:dev_tool_emails` config.
  """

  alias Flamingo.Accounts.Scope

  def allowed?(%Scope{user: %{email: email}}) when is_binary(email),
    do: String.downcase(email) in Application.get_env(:flamingo, :dev_tool_emails, [])

  def allowed?(_scope), do: false
end
