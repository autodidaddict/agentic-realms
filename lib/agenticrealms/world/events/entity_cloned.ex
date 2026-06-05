defmodule AgenticRealms.World.Events.EntityCloned do
  @moduledoc """
  An entity has come into existence, contained by the void (feature 016,
  FR-001). Carries the kind-shaped frozen `fields` the projector writes into
  `world_objects` (`:object`) or `npc_clones` (`:npc`). Broadcasts nothing —
  creation into the void is silent.
  """
  @derive Jason.Encoder
  @enforce_keys [:entity_id, :kind, :fields]
  defstruct [:entity_id, :kind, :fields, version: 1]
end
