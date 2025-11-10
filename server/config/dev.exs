import Config

config :flamingo, FlamingoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 8080],
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  watchers: []
