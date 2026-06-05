defmodule AgenticRealms.World.Events.EntityEdited do
  @moduledoc """
  An entity's frozen read-model fields changed in place (feature 016).
  `fields_changed` is a sparse map applied to the read row.
  """
  @derive Jason.Encoder
  @enforce_keys [:entity_id, :fields_changed]
  defstruct [:entity_id, :fields_changed, :kind, version: 1]
end
