defmodule AgenticRealms.World.Events.RegionDestroyed do
  @moduledoc """
  A transient region was destroyed. Triggers aggregate eviction
  (via `RegionLifespan` → `:stop`); the projector stamps `regions.destroyed_at`
  as a tombstone. Actual data removal is done by `Transient.Purge`.
  """
  @derive Jason.Encoder
  @enforce_keys [:region_id]
  defstruct [:region_id, version: 1]
end
