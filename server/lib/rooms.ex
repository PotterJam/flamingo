defmodule Flamingo.Rooms do
  @adjectives "priv/adjectives.txt"
              |> File.read!()
              |> String.split("\n", trim: true)

  @animals "priv/animals.txt"
           |> File.read!()
           |> String.split("\n", trim: true)

  @spec create_room() :: {:ok, String.t()} | {:error, :room_exists | term()}
  def create_room() do
    room_id = generate_room_id()

    # TODO: what patterns exist for logging these errors ergonomically?
    # TODO: Room needs renaming to Game in a lot of places
    case DynamicSupervisor.start_child(
           Flamingo.RoomSupervisor,
           {Flamingo.Game.GameServer, room_id}
         ) do
      {:ok, _pid} -> {:ok, room_id}
      {:error, {:already_started, _pid}} -> {:error, :room_exists}
      {:error, error} -> {:error, error}
    end
  end

  defp generate_room_id() do
    adjective = Enum.random(@adjectives)
    animal = Enum.random(@animals)
    "#{adjective}-#{animal}"
  end
end
