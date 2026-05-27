defmodule AgenticRealms.Repo.Migrations.CreateQuestInstances do
  use Ecto.Migration

  # Feature 013 — Quests. One row per accepted FetchQuest instance.
  # `definition_snapshot` carries the full quest definition as of accept
  # time so subsequent NPCBlueprint catalog edits never invalidate
  # in-flight quests.
  def change do
    create table(:quest_instances, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :player_id, references(:players, on_delete: :restrict), null: false

      add :npc_blueprint_id, references(:npc_blueprints, type: :string, on_delete: :restrict),
        null: false

      add :slug, :string, null: false
      add :state, :string, null: false
      add :accepted_at, :utc_datetime, null: false
      add :completed_at, :utc_datetime
      add :definition_snapshot, :map, null: false
      add :reward_object_id, :binary_id

      timestamps(type: :utc_datetime)
    end

    # FR-012 — sticky one-time completion per (player, NPC, slug). Partial
    # unique index so two ACTIVE quests for the same triple don't collide
    # (although the wrapper refuses :already_active first).
    create unique_index(
             :quest_instances,
             [:player_id, :npc_blueprint_id, :slug],
             where: "state = 'completed'",
             name: :quest_instances_unique_completed
           )

    # Fast lookup: "active quests for this player".
    create index(:quest_instances, [:player_id, :state])

    # Fast lookup: "all quest instances of this (NPC, slug)" — used by
    # the accept_quest wrapper to check for active duplicates.
    create index(:quest_instances, [:npc_blueprint_id, :slug])
  end
end
