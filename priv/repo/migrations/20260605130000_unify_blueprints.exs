defmodule AgenticRealms.Repo.Migrations.UnifyBlueprints do
  use Ecto.Migration

  @moduledoc """
  Feature 015 — collapse `object_blueprints` (014) + `npc_blueprints` (008/013)
  into one `blueprints` table keyed by slug, discriminated by `kind`. The
  `npc_clones.blueprint_id` and `quest_instances.npc_blueprint_id` FKs are
  retargeted to the unified table (slug unchanged). Drops the two old tables.

  Pre-launch + destroyable event log ⇒ reseed, not data-migrate: this runs
  during `mix world.reset` against a freshly-created (empty) DB, so the FK
  retarget never sees orphaned rows.
  """

  def change do
    create table(:blueprints, primary_key: false) do
      add :id, :string, primary_key: true
      add :kind, :string, null: false, default: "npc"
      add :name, :string, null: false
      add :short_description, :string, null: false
      add :long_description, :text, null: false
      add :fixed, :boolean, null: false, default: false
      add :revision, :integer, null: false, default: 1
      add :behaviors, :jsonb, null: false, default: fragment("'[]'::jsonb")
      add :lore, :text, null: false, default: ""
      add :toolsets, {:array, :string}, null: false, default: []
      add :quests, :jsonb, null: false, default: fragment("'[]'::jsonb")

      timestamps(type: :utc_datetime)
    end

    create constraint(:blueprints, :blueprints_id_slug_shape,
             check: "id ~ '^[a-z][a-z0-9_]*$' AND char_length(id) BETWEEN 1 AND 64"
           )

    create constraint(:blueprints, :blueprints_kind_check,
             check: "kind IN ('object', 'npc')"
           )

    create constraint(:blueprints, :blueprints_revision_positive, check: "revision > 0")

    create index(:blueprints, [:kind])

    # Retarget the clone + quest FKs from the per-kind tables to `blueprints`.
    alter table(:npc_clones) do
      modify :blueprint_id,
             references(:blueprints, type: :string, on_delete: :restrict),
             from: references(:npc_blueprints, type: :string, on_delete: :restrict)
    end

    alter table(:quest_instances) do
      modify :npc_blueprint_id,
             references(:blueprints, type: :string, on_delete: :restrict),
             from: references(:npc_blueprints, type: :string, on_delete: :restrict)
    end

    drop table(:npc_blueprints)
    drop table(:object_blueprints)
  end
end
