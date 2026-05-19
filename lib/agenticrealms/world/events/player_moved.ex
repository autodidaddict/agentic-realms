defmodule AgenticRealms.World.Events.PlayerMoved do
  @derive Jason.Encoder
  @enforce_keys [:player_id, :from_room_id, :to_room_id, :direction]
  defstruct [:player_id, :from_room_id, :to_room_id, :direction, version: 1]
end
