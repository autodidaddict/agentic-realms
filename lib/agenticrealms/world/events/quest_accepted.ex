defmodule AgenticRealms.World.Events.QuestAccepted do
  @derive Jason.Encoder
  @enforce_keys [
    :quest_id,
    :player_id,
    :npc_blueprint_id,
    :slug,
    :definition_snapshot,
    :accepted_at
  ]
  defstruct [
    :quest_id,
    :player_id,
    :npc_blueprint_id,
    :slug,
    :definition_snapshot,
    :accepted_at,
    version: 1
  ]
end
