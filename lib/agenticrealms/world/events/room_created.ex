defmodule AgenticRealms.World.Events.RoomCreated do
  @derive Jason.Encoder
  @enforce_keys [:room_id, :name, :description]
  defstruct [:room_id, :name, :description, version: 1]
end
