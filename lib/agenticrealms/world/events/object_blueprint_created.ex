defmodule AgenticRealms.World.Events.ObjectBlueprintCreated do
  @moduledoc """
  Feature 014 US1 — Object Blueprint creation event. Emitted by the
  `ObjectBlueprint` aggregate on a successful `CreateObjectBlueprint`
  command. Projected by `ObjectBlueprintProjector` into the
  `object_blueprints` read-model table. Also picked up by
  `UIEventBroadcaster` in US6 to fan out
  `WizardBlueprintRegistryChanged` for live-updating registries.

  Always carries `revision: 1` — subsequent edits emit
  `ObjectBlueprintEdited` (US5).

  See `specs/014-item-blueprints/contracts/events.md`.
  """

  @derive Jason.Encoder
  @enforce_keys [
    :blueprint_id,
    :kind,
    :name,
    :short_description,
    :long_description,
    :fixed,
    :revision
  ]
  defstruct [
    :blueprint_id,
    :kind,
    :name,
    :short_description,
    :long_description,
    :fixed,
    :revision,
    version: 1
  ]
end
