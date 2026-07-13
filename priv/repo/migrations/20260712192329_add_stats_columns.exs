defmodule AgenticRealms.Repo.Migrations.AddStatsColumns do
  use Ecto.Migration

  # Feature 019 — Real Stats. Adds ability scores, level, hitpoints, and mana
  # to the player and NPC read models, plus base authoring columns on
  # blueprints. Players additionally carry experience (xp); NPCs never do.
  # SQL defaults keep any pre-existing rows valid; the world is re-seeded
  # afterward (event log is destroyable pre-launch).

  def change do
    alter table(:player_state) do
      add :str, :integer, null: false, default: 12
      add :dex, :integer, null: false, default: 12
      add :con, :integer, null: false, default: 12
      add :int, :integer, null: false, default: 12
      add :wis, :integer, null: false, default: 12
      add :cha, :integer, null: false, default: 12
      add :level, :integer, null: false, default: 1
      add :xp, :integer, null: false, default: 0
      add :hp, :integer, null: false, default: 10
      add :max_hp, :integer, null: false, default: 10
      add :mana, :integer, null: false, default: 10
      add :max_mana, :integer, null: false, default: 10
    end

    alter table(:npc_clones) do
      add :str, :integer, null: false, default: 12
      add :dex, :integer, null: false, default: 12
      add :con, :integer, null: false, default: 12
      add :int, :integer, null: false, default: 12
      add :wis, :integer, null: false, default: 12
      add :cha, :integer, null: false, default: 12
      add :level, :integer, null: false, default: 1
      add :hp, :integer, null: false, default: 10
      add :max_hp, :integer, null: false, default: 10
      add :mana, :integer, null: false, default: 10
      add :max_mana, :integer, null: false, default: 10
    end

    # Base authoring stats for NPC-kind blueprints; ignored for object kind.
    alter table(:blueprints) do
      add :str, :integer, null: false, default: 12
      add :dex, :integer, null: false, default: 12
      add :con, :integer, null: false, default: 12
      add :int, :integer, null: false, default: 12
      add :wis, :integer, null: false, default: 12
      add :cha, :integer, null: false, default: 12
      add :level, :integer, null: false, default: 1
      add :max_hp, :integer, null: false, default: 10
      add :max_mana, :integer, null: false, default: 10
    end
  end
end
