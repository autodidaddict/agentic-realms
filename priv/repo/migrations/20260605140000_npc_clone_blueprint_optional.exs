defmodule AgenticRealms.Repo.Migrations.NpcCloneBlueprintOptional do
  use Ecto.Migration

  @moduledoc """
  Feature 015 — `npc_clones` cleanup.

  * `blueprint_id` becomes **nullable**: a freeform (one-off) NPC is cloned
    straight into a room with no blueprint behind it. It is kept (not dropped)
    only as the stable, denormalized quest-identity tag feature-013 quests
    group on — it is NOT lineage (no propagation; the clone is a full copy).
  * `serial` is **dropped** entirely. It was vestigial — only cosmetic
    "Garrick#2" disambiguation in telemetry and a nil-tolerant tick sort
    tiebreaker. Clones are identified by their entity id. Dropping the column
    also removes the `(blueprint_id, serial)` unique index; the plain
    `blueprint_id` index (from the introducing migration) remains.
  """

  def change do
    execute(
      "ALTER TABLE npc_clones ALTER COLUMN blueprint_id DROP NOT NULL",
      "ALTER TABLE npc_clones ALTER COLUMN blueprint_id SET NOT NULL"
    )

    alter table(:npc_clones) do
      remove :serial, :integer, null: false
    end
  end
end
