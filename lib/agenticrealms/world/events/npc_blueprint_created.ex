defmodule AgenticRealms.World.Events.NPCBlueprintCreated do
  @derive Jason.Encoder
  @enforce_keys [:blueprint_id, :name, :short_description, :long_description]
  defstruct [
    :blueprint_id,
    :name,
    :short_description,
    :long_description,
    behaviors: [],
    lore: "",
    # Feature 013 — Quests. Defaults to [] so events authored before this
    # feature replay cleanly. The aggregate apply/2 also defends via
    # Map.get/3 for legacy events that have NO :quests field at all.
    quests: [],
    # Feature 015 — wizard authoring (mirror object blueprints). Defaults keep
    # pre-015 events replaying cleanly.
    kind: "npc",
    fixed: false,
    toolsets: [],
    revision: 1,
    version: 1
  ]
end
