defmodule AgenticRealms.World.Application do
  @moduledoc """
  Commanded application for the world bounded context. Commands dispatched
  here are routed via `AgenticRealms.World.Router` to one of the two
  aggregates (Room or Player) and persisted to `AgenticRealms.EventStore`.

  Configured per environment in `config/{config,test}.exs`.
  """

  use Commanded.Application,
    otp_app: :agenticrealms,
    event_store: [
      adapter: Commanded.EventStore.Adapters.EventStore,
      event_store: AgenticRealms.EventStore
    ]

  router(AgenticRealms.World.Router)
end
