defmodule Flamingo.Room do
  use GenServer

  @impl true
  def init(room_id) do
    initial_state = %{room_id: room_id}
    {:ok, initial_state}
  end

  def start_link(room_id) do
    GenServer.start_link(__MODULE__, room_id, name: via(room_id))
  end

  defp via(room_id), do: {:via, :global, {Flamingo.RoomRegistry, room_id}}
end
