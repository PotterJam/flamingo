defmodule FlamingoWeb.Router do
  use Phoenix.Router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  # TODO: might need to namespace these behind /api so they don't get served html
  # scope "/", ServerWeb do
  #   pipe_through(:api)
  #   post("/create-room", RoomController, :create)
  #   get("/:room_id", RoomController, :get)
  # end

  scope "/", FlamingoWeb do
    post("/create-room", RoomController, :create)
    get("/*path", PageController, :index)
  end
end
