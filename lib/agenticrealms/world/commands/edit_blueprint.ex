defmodule AgenticRealms.World.Commands.EditBlueprint do
  @moduledoc """
  Edit an existing Blueprint (object or npc).

  `expected_revision` is the revision the wizard's form was based on; a
  mismatch fires the optimistic lock and the command is refused with no
  event. `fields_changed` is a sparse map of changed fields; allowed keys are
  `:name`, `:short_description`, `:long_description`, `:fixed`, `:lore`,
  `:behavior_groups`, `:behaviors`. The aggregate emits `BlueprintEdited` with the
  sparse diff and `revision: N+1`.

  Replaces `EditObjectBlueprint`.
  """

  @enforce_keys [:blueprint_id, :wizard_id, :expected_revision, :fields_changed]
  defstruct [:blueprint_id, :wizard_id, :expected_revision, :fields_changed]
end
