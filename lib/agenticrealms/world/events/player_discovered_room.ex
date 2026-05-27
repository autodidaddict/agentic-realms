defmodule AgenticRealms.World.Events.PlayerDiscoveredRoom do
  @derive Jason.Encoder
  @enforce_keys [:player_id, :room_id, :discovered_at]
  defstruct [:player_id, :room_id, :discovered_at, version: 1]
end
