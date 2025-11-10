defmodule Flamingo.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Flamingo.RoomRegistry},
      {DynamicSupervisor, name: Flamingo.RoomSupervisor, strategy: :one_for_one},
      FlamingoWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Flamingo.Supervisor)
  end
end
