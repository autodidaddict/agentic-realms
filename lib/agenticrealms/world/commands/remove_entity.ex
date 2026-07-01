defmodule AgenticRealms.World.Commands.RemoveEntity do
  @moduledoc """
  Feature 018 — remove a world entity (object or NPC) from existence. The first
  first-class, event-sourced removal path (previously entities were only ever
  removed by the transient-region hard-purge, which emits nothing). Routed to the
  `Entity` aggregate, which validates existence and emits `EntityRemoved`.
  """
  @enforce_keys [:entity_id]
  defstruct [:entity_id]
end
