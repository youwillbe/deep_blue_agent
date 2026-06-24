import Config

# Configure DurableStreams to use CubDB for persistent storage in tests
config :deep_blue, :durable_streams_storage, DurableStreams.Storage.CubDB

config :deep_blue, DurableStreams.Storage.CubDB,
  data_dir: "tmp/durable_streams_test"

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :deep_blue, DeepBlue.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "deep_blue_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :deep_blue, DeepBlueWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "wrz+w2dG8jvB7h82VFz3nZL54fQ8NAbqdd00y1x9DMYgCZ8haNGPyjsHdI8gkmjn",
  server: false


# Print only errors during test
config :logger, level: :error

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
