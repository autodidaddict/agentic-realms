defmodule AgenticRealms.World.Commands.SpawnObjectFromBlueprint do
  @moduledoc """
  Feature 014 US2 — spawn an object from an Object Blueprint into a
  room. The dispatcher reads the blueprint's current payload and stamps
  the denormalized fields into the command before dispatching to the
  destination `Room` aggregate. The blueprint itself is NOT consulted
  by the aggregate (which has no reference to it) — by design (FR-013).

  See `specs/014-item-blueprints/contracts/commands.md`.
  """

  @enforce_keys [
    :room_id,
    :object_id,
    :blueprint_id,
    :wizard_id,
    :name,
    :short_description,
    :long_description
  ]
  defstruct [
    :room_id,
    :object_id,
    :blueprint_id,
    :wizard_id,
    :name,
    :short_description,
    :long_description,
    fixed: false
  ]
end
