import Config

config :flamingo, Flamingo.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "flamingo_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# Google is replaced by a stand-in that signs in whoever the test names.
config :flamingo, :google_strategy, Flamingo.FakeGoogleStrategy
config :flamingo, :google_oauth, client_id: "test-client", client_secret: "test-secret"

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :flamingo, FlamingoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "0UYNugMwUBFA9tGplxKfaS3CDdUlF6+2iI4ON8GcFpjfN5CXilwWS8krw566tFMM",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
