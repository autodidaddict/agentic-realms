defmodule AgenticRealms.Repo.Migrations.AddLoreColumns do
  use Ecto.Migration

  def change do
    alter table(:npc_blueprints) do
      add :lore, :text, null: false, default: ""
    end

    alter table(:npc_clones) do
      add :lore, :text, null: false, default: ""
    end
  end
end
