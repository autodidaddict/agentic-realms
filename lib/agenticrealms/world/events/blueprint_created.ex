defmodule AgenticRealms.World.Events.BlueprintCreated do
  @moduledoc """
  Feature 015 — unified Blueprint creation event. Emitted by the `Blueprint`
  aggregate on a successful `CreateBlueprint`. Projected by
  `BlueprintProjector` into the `blueprints` table and fanned out by
  `UIEventBroadcaster` as a `WizardBlueprintRegistryChanged`. Always carries
  `revision: 1`; edits emit `BlueprintEdited`.

  Replaces `ObjectBlueprintCreated` + `NPCBlueprintCreated`.
  """

  @derive Jason.Encoder
  @enforce_keys [:blueprint_id, :kind, :name, :short_description, :long_description]
  defstruct [
    :blueprint_id,
    :kind,
    :name,
    :short_description,
    :long_description,
    fixed: false,
    revision: 1,
    behaviors: [],
    lore: "",
    behavior_groups: [],
    quests: [],
    version: 1
  ]
end
