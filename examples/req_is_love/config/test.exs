import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
# NOTE: server: true is REQUIRED for Hermes MCP transport to start
config :req_is_love, ReqIsLoveWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "uimYVx+ijmqXyxF2ZQWS0hDPL6x6SQY0yeiQbU+fkDYeB2BtR2jpuxzOtQwW10qz",
  server: true

# CRITICAL: Force MCP transport to start in test environment
# Hard-won pattern from transport lifecycle debugging
config :ash_ai, :mcp_transport, start: true

# In test we don't send emails
config :req_is_love, ReqIsLove.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
