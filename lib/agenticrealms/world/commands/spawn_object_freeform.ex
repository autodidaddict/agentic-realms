defmodule AgenticRealms.World.Commands.SpawnObjectFreeform do
  @moduledoc """
  Feature 014 US3 — spawn a one-off Object into a room without any
  Object Blueprint involvement. The wizard's prompt + Interpreted Data
  card form populate the payload directly; no row is added to
  `object_blueprints`. Emits the same `ObjectSpawned` event the
  blueprint-spawn path does — the two paths converge at the event
  boundary and the projector / broadcaster are path-agnostic (FR-012).

  See `specs/014-item-blueprints/contracts/commands.md`.
  """

  @enforce_keys [
    :room_id,
    :object_id,
    :wizard_id,
    :name,
    :short_description,
    :long_description
  ]
  defstruct [
    :room_id,
    :object_id,
    :wizard_id,
    :name,
    :short_description,
    :long_description,
    fixed: false
  ]
end
