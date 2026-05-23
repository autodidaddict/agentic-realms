defmodule AgenticRealms.World.Events.NPCSpawnedInRoom do
  @derive Jason.Encoder
  @enforce_keys [
    :room_id,
    :npc_id,
    :name,
    :short_description,
    :long_description
  ]
  defstruct [
    :room_id,
    :npc_id,
    :name,
    :short_description,
    :long_description,
    version: 1
  ]
end
