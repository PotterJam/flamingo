defmodule Server.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Server.RoomRegistry},
      {DynamicSupervisor, name: Server.RoomSupervisor, strategy: :one_for_one},
      ServerWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Server.Supervisor)
  end
end
