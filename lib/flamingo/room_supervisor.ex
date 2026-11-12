defmodule Flamingo.RoomSupervisor do
  use DynamicSupervisor

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_room(room_id \\ nil, opts \\ []) do
    room_id = room_id || Flamingo.RoomId.generate()
    do_start_room(room_id, opts, 3)
  end

  defp do_start_room(_room_id, _opts, 0), do: {:error, :failed_to_start}

  defp do_start_room(room_id, opts, retries) do
    case DynamicSupervisor.start_child(__MODULE__, {Flamingo.RoomServer, {room_id, opts}}) do
      {:ok, _pid} ->
        {:ok, room_id}

      {:error, {:already_started, _pid}} ->
        do_start_room(Flamingo.RoomId.generate(), opts, retries - 1)

      :ignore ->
        {:error, :saved_lobby_already_open}

      error ->
        error
    end
  end
end
