defmodule AgenticRealms.World.Commands.PlaceObject do
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
    :fixed
  ]
end
