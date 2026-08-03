defmodule AgenticRealms.World.EntityLifespan do
  @moduledoc """
  Aggregate lifespan for the `Entity` aggregate. Evicts the
  aggregate process (`:stop`) as soon as the entity is removed (`EntityRemoved`),
  freeing the in-memory GenServer for an entity that no longer exists. All other
  events keep the aggregate resident (`:infinity`), preserving prior behavior for
  clone/move/edit. Eviction is orthogonal to the read-model row delete, which the
  `EntityProjector` performs on the same event.
  """

  @behaviour Commanded.Aggregates.AggregateLifespan

  alias AgenticRealms.World.Events.EntityRemoved

  @impl true
  def after_event(%EntityRemoved{}), do: :stop
  def after_event(_event), do: :infinity

  @impl true
  def after_command(_command), do: :infinity

  @impl true
  def after_error(_error), do: :stop
end
