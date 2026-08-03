defmodule AgenticRealms.World.Blueprint do
  @moduledoc """
  Unified Blueprint aggregate — the authored template for a
  kind of world entity (`kind` ∈ {`"object"`, `"npc"`}). Owns the shared core
  (name/descriptions/fixed) plus the NPC-flavored fields (behaviors/lore/
  behavior_groups/quests) and the monotonic `revision` that secures optimistic-lock
  edits.

  Identified by `:blueprint_id` (the human-typable slug) with stream
  prefix `"blueprint-"`. UUIDs are disallowed by the slug shape.

  Replaces the structurally-identical `ObjectBlueprint` (014) + `NPCBlueprint`
  (008/013) aggregates: once spawned, an object and an NPC are the same 016
  `Entity` with a different kind, so their templates are one aggregate too.
  Spawned instances are freestanding — edits never propagate (full copy).
  """

  defstruct id: nil,
            kind: "npc",
            name: nil,
            short_description: nil,
            long_description: nil,
            fixed: false,
            revision: 0,
            behaviors: [],
            lore: "",
            behavior_groups: [],
            quests: []

  alias AgenticRealms.World.Commands.{CreateBlueprint, EditBlueprint}
  alias AgenticRealms.World.Events.{BlueprintCreated, BlueprintEdited}

  @editable_fields ~w(name short_description long_description fixed lore behavior_groups behaviors)a

  @spec execute(%__MODULE__{}, %CreateBlueprint{} | %EditBlueprint{}) ::
          %BlueprintCreated{} | %BlueprintEdited{} | :ok | {:error, atom()}
  def execute(%__MODULE__{id: nil}, %CreateBlueprint{
        blueprint_id: bp_id,
        kind: kind,
        name: name,
        short_description: short,
        long_description: long,
        fixed: fixed,
        behaviors: behaviors,
        lore: lore,
        behavior_groups: behavior_groups,
        quests: quests
      }) do
    cond do
      name in [nil, ""] ->
        {:error, :name_required}

      short in [nil, ""] ->
        {:error, :short_description_required}

      long in [nil, ""] ->
        {:error, :long_description_required}

      true ->
        %BlueprintCreated{
          blueprint_id: bp_id,
          kind: kind || "npc",
          name: name,
          short_description: short,
          long_description: long,
          fixed: !!fixed,
          revision: 1,
          behaviors: behaviors || [],
          lore: lore || "",
          behavior_groups: behavior_groups || [],
          quests: quests || []
        }
    end
  end

  def execute(%__MODULE__{}, %CreateBlueprint{}),
    do: {:error, :blueprint_already_exists}

  def execute(%__MODULE__{id: nil}, %EditBlueprint{}),
    do: {:error, :blueprint_not_found}

  def execute(
        %__MODULE__{revision: current_revision} = state,
        %EditBlueprint{
          expected_revision: expected_revision,
          fields_changed: fields_changed
        }
      )
      when is_map(fields_changed) do
    cond do
      expected_revision != current_revision ->
        {:error, :stale_revision}

      not Enum.all?(Map.keys(fields_changed), &(&1 in @editable_fields)) ->
        {:error, :invalid_field}

      no_changes?(state, fields_changed) ->
        :ok

      true ->
        %BlueprintEdited{
          blueprint_id: state.id,
          fields_changed: only_changed(state, fields_changed),
          revision: current_revision + 1
        }
    end
  end

  defp no_changes?(state, fields_changed) do
    Enum.all?(fields_changed, fn {k, v} -> Map.get(state, k) == v end)
  end

  defp only_changed(state, fields_changed) do
    fields_changed
    |> Enum.reject(fn {k, v} -> Map.get(state, k) == v end)
    |> Map.new()
  end

  @spec apply(%__MODULE__{}, %BlueprintCreated{} | %BlueprintEdited{}) :: %__MODULE__{}
  def apply(%__MODULE__{} = state, %BlueprintCreated{} = e) do
    %__MODULE__{
      state
      | id: e.blueprint_id,
        kind: e.kind,
        name: e.name,
        short_description: e.short_description,
        long_description: e.long_description,
        fixed: e.fixed,
        revision: e.revision,
        behaviors: e.behaviors || [],
        lore: e.lore || "",
        behavior_groups: e.behavior_groups || [],
        quests: e.quests || []
    }
  end

  def apply(%__MODULE__{} = state, %BlueprintEdited{
        fields_changed: fields_changed,
        revision: revision
      }) do
    Enum.reduce(fields_changed, %__MODULE__{state | revision: revision}, fn {k, v}, acc ->
      Map.put(acc, k, v)
    end)
  end
end
