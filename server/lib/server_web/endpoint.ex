defmodule ServerWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :server

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :json],
    pass: ["*/*"],
    json_decoder: Jason
  )

  socket("/ws", ServerWeb.GameSocket, websocket: true, longpoll: false)

  plug(SeverWeb.Router)
end
