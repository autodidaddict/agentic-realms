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

# Commanded application + EventStore adapter
config :agenticrealms, AgenticRealms.World.Application,
  event_store: [
    adapter: Commanded.EventStore.Adapters.EventStore,
    event_store: AgenticRealms.EventStore
  ],
  pubsub: :local,
  registry: :local

config :agenticrealms, AgenticRealms.EventStore,
  serializer: EventStore.JsonSerializer,
  column_data_type: "jsonb",
  username: "postgres",
  password: "postgres",
  database: "agenticrealms_eventstore",
  hostname: "localhost"

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

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
