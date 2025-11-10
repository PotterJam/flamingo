defmodule FlamingoWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :flamingo

  # TODO: not sure what files to whitelist yet
  plug(Plug.Static,
    at: "/",
    from: :flamingo,
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

  # socket("/ws", FlamingoWeb.GameSocket, websocket: true, longpoll: false)

  plug(FlamingoWeb.Router)
end
