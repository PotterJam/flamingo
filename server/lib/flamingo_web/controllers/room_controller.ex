defmodule FlamingoWeb.RoomController do
  use FlamingoWeb, :controller

  def create(conn, _params) do
    {:ok, room_id} = Flamingo.Rooms.create_room()

    # TODO: the phoenix way of doing this is a json template, which means can add the camel case encoding to config.ex instead
    json(conn, ProperCase.to_camel_case(%{room_id: room_id}))
  end
end
