defmodule AgenticRealms.World.Events.ObjectTakenFromRoom do
  @derive Jason.Encoder
  @enforce_keys [:room_id, :player_id, :object_id]
  defstruct [:room_id, :player_id, :object_id, version: 1]
end
