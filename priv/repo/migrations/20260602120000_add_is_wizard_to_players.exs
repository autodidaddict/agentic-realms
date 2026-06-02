defmodule AgenticRealms.Repo.Migrations.AddIsWizardToPlayers do
  use Ecto.Migration

  def change do
    alter table(:players) do
      add :is_wizard, :boolean, null: false, default: false
    end
  end
end
