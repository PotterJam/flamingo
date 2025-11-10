defmodule FlamingoWeb.RoomController do
  use FlamingoWeb, :controller

  def create(conn, _params) do
    {:ok, room_id} = Flamingo.Rooms.create_room()
    json(conn, %{room_id: room_id})
  end
end
