defmodule AgenticRealms.World.Commands.CreateRoom do
  @enforce_keys [:room_id, :name, :description, :region_id]
  defstruct [
    :room_id,
    :name,
    :description,
    :region_id,
    behaviors: [],
    map_visible: true,
    elevation: 0,
    map_x: nil,
    map_y: nil
  ]
end
