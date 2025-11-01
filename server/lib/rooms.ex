defmodule Server.Rooms do
  @adjectives "priv/adjectives.txt"
              |> File.read!()
              |> String.split("\n", trim: true)

  @animals "priv/animals.txt"
           |> File.read!()
           |> String.split("\n", trim: true)

  def create_room() do
    room_id = generate_room_id()

    # TODO: what patterns exist for logging these errors ergonomically?
    case DynamicSupervisor.start_child(Server.RoomSupervisor, {Server.Room, room_id}) do
      {:ok, _pid} -> {:ok, room_id}
      {:error, {:already_started, _pid}} -> {:error, :room_exists}
      error -> error
    end
  end

  defp generate_room_id() do
    adjective = Enum.random(@adjectives)
    animal = Enum.random(@animals)
    "#{adjective}-#{animal}"
  end
end
