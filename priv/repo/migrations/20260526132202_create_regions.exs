defmodule AgenticRealms.Repo.Migrations.CreateRegions do
  use Ecto.Migration

  # Feature 012 — Regions are first-class. Each Room belongs to exactly
  # one region via the FK added in the next migration.
  def change do
    create table(:regions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:regions, [:name])
  end
end
