import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :agenticrealms, AgenticRealms.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "agenticrealms_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :agenticrealms, AgenticRealmsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "AUDex/DoKIKUZZv5pRTn4cjduhGE1FkwYLNNJxEfFtzE5LYKOSUDDmoPUmfA0W1l",
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

# Issue #10 — the Commanded chain (World.Application, projectors, event
# handlers) is started per-test by tests tagged `:commanded`, NOT at boot.
# Each test gets a fresh in-memory event store and fresh subscription
# positions. See `AgenticRealms.DataCase.setup_commanded/0`.
config :agenticrealms, start_commanded?: false

# In tests use the in-memory event store adapter so we don't need a separate
# Postgres database for event sourcing and tests stay fast/hermetic.
#
# `snapshotting:` mirrors config.exs (issue #6). The test config block fully
# overrides the prod block, so the snapshot config must be repeated here for
# tests to exercise the snapshot path.
config :agenticrealms, AgenticRealms.World.Application,
  event_store: [
    adapter: Commanded.EventStore.Adapters.InMemory,
    serializer: Commanded.Serialization.JsonSerializer
  ],
  pubsub: :local,
  registry: :local,
  snapshotting: %{
    AgenticRealms.World.Room => [snapshot_every: 100, snapshot_version: 1],
    AgenticRealms.World.Player => [snapshot_every: 100, snapshot_version: 1]
  }

# Anthropic API in tests: a dummy key (so the resolver does not take the
# missing-key path) plus a Req.Test plug so no request ever leaves the BEAM.
# Tests register per-test stubs with `Req.Test.stub(AgenticRealms.Anthropic, fun)`.
config :agenticrealms, AgenticRealms.Anthropic,
  api_key: "test-key-not-real",
  req_options: [plug: {Req.Test, AgenticRealms.Anthropic}]

# Feature 010 — idle-timeout override for NPC chat Conversation GenServers.
# Keeps idle-reap tests fast (200ms instead of 60_000ms).
config :agenticrealms, AgenticRealms.World.NPCChat, idle_timeout_ms: 200

# Feature 011 — Room-Scoped Tick Timers. Test overrides keep cadence
# fast so per-beat assertions don't sleep for the production defaults.
config :agenticrealms, AgenticRealms.World.Ticks,
  base_tick_rate_ms: 50,
  join_grace_ms: 10,
  leave_grace_ms: 50
