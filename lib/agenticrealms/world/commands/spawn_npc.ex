defmodule AgenticRealms.World.Commands.SpawnNPC do
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
    :long_description
  ]
end
