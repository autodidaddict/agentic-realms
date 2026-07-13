defmodule AgenticRealms.World.Events.PlayerLeveledUp do
  @derive Jason.Encoder
  @enforce_keys [:player_id, :from_level, :to_level]
  defstruct [:player_id, :from_level, :to_level, version: 1]
end
