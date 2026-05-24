defmodule AgenticRealms.World.Events.NPCClonedFromBlueprint do
  @derive Jason.Encoder
  @enforce_keys [
    :blueprint_id,
    :clone_id,
    :room_id,
    :serial,
    :name,
    :short_description,
    :long_description
  ]
  defstruct [
    :blueprint_id,
    :clone_id,
    :room_id,
    :serial,
    :name,
    :short_description,
    :long_description,
    behaviors: [],
    version: 1
  ]
end
