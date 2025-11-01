defmodule ServerWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :server

  # TODO: not sure what files to whitelist yet
  plug(Plug.Static,
    at: "/",
    from: :server,
    gzip: false,
    only: ~w(assets)
  )

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :json],
    pass: ["*/*"],
    json_decoder: Jason
  )

  # socket("/ws", ServerWeb.GameSocket, websocket: true, longpoll: false)

  plug(ServerWeb.Router)
end
