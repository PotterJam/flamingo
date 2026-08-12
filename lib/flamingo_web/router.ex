defmodule FlamingoWeb.Router do
  use FlamingoWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FlamingoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", FlamingoWeb do
    pipe_through :browser

    live "/", HomeLive
    live "/join/:room_code", HomeLive
    live "/game/:room_id", ScribbleLive
    live "/game/:room_id/telephone", TelephoneLive
    live "/drawing", DrawingLive
  end

  # Other scopes may use custom stacks.
  # scope "/api", FlamingoWeb do
  #   pipe_through :api
  # end
end
