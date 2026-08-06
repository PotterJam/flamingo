defmodule Flamingo.RoomSupervisor do
  use DynamicSupervisor

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_room(room_id \\ nil) do
    room_id = room_id || Flamingo.RoomId.generate()
    do_start_room(room_id, 3)
  end

  defp do_start_room(_room_id, 0), do: {:error, :failed_to_start}

  defp do_start_room(room_id, retries) do
    case DynamicSupervisor.start_child(__MODULE__, {Flamingo.RoomServer, room_id}) do
      {:ok, _pid} -> {:ok, room_id}
      {:error, {:already_started, _pid}} -> do_start_room(Flamingo.RoomId.generate(), retries - 1)
      error -> error
    end
  end
end
