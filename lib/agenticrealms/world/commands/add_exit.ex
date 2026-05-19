defmodule AgenticRealms.World.Commands.AddExit do
  @enforce_keys [:room_id, :direction, :target_room_id]
  defstruct [:room_id, :direction, :target_room_id]
end
