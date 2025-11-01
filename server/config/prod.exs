import Config

config :server, ServerWeb.Endpoint,
  http: [
    ip: {0, 0, 0, 0},
    port: String.to_integer(System.get_env("PORT") || "8080")
  ],
  url: [host: System.get_env("PHX_HOST") || "localhost"],
  check_origin: false
