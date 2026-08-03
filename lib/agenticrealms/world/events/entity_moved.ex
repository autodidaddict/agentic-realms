defmodule AgenticRealms.World.Events.EntityMoved do
  @moduledoc """
  An entity has relocated from `from` to `to` (feature 016, FR-002). `from`
  and `to` are `ContainerRef`s (serialized as maps). `cause` drives the UI
  witness policy. The destination `to` is authoritative for the read model.
  """
  @derive Jason.Encoder
  @enforce_keys [:entity_id, :from, :to]
  defstruct [:entity_id, :from, :to, :cause, :kind, version: 1]
end
