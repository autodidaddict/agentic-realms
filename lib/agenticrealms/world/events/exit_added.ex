defmodule AgenticRealms.World.Events.ExitAdded do
  @derive Jason.Encoder
  @enforce_keys [:room_id, :direction, :target_room_id]
  defstruct [:room_id, :direction, :target_room_id, version: 1]
end
