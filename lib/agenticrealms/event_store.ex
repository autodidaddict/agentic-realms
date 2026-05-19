defmodule AgenticRealms.EventStore do
  @moduledoc """
  PostgreSQL-backed event store for the `AgenticRealms.World` Commanded
  application. Used as the `:event_store` adapter argument in dev and prod;
  tests use `Commanded.EventStore.Adapters.InMemory` (see `config/test.exs`).
  """
  use EventStore, otp_app: :agenticrealms
end
