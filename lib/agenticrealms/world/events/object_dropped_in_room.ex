defmodule AgenticRealms.World.Events.ObjectDroppedInRoom do
  @derive Jason.Encoder
  @enforce_keys [:room_id, :player_id, :object_id]
  defstruct [:room_id, :player_id, :object_id, version: 1]
end
