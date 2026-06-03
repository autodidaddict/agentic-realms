defmodule AgenticRealms.World.Events.ObjectSpawned do
  @moduledoc """
  Feature 014 US2 — wizard-driven Object placement event. Emitted by
  the `Room` aggregate on a successful `SpawnObjectFromBlueprint` (US2)
  or `SpawnObjectFreeform` (US3).

  **`blueprint_id` is intentionally absent from the payload** (FR-013,
  FR-029). The event records what was spawned, not its origin. The
  projector and UI broadcaster are path-agnostic — they cannot tell
  whether a clone came from a blueprint or from a freeform prompt.

  Distinct from the existing `ObjectPlacedInRoom` event (feature 003)
  which covers seed-time placement and quest spawns and additionally
  carries `behaviors`, `quest_player_id`, and `quest_instance_id`.

  See `specs/014-item-blueprints/contracts/events.md`.
  """

  @derive Jason.Encoder
  @enforce_keys [
    :object_id,
    :room_id,
    :name,
    :short_description,
    :long_description,
    :fixed
  ]
  defstruct [
    :object_id,
    :room_id,
    :name,
    :short_description,
    :long_description,
    :fixed,
    version: 1
  ]
end
