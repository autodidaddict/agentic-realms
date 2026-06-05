defmodule AgenticRealms.World.Events.EntityMoved do
  @moduledoc """
  An entity has relocated from `from` to `to` (feature 016, FR-002). `from`
  and `to` are `ContainerRef`s (serialized as maps). `cause` drives the UI
  witness policy. The destination `to` is authoritative for the read model.
  """
  @derive Jason.Encoder
  @enforce_keys [:entity_id, :from, :to]
  # `kind` (`:object | :npc`) lets the read-side projector route to the right
  # table without a lookup; stamped from aggregate state at emit time.
  defstruct [:entity_id, :from, :to, :cause, :kind, version: 1]
end
