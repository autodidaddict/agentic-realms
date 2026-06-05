defmodule AgenticRealms.World.Commands.CreateNPCBlueprint do
  @moduledoc """
  Author a new NPC Blueprint.

  `blueprint_id` is the human-typable slug (FR-004, mirrors object
  blueprints). `wizard_id` is the acting wizard's `players.id`; the
  `Commands.create_npc_blueprint/2` wrapper verifies `is_wizard` before
  dispatch (FR-WIZ-5). `wizard_id` is optional on the struct so the
  world seed can dispatch system-authored NPCs (Garrick, …) directly,
  bypassing the wizard gate.

  Feature 015 — `kind` (always `"npc"`), `fixed`, and `toolsets` (referenced
  toolset names) join the existing feature-008/013 `behaviors`/`lore`/`quests`.

  See `specs/015-npc-blueprints/contracts/commands.md`.
  """

  @enforce_keys [:blueprint_id, :name, :short_description, :long_description]
  defstruct [
    :blueprint_id,
    :name,
    :short_description,
    :long_description,
    # Optional — set by the Commands wrapper; nil for system-seeded NPCs.
    wizard_id: nil,
    behaviors: [],
    lore: "",
    # Feature 013 — Quests. Per-NPC FetchQuest catalog. See
    # `specs/013-quest-system/contracts/npc-blueprint-quests.md` for the
    # shape and the validation rules applied at the command-wrapper level.
    quests: [],
    # Feature 015 — wizard authoring (mirror object blueprints).
    kind: "npc",
    fixed: false,
    toolsets: []
  ]
end
