defmodule AgenticRealms.World.Commands.CreateNPCBlueprint do
  @enforce_keys [:blueprint_id, :name, :short_description, :long_description]
  defstruct [
    :blueprint_id,
    :name,
    :short_description,
    :long_description,
    behaviors: [],
    lore: "",
    # Feature 013 — Quests. Per-NPC FetchQuest catalog. See
    # `specs/013-quest-system/contracts/npc-blueprint-quests.md` for the
    # shape and the validation rules applied at the command-wrapper level.
    quests: []
  ]
end
