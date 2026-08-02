defmodule AgenticRealms.Repo.Migrations.AddCharacterNameAndChoices do
  use Ecto.Migration

  # Feature 021 — Interactive Character Creation. Three columns for what the
  # player now chooses rather than what configuration chose for them.
  #
  # `character_name` is the player's identity in the world from here on: it is
  # what other players see in rooms, speech, whispers, and presence, and the
  # account username goes back to being a login credential and nothing else.
  #
  # It is nullable, and deliberately so. Either PlayerStateProjector clause may
  # be the one that creates the row — a replay from position 0 can deliver
  # PlayerSpawned before CharacterCreated — so a NOT NULL here would crash the
  # projector on a legal ordering. The write side guarantees the value; the
  # column tolerates the ordering, exactly as the feature 020 slug columns do.
  #
  # `choices` holds the picks with no typed column of their own: tool
  # proficiencies, weapon masteries, and feature options such as a cleric's
  # Divine Order. Skill picks and feat picks keep their existing arrays, because
  # those are the facts Srd.Character.derive/1 consumes. A map rather than a
  # column per rule, so a choice the SRD content gains later needs no migration.

  def change do
    alter table(:player_state) do
      add :character_name, :string
      add :lineage_slug, :string
      add :choices, :map, null: false, default: %{}
    end

    # Serves the availability check during creation and the name-to-player
    # lookup that whispers and examine need now that names replace usernames.
    #
    # Not unique. The CharacterName aggregate is the authority on uniqueness, so
    # a duplicate can only arrive if the write side is already broken, and a
    # unique index would turn that into a halted projection for every player
    # rather than an error for the one who lost the race.
    create index(:player_state, ["lower(character_name)"],
             name: :player_state_character_name_lower_idx
           )
  end
end
