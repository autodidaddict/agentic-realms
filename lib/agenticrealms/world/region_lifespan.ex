defmodule AgenticRealms.World.RegionLifespan do
  @moduledoc """
  Aggregate lifespan for the `Region` aggregate. Evicts the
  aggregate process (`:stop`) as soon as a region is destroyed, so a
  transient region's GenServer is freed immediately on teardown. All other
  events keep the aggregate resident (`:infinity`), preserving the existing
  behavior for permanent regions. Eviction is orthogonal to the data purge —
  it frees only the in-memory process; events/snapshots are removed by
  `AgenticRealms.World.Transient.Purge`.
  """

  @behaviour Commanded.Aggregates.AggregateLifespan

  alias AgenticRealms.World.Events.RegionDestroyed

  @impl true
  def after_event(%RegionDestroyed{}), do: :stop
  def after_event(_event), do: :infinity

  @impl true
  def after_command(_command), do: :infinity

  @impl true
  def after_error(_error), do: :stop
end
