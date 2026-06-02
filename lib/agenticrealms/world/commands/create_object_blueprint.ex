defmodule AgenticRealms.World.Commands.CreateObjectBlueprint do
  @moduledoc """
  Feature 014 US1 — author a new Object Blueprint.

  `blueprint_id` is the human-typable slug (FR-007a). `wizard_id` is the
  acting wizard's `players.id`; the `Commands.create_object_blueprint/2`
  wrapper verifies `is_wizard` before dispatch (FR-WIZ-5). `kind` is
  fixed to `"object"` in milestone 1; milestone 2 introduces `"npc"`.

  See `specs/014-item-blueprints/contracts/commands.md`.
  """

  @enforce_keys [
    :blueprint_id,
    :wizard_id,
    :name,
    :short_description,
    :long_description
  ]
  defstruct [
    :blueprint_id,
    :wizard_id,
    :name,
    :short_description,
    :long_description,
    kind: "object",
    fixed: false
  ]
end
