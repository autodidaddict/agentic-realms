defmodule AgenticRealms.Repo.Migrations.AddBehaviorsColumns do
  use Ecto.Migration

  def change do
    alter table(:npc_blueprints) do
      add :behaviors, :jsonb, null: false, default: fragment("'[]'::jsonb")
    end

    alter table(:npc_clones) do
      add :behaviors, :jsonb, null: false, default: fragment("'[]'::jsonb")
    end

    alter table(:world_rooms) do
      add :behaviors, :jsonb, null: false, default: fragment("'[]'::jsonb")
    end
  end
end
