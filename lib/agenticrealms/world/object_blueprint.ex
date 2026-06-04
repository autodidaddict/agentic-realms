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

  alias AgenticRealms.World.Commands.{CreateObjectBlueprint, EditObjectBlueprint}
  alias AgenticRealms.World.Events.{ObjectBlueprintCreated, ObjectBlueprintEdited}

  @editable_fields ~w(name short_description long_description fixed)a

  # --- CreateObjectBlueprint ----------------------------------------------

  @spec execute(%__MODULE__{}, %CreateObjectBlueprint{} | %EditObjectBlueprint{}) ::
          %ObjectBlueprintCreated{} | %ObjectBlueprintEdited{} | :ok | {:error, atom()}
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

  # --- EditObjectBlueprint (feature 014 US5) ------------------------------

  def execute(%__MODULE__{id: nil}, %EditObjectBlueprint{}),
    do: {:error, :blueprint_not_found}

  def execute(
        %__MODULE__{revision: current_revision} = state,
        %EditObjectBlueprint{
          expected_revision: expected_revision,
          fields_changed: fields_changed
        }
      )
      when is_map(fields_changed) do
    cond do
      # FR-020a — optimistic lock at the aggregate boundary. If the
      # wizard's known revision doesn't match the aggregate's current
      # revision, refuse without emitting an event. The wrapper re-reads
      # the read model to surface the current revision in the error
      # tuple that the LiveView consumes (Commanded itself only allows
      # 2-tuple errors out of execute/2).
      expected_revision != current_revision ->
        {:error, :stale_revision}

      # Validate keys.
      not Enum.all?(Map.keys(fields_changed), &(&1 in @editable_fields)) ->
        {:error, :invalid_field}

      # No-op diff returns :ok with no event (FR-008).
      no_changes?(state, fields_changed) ->
        :ok

      true ->
        %ObjectBlueprintEdited{
          blueprint_id: state.id,
          fields_changed: only_changed(state, fields_changed),
          revision: current_revision + 1
        }
    end
  end

  defp no_changes?(state, fields_changed) do
    Enum.all?(fields_changed, fn {k, v} ->
      Map.get(state, k) == v
    end)
  end

  defp only_changed(state, fields_changed) do
    fields_changed
    |> Enum.reject(fn {k, v} -> Map.get(state, k) == v end)
    |> Map.new()
  end

  # --- apply/2 ------------------------------------------------------------

  @spec apply(%__MODULE__{}, %ObjectBlueprintCreated{} | %ObjectBlueprintEdited{}) ::
          %__MODULE__{}
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

  def apply(%__MODULE__{} = state, %ObjectBlueprintEdited{
        fields_changed: fields_changed,
        revision: revision
      }) do
    Enum.reduce(fields_changed, %__MODULE__{state | revision: revision}, fn {k, v}, acc ->
      Map.put(acc, k, v)
    end)
  end
end
