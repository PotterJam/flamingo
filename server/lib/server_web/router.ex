defmodule ServerWeb.Router do
  use Phoenix.Router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", ServerWeb do
    pipe_through(:api)
    post("/create-room", RoomController, :create)
    get("/:room_id", RoomController, :get)
  end
end
