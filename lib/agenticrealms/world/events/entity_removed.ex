defmodule AgenticRealms.World.Events.EntityRemoved do
  @moduledoc """
  An entity has been removed from the world. Carries the entity's
  `kind` (routes the read-model row delete) and `from` — the container it
  occupied at removal — so the witness fan-out can announce an NPC's departure to
  the room it was in. Terminal: the `Entity` aggregate stops after this event
  (`EntityLifespan`).
  """
  @derive Jason.Encoder
  @enforce_keys [:entity_id, :kind]
  defstruct [:entity_id, :kind, :from, :name, version: 1]
end
