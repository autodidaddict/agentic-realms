defmodule AgenticRealms.World.Commands.MoveEntity do
  @moduledoc """
  Relocate an entity from one container to another (feature 016, FR-002).

  `expected_from` is the container the caller believes the entity is in; the
  `Entity` aggregate rejects a move whose `expected_from` disagrees with the
  entity's actual current container (`:container_conflict`), so a concurrent
  second take/move cannot "steal" an entity (FR-005).

  `cause` (`:spawned | :placed | :taken | :dropped | :relocated`) is metadata
  for the UI witness policy only — it does not affect the move mechanism.
  """
  @enforce_keys [:entity_id, :expected_from, :to]
  defstruct [:entity_id, :expected_from, :to, :cause]
end
