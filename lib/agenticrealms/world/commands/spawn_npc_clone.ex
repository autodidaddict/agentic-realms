defmodule AgenticRealms.World.Commands.SpawnNPCClone do
  @enforce_keys [:blueprint_id, :clone_id, :room_id]
  defstruct [:blueprint_id, :clone_id, :room_id]
end
