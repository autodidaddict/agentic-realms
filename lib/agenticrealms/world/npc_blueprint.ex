defmodule AgenticRealms.World.NPCBlueprint do
  @moduledoc """
  NPC Blueprint aggregate. Owns the authored template for a kind of NPC
  (display name, descriptions, behaviors, lore, quest catalog).

  Identified by `:blueprint_id` (slug string) with prefix `"npc-blueprint-"`.

  **Feature 016 note**: clone spawning (`SpawnNPCClone` → `NPCClonedFromBlueprint`)
  and the per-blueprint `serial`/`clone_ids` tracking were removed when NPC
  spawning moved onto the entity lifecycle. A clone is now cloned into
  existence and moved into a room via `World.Entity` (see
  `World.Commands.spawn_npc_clone/3`), with the blueprint's data copied into
  the `EntityCloned` payload at dispatch time (full-copy). This aggregate now
  owns blueprint authoring only.

  See `specs/008-npc-blueprints/data-model.md` §3 and
  `specs/016-entity-containment/`.
  """

  defstruct id: nil,
            name: nil,
            short_description: nil,
            long_description: nil,
            behaviors: [],
            lore: "",
            # Feature 013 — Quests. Per-NPC FetchQuest catalog.
            quests: []

  alias AgenticRealms.World.Commands.CreateNPCBlueprint
  alias AgenticRealms.World.Events.NPCBlueprintCreated

  # --- CreateNPCBlueprint -------------------------------------------------

  @spec execute(%__MODULE__{}, %CreateNPCBlueprint{}) ::
          %NPCBlueprintCreated{} | {:error, atom()}
  def execute(%__MODULE__{id: nil}, %CreateNPCBlueprint{
        blueprint_id: bp_id,
        name: name,
        short_description: short,
        long_description: long,
        behaviors: behaviors,
        lore: lore,
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
        %NPCBlueprintCreated{
          blueprint_id: bp_id,
          name: name,
          short_description: short,
          long_description: long,
          behaviors: behaviors,
          lore: lore || "",
          # Feature 013 — pass the catalog through verbatim; validation
          # of catalog shape lives in `Commands.create_npc_blueprint/*`.
          quests: quests || []
        }
    end
  end

  def execute(%__MODULE__{}, %CreateNPCBlueprint{}),
    do: {:error, :blueprint_already_exists}

  # --- apply/2 ------------------------------------------------------------

  @spec apply(%__MODULE__{}, %NPCBlueprintCreated{}) :: %__MODULE__{}
  def apply(
        %__MODULE__{} = state,
        %NPCBlueprintCreated{
          blueprint_id: bp_id,
          name: name,
          short_description: short,
          long_description: long,
          behaviors: behaviors,
          lore: lore
        } = event
      ) do
    %__MODULE__{
      state
      | id: bp_id,
        name: name,
        short_description: short,
        long_description: long,
        behaviors: behaviors,
        lore: lore || "",
        # Feature 013 — Map.get/3 defends against legacy events
        # serialized before this field existed.
        quests: Map.get(event, :quests, []) || []
    }
  end
end
