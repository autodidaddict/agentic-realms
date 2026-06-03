defmodule AgenticRealms.World.Commands.EditObjectBlueprint do
  @moduledoc """
  Feature 014 US5 — edit an existing Object Blueprint.

  `expected_revision` carries the revision the wizard's form was based
  on. If it doesn't match the aggregate's current revision, the
  optimistic lock fires (FR-020a) and the command is refused without
  emitting any event.

  `fields_changed` is a sparse map containing only the fields the
  wizard actually changed. Allowed keys: `:name`, `:short_description`,
  `:long_description`, `:fixed`. The aggregate replaces those fields
  in its state and emits `ObjectBlueprintEdited` with the same sparse
  map; the projector applies the diff and bumps `revision` to N+1.

  See `specs/014-item-blueprints/contracts/commands.md`.
  """

  @enforce_keys [:blueprint_id, :wizard_id, :expected_revision, :fields_changed]
  defstruct [:blueprint_id, :wizard_id, :expected_revision, :fields_changed]
end
