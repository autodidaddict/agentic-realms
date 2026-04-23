defmodule AgenticRealms.Repo.Migrations.AddPreferencesToPlayers do
  use Ecto.Migration

  def change do
    alter table(:players) do
      add :theme, :string, default: "phosphor", null: false
      add :density, :string, default: "comfortable", null: false
    end
  end
end
