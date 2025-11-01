defmodule Server.Application do
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("starting server")
    children = []
    Supervisor.start_link(children, strategy: :one_for_one, name: Server.Supervisor)
  end
end
