defmodule AgenticRealms.Repo.Migrations.ExtendWorldObjectsWithQuestFields do
  use Ecto.Migration

  # Feature 013 — Quests. Objects spawned for a specific quest instance
  # carry both `quest_player_id` (visibility scope) and `quest_instance_id`
  # (lifecycle scope). Pre-existing objects have both NULL — behavior
  # unchanged.
  def change do
    alter table(:world_objects) do
      add :quest_player_id, references(:players, on_delete: :nilify_all)

      add :quest_instance_id,
          references(:quest_instances, type: :binary_id, on_delete: :delete_all)
    end

    # Both fields are set together or not at all. The pre-dispatch wrapper
    # and the projector cooperatively maintain this; the DB enforces it.
    create constraint(
             :world_objects,
             :world_objects_quest_fields_paired,
             check: "(quest_player_id IS NULL) = (quest_instance_id IS NULL)"
           )

    # Bulk cleanup at finalize scans by quest_instance_id.
    create index(:world_objects, [:quest_instance_id],
             where: "quest_instance_id IS NOT NULL",
             name: :world_objects_quest_instance_id_idx
           )
  end
end
