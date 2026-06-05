defmodule AgenticRealms.Repo.Migrations.NpcClonesViaEntityLifecycle do
  use Ecto.Migration

  @moduledoc """
  Feature 016 Phase 4 — NPC spawn moves onto the entity lifecycle
  (clone into the void, then move into a room). The `npc_clones` row is now
  written by the `EntityProjector`; an entity is briefly in the void between
  `EntityCloned` and `EntityMoved`, so `room_id` must be nullable.

  The denormalized `blueprint_id` / `serial` columns are retained (as plain
  references, not a live lineage) because feature 010 conversations and
  feature 013 NPC quests resolve an in-world NPC's quest catalog and lore via
  its `blueprint_id`, and examine telemetry / tick scope use `serial`.
  """

  def up do
    drop constraint(:npc_clones, "npc_clones_room_id_fkey")

    alter table(:npc_clones) do
      modify :room_id, :binary_id, null: true
    end
  end

  def down do
    alter table(:npc_clones) do
      modify :room_id, :binary_id, null: false
    end

    alter table(:npc_clones) do
      modify :room_id, references(:world_rooms, type: :binary_id, on_delete: :restrict)
    end
  end
end
