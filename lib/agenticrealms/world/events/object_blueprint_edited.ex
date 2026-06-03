defmodule AgenticRealms.World.Events.ObjectBlueprintEdited do
  @moduledoc """
  Feature 014 US5 — Object Blueprint edit event. Emitted by the
  `ObjectBlueprint` aggregate on a successful `EditObjectBlueprint`
  command (one that passed the optimistic-lock check and carried at
  least one field-changing diff).

  Projected by `ObjectBlueprintProjector` (updates the row's fields
  and bumps `revision`). Picked up by `UIEventBroadcaster` in US6 for
  the live-updating registry.

  See `specs/014-item-blueprints/contracts/events.md`.
  """

  @derive Jason.Encoder
  @enforce_keys [:blueprint_id, :fields_changed, :revision]
  defstruct [:blueprint_id, :fields_changed, :revision, version: 1]
end
