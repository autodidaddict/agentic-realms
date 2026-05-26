defmodule AgenticRealms.World.Commands.RecordRoomDiscovery do
  @enforce_keys [:player_id, :room_id]
  defstruct [:player_id, :room_id]
end
