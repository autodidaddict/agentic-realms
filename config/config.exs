# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :agenticrealms,
  namespace: AgenticRealms,
  ecto_repos: [AgenticRealms.Repo],
  event_stores: [AgenticRealms.EventStore],
  generators: [timestamp_type: :utc_datetime]

# Commanded application + EventStore adapter.
#
# Issue #6 — `snapshotting:` enables Commanded aggregate snapshots so
# command latency stops growing linearly with the aggregate's event count.
# `snapshot_every: 100` means a new snapshot is recorded after every 100
# events on the stream; `snapshot_version: 1` lets us force-discard prior
# snapshots if the aggregate state schema changes (bump the version).
# Room and Player aggregates implement `Commanded.Serialization.JsonDecoder`
# so their `MapSet` fields roundtrip cleanly through the serializer below.
config :agenticrealms, AgenticRealms.World.Application,
  event_store: [
    adapter: Commanded.EventStore.Adapters.EventStore,
    event_store: AgenticRealms.EventStore
  ],
  pubsub: :local,
  registry: :local,
  snapshotting: %{
    AgenticRealms.World.Room => [snapshot_every: 100, snapshot_version: 1],
    AgenticRealms.World.Player => [snapshot_every: 100, snapshot_version: 1]
  }

# `AgenticRealms.EventStore.Serializer` is a thin wrapper over
# `EventStore.JsonSerializer` that pipes deserialized structs through
# `Commanded.Serialization.JsonDecoder` — required so aggregate snapshots
# can rehydrate `MapSet` fields. Wire format is unchanged for events.
config :agenticrealms, AgenticRealms.EventStore,
  serializer: AgenticRealms.EventStore.Serializer,
  column_data_type: "jsonb",
  username: "postgres",
  password: "postgres",
  database: "agenticrealms_eventstore",
  hostname: "localhost",
  # Feature 017 — Transient Regions. Permits irreversible hard deletes so a
  # destroyed transient region's streams can be permanently purged from the
  # event store (current + historical). Off by default in eventstore; the
  # only purge path is `AgenticRealms.World.Transient.Purge`.
  enable_hard_deletes: true

# Feature 017 — Transient Regions.
# `region_lifetime_ms`: absolute lifetime cap measured from provisioning;
#   the reaper destroys the region once it elapses, regardless of activity.
# `logoff_grace_ms`: reconnect grace after the provision-owner's last session
#   leaves before the region is considered abandoned (tolerates refreshes).
# `reap_interval_ms`: how often the singleton reaper sweeps for due regions;
#   keep `logoff_grace_ms`-relative detection latency within the SC budget.
config :agenticrealms, AgenticRealms.World.Transient,
  region_lifetime_ms: 3_600_000,
  logoff_grace_ms: 120_000,
  reap_interval_ms: 30_000

# Feature 011 — Room-Scoped Tick Timers.
# `base_tick_rate_ms`: scheduler beat granularity; the minimum interval
#   for any tick behavior (FR-004). Authored intervals must be positive
#   integer multiples of this value.
# `join_grace_ms`: short delay before a 0→1 occupancy transition starts
#   the room scheduler (FR-002). Absorbs reconnect bursts.
# `leave_grace_ms`: delay before a 1→0 occupancy transition tears down
#   the room scheduler (FR-003). Re-entry within this window preserves
#   the schedule.
config :agenticrealms, AgenticRealms.World.Ticks,
  base_tick_rate_ms: 1_000,
  join_grace_ms: 250,
  leave_grace_ms: 5_000

# Feature 012 — Maps.
# `default_zoom_cells`: side length of the initial SVG viewBox in CELL
#   units. Defaults to 3 (3×3 cells visible at first open, centered on the
#   player's current room). The browser-side `.MapInteract` hook owns
#   mouse-wheel zoom and click-drag pan from there.
config :agenticrealms, AgenticRealms.MapRenderer, default_zoom_cells: 3

# Configure the endpoint
config :agenticrealms, AgenticRealmsWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: AgenticRealmsWeb.ErrorHTML, json: AgenticRealmsWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: AgenticRealms.PubSub,
  live_view: [signing_salt: "JPS9D/Op"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  agenticrealms: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  agenticrealms: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Anthropic API — backs the natural-language intent resolver (feature 005).
# Compile-time defaults; the API key and any overrides are applied in
# config/runtime.exs from environment variables.
config :agenticrealms, AgenticRealms.Anthropic,
  base_url: "https://api.anthropic.com",
  model: "claude-haiku-4-5-20251001",
  timeout_ms: 5_000

# Feature 018 — External NPC Brains. The game calls the Temporal server's HTTP
# API to start/terminate one durable workflow per NPC (never the worker), and
# runs a reconciliation sweep that converges running minds to live NPCs.
# Compile-time defaults; `service_secret` and any overrides are applied in
# config/runtime.exs from environment variables. `service_secret` is
# deliberately absent here (unset ⇒ the API fails closed).
config :agenticrealms, AgenticRealms.NpcMinds,
  temporal_base_url: "http://localhost:7243",
  temporal_namespace: "default",
  temporal_task_queue: "npc-minds",
  npc_workflow_type: "NpcWorkflow",
  reconcile_interval_ms: 60_000

# Feature 020 — SRD 5e Character Stats. Character creation is not interactive
# yet, so every new character is generated from these defaults. This is the one
# place they live: changing a value here changes what new characters are made
# as, with no other code edit. Existing characters keep whatever their
# CharacterCreated event recorded.
#
# `species_skill` fills Human's Skillful trait and `species_feat` its Versatile
# trait, both of which the SRD leaves to the player. Perception is the most
# broadly useful skill in play; Alert is the one origin feat with no sub-choice
# of its own, and Soldier has already taken Savage Attacker.
config :agenticrealms, :character_defaults,
  species: "human",
  class: "fighter",
  background: "soldier",
  size: :medium,
  species_skill: :perception,
  species_feat: "alert"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
