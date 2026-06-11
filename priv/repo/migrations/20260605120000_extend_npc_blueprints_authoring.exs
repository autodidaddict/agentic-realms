defmodule AgenticRealms.Repo.Migrations.ExtendNpcBlueprintsAuthoring do
  use Ecto.Migration

  @moduledoc """
  Feature 015 — wizard NPC authoring. Mirror the object-blueprint columns on
  `npc_blueprints`: a fixed `kind`, the ungettable `fixed` flag, referenced
  `behavior_groups` (names), and a monotonic `revision` for optimistic-lock edits.
  """

  def change do
    alter table(:npc_blueprints) do
      add :kind, :string, null: false, default: "npc"
      add :fixed, :boolean, null: false, default: false
      add :behavior_groups, {:array, :string}, null: false, default: []
      add :revision, :integer, null: false, default: 1
    end

    create constraint(:npc_blueprints, :npc_blueprints_kind_check, check: "kind = 'npc'")
    create constraint(:npc_blueprints, :npc_blueprints_revision_positive, check: "revision > 0")

    create constraint(:npc_blueprints, :npc_blueprints_id_slug_shape,
             check: "id ~ '^[a-z][a-z0-9_]*$' AND char_length(id) BETWEEN 1 AND 64"
           )

    create index(:npc_blueprints, [:kind])
  end
end
