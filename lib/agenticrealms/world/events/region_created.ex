defmodule AgenticRealms.World.Events.RegionCreated do
  @derive Jason.Encoder
  @enforce_keys [:region_id, :name]
  defstruct [:region_id, :name, version: 1]
end
