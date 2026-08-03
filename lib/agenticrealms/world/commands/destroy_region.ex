defmodule AgenticRealms.World.Commands.DestroyRegion do
  @moduledoc """
  Destroy a transient region. Idempotent: a no-op if the region
  is already destroyed or its stream has already been purged. Emitting
  `RegionDestroyed` evicts the aggregate via `RegionLifespan`; the data purge
  is handled out-of-band by `AgenticRealms.World.Transient.Purge`.
  """
  @enforce_keys [:region_id]
  defstruct [:region_id]
end
