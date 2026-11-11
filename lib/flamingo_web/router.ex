defmodule FlamingoWeb.Router do
  use FlamingoWeb, :router

  import FlamingoWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FlamingoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Local review fixture; remove before shipping.
  if Application.compile_env(:flamingo, :dev_routes) do
    scope "/dev", FlamingoWeb do
      pipe_through :browser
      post "/log-in", UserSessionController, :dev_log_in
    end

    scope "/preview", FlamingoWeb do
      pipe_through :browser
      live "/voting", VotingPreviewLive
      live "/telephone", TelephonePreviewLive
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", FlamingoWeb do
  #   pipe_through :api
  # end

  ## Authentication routes

  scope "/", FlamingoWeb do
    pipe_through [:browser, :require_authenticated_user]

    delete "/users/account", UserSessionController, :delete_account

    live_session :require_authenticated_user,
      on_mount: [{FlamingoWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
    end
  end

  scope "/", FlamingoWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{FlamingoWeb.UserAuth, :mount_current_scope}] do
      live "/", HomeLive
      live "/join/:room_code", HomeLive
      live "/saved-lobby/:saved_lobby_name", HomeLive
      live "/game/:room_id", LobbyLive
      live "/game/:room_id/scribble", ScribbleLive
      live "/game/:room_id/telephone", TelephoneLive
      live "/drawing", DrawingLive
      live "/users/log-in", UserLive.Login, :new
    end

    get "/auth/google", UserSessionController, :google_request
    get "/auth/google/callback", UserSessionController, :google_callback
    delete "/users/log-out", UserSessionController, :delete
  end
end
