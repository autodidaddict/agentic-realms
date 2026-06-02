defmodule AgenticRealms.World.ObjectBlueprint do
  @moduledoc """
  Object Blueprint aggregate. Owns the authored archetype for a kind of
  object — name, descriptions, fixed flag — and the monotonic `revision`
  counter that secures optimistic-lock concurrent edits (FR-020a, US5).

  Identified by `:blueprint_id` (the human-typable slug per FR-007a) with
  prefix `"object-blueprint-"`. UUIDs explicitly disallowed.

  **Constructor semantics**: blueprints stamp clones at spawn time, but
  spawned objects are freestanding afterward — they carry no reference
  back to the blueprint and edits to the blueprint never propagate
  (FR-009, FR-013, FR-021). See `specs/014-item-blueprints/data-model.md`.

  Command handlers landed per user story:
    * `CreateObjectBlueprint` → US1 (this file).
    * `EditObjectBlueprint` → US5 (Phase 7).
  """

  defstruct id: nil,
            kind: "object",
            name: nil,
            short_description: nil,
            long_description: nil,
            fixed: false,
            revision: 0

  alias AgenticRealms.World.Commands.CreateObjectBlueprint
  alias AgenticRealms.World.Events.ObjectBlueprintCreated

  # --- CreateObjectBlueprint ----------------------------------------------

  def execute(%__MODULE__{id: nil}, %CreateObjectBlueprint{
        blueprint_id: bp_id,
        name: name,
        short_description: short,
        long_description: long,
        kind: kind,
        fixed: fixed
      }) do
    cond do
      name in [nil, ""] ->
        {:error, :name_required}

      short in [nil, ""] ->
        {:error, :short_description_required}

      long in [nil, ""] ->
        {:error, :long_description_required}

      true ->
        %ObjectBlueprintCreated{
          blueprint_id: bp_id,
          kind: kind || "object",
          name: name,
          short_description: short,
          long_description: long,
          fixed: !!fixed,
          revision: 1
        }
    end
  end

  def execute(%__MODULE__{}, %CreateObjectBlueprint{}),
    do: {:error, :blueprint_already_exists}

  # --- apply/2 ------------------------------------------------------------

  def apply(%__MODULE__{} = state, %ObjectBlueprintCreated{} = e) do
    %__MODULE__{
      state
      | id: e.blueprint_id,
        kind: e.kind,
        name: e.name,
        short_description: e.short_description,
        long_description: e.long_description,
        fixed: e.fixed,
        revision: e.revision
    }
  end
end
