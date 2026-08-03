defmodule AgenticRealms.World.Commands.EditEntity do
  @moduledoc """
  Edit an entity's frozen read-model fields in place. Absorbs
  the old `EditObject`. `fields_changed` is a sparse map; a no-op diff emits
  no event.
  """
  @enforce_keys [:entity_id, :fields_changed]
  defstruct [:entity_id, :fields_changed]
end
