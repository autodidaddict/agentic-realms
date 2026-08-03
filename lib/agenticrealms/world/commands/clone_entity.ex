defmodule AgenticRealms.World.Commands.CloneEntity do
  @moduledoc """
  Bring a world entity into existence. A freshly
  cloned entity is born in the void; placement is a separate `MoveEntity`.

  `kind` is `:object` or `:npc`. `fields` is the kind-shaped map of frozen
  read-model fields the projector writes (denormalized full copy).
  """
  @enforce_keys [:entity_id, :kind, :fields]
  defstruct [:entity_id, :kind, :fields]
end
