defmodule AgenticRealms.World.Events.BlueprintEdited do
  @moduledoc """
  Feature 015 — unified Blueprint edit event. Emitted by the `Blueprint`
  aggregate on a successful `EditBlueprint` (passed the optimistic-lock check
  and carried ≥1 field-changing diff). `fields_changed` is sparse. Projected
  by `BlueprintProjector` (applies the diff, bumps `revision`).

  Replaces `ObjectBlueprintEdited` (and is the path the NPC edit story uses).
  """

  @derive Jason.Encoder
  @enforce_keys [:blueprint_id, :fields_changed, :revision]
  defstruct [:blueprint_id, :fields_changed, :revision, version: 1]
end
