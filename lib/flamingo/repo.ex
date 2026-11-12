defmodule Flamingo.Repo do
  use Ecto.Repo,
    otp_app: :flamingo,
    adapter: Ecto.Adapters.Postgres
end
