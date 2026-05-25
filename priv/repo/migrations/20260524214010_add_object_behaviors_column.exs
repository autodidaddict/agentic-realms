defmodule AgenticRealms.Repo.Migrations.AddObjectBehaviorsColumn do
  use Ecto.Migration

  def change do
    alter table(:world_objects) do
      add :behaviors, :map, null: false, default: fragment("'[]'::jsonb")
    end
  end
end
