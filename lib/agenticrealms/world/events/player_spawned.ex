defmodule AgenticRealms.World.Events.PlayerSpawned do
  @derive Jason.Encoder
  @enforce_keys [:player_id, :room_id]
  defstruct [:player_id, :room_id, version: 1]
end
