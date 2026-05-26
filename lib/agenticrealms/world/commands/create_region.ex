defmodule AgenticRealms.World.Commands.CreateRegion do
  @enforce_keys [:region_id, :name]
  defstruct [:region_id, :name]
end
