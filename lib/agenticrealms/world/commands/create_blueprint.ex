defmodule AgenticRealms.World.Commands.CreateBlueprint do
  @moduledoc """
  Feature 015 — author a new Blueprint (object or npc).

  `blueprint_id` is the human-typable slug (FR-004, one namespace across
  kinds). `wizard_id` is the acting wizard's `players.id`; the
  `Commands.create_blueprint/2` wrapper verifies `is_wizard` before dispatch.
  `wizard_id` is optional so the world seed can author system NPCs directly.

  `kind` ∈ {`"object"`, `"npc"`}. The NPC-flavored fields (`behaviors`/`lore`/
  `behavior_groups`/`quests`) default empty and are unused for objects.

  Replaces `CreateObjectBlueprint` + `CreateNPCBlueprint`.
  """

  @enforce_keys [:blueprint_id, :name, :short_description, :long_description]
  defstruct [
    :blueprint_id,
    :name,
    :short_description,
    :long_description,
    # The wrapper + seed always set `kind` explicitly; it defaults to "npc"
    # for the convenience of direct test dispatches.
    kind: "npc",
    wizard_id: nil,
    fixed: false,
    behaviors: [],
    lore: "",
    behavior_groups: [],
    quests: []
  ]
end
