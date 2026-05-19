defmodule AgenticRealms.World.Commands.MovePlayer do
  @enforce_keys [:player_id, :from_room_id, :to_room_id, :direction]
  defstruct [:player_id, :from_room_id, :to_room_id, :direction]
end
