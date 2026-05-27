defmodule AgenticRealms.World.Commands.AcceptQuest do
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
    :accepted_at
  ]
end
