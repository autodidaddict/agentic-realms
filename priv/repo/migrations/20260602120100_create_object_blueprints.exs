defmodule AgenticRealms.Repo.Migrations.CreateObjectBlueprints do
  use Ecto.Migration

  def change do
    create table(:object_blueprints, primary_key: false) do
      add :id, :text, primary_key: true
      add :kind, :string, null: false, default: "object"
      add :name, :string, null: false
      add :short_description, :string, null: false
      add :long_description, :text, null: false
      add :fixed, :boolean, null: false, default: false
      add :revision, :integer, null: false, default: 1

      timestamps(type: :utc_datetime)
    end

    # FR-007a — id is the slug, human-typable, no UUIDs.
    create constraint(:object_blueprints, :id_slug_shape,
             check: "id ~ '^[a-z][a-z0-9_]*$' AND char_length(id) BETWEEN 1 AND 64"
           )

    # Milestone 1 ships only :object kind. Milestone 2 will add :npc to the
    # allowed list (see specs/014-item-blueprints/data-model.md §1.2).
    create constraint(:object_blueprints, :kind_in_allowed_set, check: "kind IN ('object')")

    create constraint(:object_blueprints, :revision_positive, check: "revision > 0")

    create index(:object_blueprints, [:kind])
  end
end
