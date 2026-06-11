defmodule AgenticRealms.Repo.Migrations.CreateBehaviorGroups do
  use Ecto.Migration

  @moduledoc """
  Feature 015 — a behavior_group is a named, reusable group of behaviors, applicable
  to items/NPCs/rooms (cross-entity), composed via union onto a blueprint.
  Seed-populated only this milestone (no wizard authoring surface yet), so
  this is a plain read table — not event-sourced.
  """

  def change do
    create table(:behavior_groups, primary_key: false) do
      add :name, :string, primary_key: true
      add :description, :string
      add :behaviors, :jsonb, null: false, default: fragment("'[]'::jsonb")
      add :applies_to, {:array, :string}, null: false, default: ["npc"]
      timestamps(type: :utc_datetime)
    end

    create constraint(:behavior_groups, :behavior_groups_name_slug_shape,
             check: "name ~ '^[a-z][a-z0-9_]*$' AND char_length(name) BETWEEN 1 AND 64"
           )

    create constraint(:behavior_groups, :behavior_groups_applies_to_subset,
             check: "applies_to <@ ARRAY['item','npc','room']::varchar[]"
           )
  end
end
