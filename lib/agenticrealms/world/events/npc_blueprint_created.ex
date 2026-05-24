defmodule AgenticRealms.World.Events.NPCBlueprintCreated do
  @derive Jason.Encoder
  @enforce_keys [:blueprint_id, :name, :short_description, :long_description]
  defstruct [
    :blueprint_id,
    :name,
    :short_description,
    :long_description,
    behaviors: [],
    version: 1
  ]
end
