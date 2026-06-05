defmodule AgenticRealms.Repo.Migrations.NpcCloneBlueprintOptional do
  use Ecto.Migration

  @moduledoc """
  Feature 015 US5 — a freeform (one-off) NPC is cloned straight into a room
  with no blueprint behind it, so both `npc_clones.blueprint_id` AND
  `npc_clones.serial` become nullable: a freeform clone is not the Nth instance
  of any blueprint, so it carries neither. The `(blueprint_id, serial)` unique
  index still holds — Postgres treats NULLs as distinct, so multiple freeform
  clones coexist — and `max(serial)` (next-serial) ignores the NULL rows.
  """

  def change do
    execute(
      "ALTER TABLE npc_clones ALTER COLUMN blueprint_id DROP NOT NULL",
      "ALTER TABLE npc_clones ALTER COLUMN blueprint_id SET NOT NULL"
    )

    execute(
      "ALTER TABLE npc_clones ALTER COLUMN serial DROP NOT NULL",
      "ALTER TABLE npc_clones ALTER COLUMN serial SET NOT NULL"
    )
  end
end
