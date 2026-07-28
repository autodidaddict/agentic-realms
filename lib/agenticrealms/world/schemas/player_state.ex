defmodule AgenticRealms.World.Schemas.PlayerState do
  @moduledoc """
  A player's projected world state: where they are, and who their character is.

  Feature 020 — SRD 5e Character Stats. The character columns carry only what
  cannot be recomputed: the choices made at creation, and the two counters that
  change during play. Everything a character sheet shows beyond these —
  modifiers, proficiency bonus, saving throws, skills, armor class, initiative,
  hit dice, and the hit point maximum — is derived on read by
  `Srd.Character.derive/1` and never stored.

  The fields carry no defaults. A character arrives complete via
  `CharacterCreated`, so a placeholder ability score would never be correct and
  is never read; leaving one would let a row render a plausible character that
  nobody created.
  """

  use Ecto.Schema

  @primary_key {:player_id, :id, autogenerate: false}
  schema "player_state" do
    belongs_to :player, AgenticRealms.Accounts.Player,
      foreign_key: :player_id,
      define_field: false

    belongs_to :current_room, AgenticRealms.World.Schemas.Room, type: :binary_id

    # Who the character is. Slugs into the SRD content catalog.
    field :species_slug, :string
    field :class_slug, :string
    field :background_slug, :string
    field :size, :string

    # Ability scores, as chosen at creation.
    field :str, :integer
    field :dex, :integer
    field :con, :integer
    field :int, :integer
    field :wis, :integer
    field :cha, :integer

    # Progression and vitals.
    field :level, :integer
    field :xp, :integer
    field :hp, :integer
    field :max_hp, :integer

    # What the class, background, and species granted. Stored as strings; the
    # derived layer takes atoms.
    field :skill_proficiencies, {:array, :string}, default: []
    field :save_proficiencies, {:array, :string}, default: []
    # Recorded, not applied — feats have no mechanical effect this milestone.
    field :feat_slugs, {:array, :string}, default: []

    timestamps(type: :utc_datetime)
  end
end
