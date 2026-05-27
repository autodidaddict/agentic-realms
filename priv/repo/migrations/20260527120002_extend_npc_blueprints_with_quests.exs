defmodule AgenticRealms.Repo.Migrations.ExtendNpcBlueprintsWithQuests do
  use Ecto.Migration

  # Feature 013 — Quests. Adds the per-NPC FetchQuest catalog. Each entry
  # is a wizard-authored definition the NPC can offer in conversation.
  # Pre-existing blueprints get the default `[]` — they have no quests
  # to offer, which is exactly their prior behavior.
  def change do
    alter table(:npc_blueprints) do
      add :quests, :map, null: false, default: %{"_" => []}
    end

    # The default above is a workaround — Postgres requires a non-null
    # default and `:map` over `:jsonb`. We rewrite to `[]::jsonb` so the
    # default matches the intended array shape.
    execute(
      "ALTER TABLE npc_blueprints ALTER COLUMN quests SET DEFAULT '[]'::jsonb",
      "ALTER TABLE npc_blueprints ALTER COLUMN quests DROP DEFAULT"
    )

    execute(
      "UPDATE npc_blueprints SET quests = '[]'::jsonb WHERE quests::text = '{\"_\": []}'",
      ""
    )
  end
end
