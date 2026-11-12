defmodule Flamingo.FakeGoogleStrategy do
  @moduledoc """
  Stands in for `Assent.Strategy.Google` in tests. The authorization URL
  carries the state, and the callback's `code` is the JSON of the claims
  Google would return, so a test chooses who signs in.
  """

  def authorize_url(config) do
    state = "state-#{System.unique_integer([:positive])}"
    query = URI.encode_query(redirect_uri: config[:redirect_uri], state: state)

    {:ok,
     %{
       url: "https://accounts.google.test/o/oauth2/auth?" <> query,
       session_params: %{state: state, nonce: "nonce"}
     }}
  end

  def callback(config, %{"state" => state, "code" => code}) do
    case config[:session_params] do
      %{state: ^state} -> {:ok, %{user: JSON.decode!(code), token: %{}}}
      _ -> {:error, :state_mismatch}
    end
  end

  def callback(_config, _params), do: {:error, :access_denied}
end
