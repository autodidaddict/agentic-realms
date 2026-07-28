defmodule AgenticRealms.Repo.Migrations.AddSrdCharacterColumns do
  use Ecto.Migration

  # Feature 020 — SRD 5e Character Stats. Players get a real SRD character:
  # a species, class, and background, plus the proficiencies those grant. The
  # ability scores, level, xp, and hitpoints feature 019 added stay as they are.
  #
  # Mana goes. The SRD has no such resource, and spell slots will arrive with
  # spellcasting. Only the player columns are dropped — npc_clones keeps its
  # mana as unread state, because NPC records are out of scope this milestone.
  #
  # No compatibility defaults on the new columns. The world is purged and
  # restaged (mix world.reset), so there are no pre-existing rows to keep valid.
  # The slug columns are nullable because a row can legally exist before its
  # CharacterCreated event has been projected; the array defaults serve that
  # same window.

  # Feature 019's stat columns were NOT NULL with placeholder defaults, because
  # PlayerSpawned seeded them. It no longer does: stats arrive with
  # CharacterCreated, and either event may create the row first on a replay. So
  # they become nullable with no default, and a NULL means "not created yet" —
  # the same thing the slug columns mean.
  @relaxed [
    {:str, 12},
    {:dex, 12},
    {:con, 12},
    {:int, 12},
    {:wis, 12},
    {:cha, 12},
    {:level, 1},
    {:xp, 0},
    {:hp, 10},
    {:max_hp, 10}
  ]

  def change do
    alter table(:player_state) do
      add :species_slug, :string
      add :class_slug, :string
      add :background_slug, :string
      add :size, :string

      add :skill_proficiencies, {:array, :string}, null: false, default: []
      add :save_proficiencies, {:array, :string}, null: false, default: []
      add :feat_slugs, {:array, :string}, null: false, default: []

      for {column, was} <- @relaxed do
        modify column, :integer,
          null: true,
          default: nil,
          from: {:integer, null: false, default: was}
      end

      remove :mana, :integer, null: false, default: 10
      remove :max_mana, :integer, null: false, default: 10
    end
  end
end
