defmodule AgenticRealms.World.Schemas.NPCClone do
  @moduledoc """
  An NPC instance in the world. A clone is spawned from a blueprint (or, for a
  freeform NPC, from nothing) and carries a denormalized full-copy snapshot of
  that data as of the moment of spawning (feature 008 FR-007 / FR-012).

  Identified by its own entity `id`. `blueprint_id` is a nullable, denormalized
  quest-identity tag (feature 013 groups quest progress on it) — NOT lineage,
  and absent for freeform NPCs. The LPMud-style debug identity (`debug_id/1`)
  is exposed for admin / telemetry / debug audiences ONLY — never for
  player-facing surfaces (FR-011).

  See `specs/008-npc-blueprints/data-model.md` §2.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "npc_clones" do
    field :name, :string
    field :short_description, :string
    field :long_description, :string
    # Effective behaviors (behavior_groups ∪ direct), frozen at spawn.
    field :behaviors, {:array, :map}, default: []
    field :lore, :string, default: ""
    # Feature 015 — authoring/extract provenance, frozen at spawn.
    field :fixed, :boolean, default: false
    field :behavior_groups, {:array, :string}, default: []
    field :direct_behaviors, {:array, :map}, default: []

    belongs_to :blueprint, AgenticRealms.World.Schemas.Blueprint,
      foreign_key: :blueprint_id,
      type: :string,
      references: :id

    belongs_to :room, AgenticRealms.World.Schemas.Room, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          short_description: String.t() | nil,
          long_description: String.t() | nil,
          blueprint_id: String.t() | nil,
          room_id: String.t() | nil
        }

  @doc """
  LPMud-style debug identity: `<display_name>#<entity_id>`. Used in telemetry
  and admin surfaces. MUST NOT appear in player-facing renders (FR-011).
  """
  @spec debug_id(t()) :: String.t()
  def debug_id(%__MODULE__{name: name, id: id}) do
    "#{name}##{id}"
  end
end
