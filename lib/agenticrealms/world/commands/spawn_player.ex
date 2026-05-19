defmodule AgenticRealms.World.Commands.SpawnPlayer do
  @enforce_keys [:player_id, :starting_room_id]
  defstruct [:player_id, :starting_room_id]
end
