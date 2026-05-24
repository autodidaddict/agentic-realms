defmodule AgenticRealms.World.NPCBlueprint do
  @moduledoc """
  NPC Blueprint aggregate. Owns the authored template for a kind of NPC
  (display name, descriptions) and the per-blueprint serial counter that
  assigns sequential numbers to clones spawned from this blueprint.

  Identified by `:blueprint_id` (slug string) with prefix `"npc-blueprint-"`.

  **Full-copy materialization**: when a `SpawnNPCClone` command arrives,
  the aggregate stamps its CURRENT `name`, `short_description`, and
  `long_description` into the emitted `NPCClonedFromBlueprint` event. The
  clone row is built from the event payload; the blueprint table is never
  consulted at render time. Subsequent blueprint edits (which are not
  exposed in this feature — FR-005a) do NOT propagate to existing clones.

  See `specs/008-npc-blueprints/data-model.md` §3 and `contracts/commands.md`.
  """

  defstruct id: nil,
            name: nil,
            short_description: nil,
            long_description: nil,
            behaviors: [],
            lore: "",
            next_serial: 1,
            clone_ids: MapSet.new()

  alias AgenticRealms.World.Commands.{CreateNPCBlueprint, SpawnNPCClone}
  alias AgenticRealms.World.Events.{NPCBlueprintCreated, NPCClonedFromBlueprint}

  # --- CreateNPCBlueprint -------------------------------------------------

  def execute(%__MODULE__{id: nil}, %CreateNPCBlueprint{
        blueprint_id: bp_id,
        name: name,
        short_description: short,
        long_description: long,
        behaviors: behaviors,
        lore: lore
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
          lore: lore || ""
        }
    end
  end

  def execute(%__MODULE__{}, %CreateNPCBlueprint{}),
    do: {:error, :blueprint_already_exists}

  # --- SpawnNPCClone ------------------------------------------------------
  # Full-copy materialization point. The aggregate's CURRENT name / short /
  # long are stamped into the emitted event payload.

  def execute(%__MODULE__{id: nil}, %SpawnNPCClone{}),
    do: {:error, :blueprint_not_found}

  def execute(
        %__MODULE__{
          id: bp_id,
          name: name,
          short_description: short,
          long_description: long,
          behaviors: behaviors,
          lore: lore,
          next_serial: serial,
          clone_ids: clones
        },
        %SpawnNPCClone{blueprint_id: bp_id, clone_id: cid, room_id: rid}
      ) do
    if MapSet.member?(clones, cid) do
      {:error, :clone_id_already_used}
    else
      %NPCClonedFromBlueprint{
        blueprint_id: bp_id,
        clone_id: cid,
        room_id: rid,
        serial: serial,
        name: name,
        short_description: short,
        long_description: long,
        behaviors: behaviors,
        lore: lore
      }
    end
  end

  # --- apply/2 ------------------------------------------------------------

  def apply(%__MODULE__{} = state, %NPCBlueprintCreated{
        blueprint_id: bp_id,
        name: name,
        short_description: short,
        long_description: long,
        behaviors: behaviors,
        lore: lore
      }) do
    %__MODULE__{
      state
      | id: bp_id,
        name: name,
        short_description: short,
        long_description: long,
        behaviors: behaviors,
        lore: lore || ""
    }
  end

  def apply(
        %__MODULE__{next_serial: s, clone_ids: c} = state,
        %NPCClonedFromBlueprint{clone_id: cid}
      ) do
    %__MODULE__{state | next_serial: s + 1, clone_ids: MapSet.put(c, cid)}
  end
end
