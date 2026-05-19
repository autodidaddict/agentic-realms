defmodule AgenticRealms.World.Commands.DropObject do
  @enforce_keys [:room_id, :player_id, :object_id]
  defstruct [:room_id, :player_id, :object_id]
end
