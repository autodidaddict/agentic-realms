defmodule AgenticRealms.World.Events.ObjectPlacedInRoom do
  @derive Jason.Encoder
  @enforce_keys [
    :room_id,
    :object_id,
    :name,
    :short_description,
    :long_description,
    :fixed
  ]
  defstruct [
    :room_id,
    :object_id,
    :name,
    :short_description,
    :long_description,
    :fixed,
    behaviors: [],
    version: 1
  ]
end
