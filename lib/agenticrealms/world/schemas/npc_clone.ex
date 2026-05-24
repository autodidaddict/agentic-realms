defmodule AgenticRealms.World.Schemas.NPCClone do
  @moduledoc """
  An NPC instance in the world. A clone is spawned from a blueprint and
  carries a denormalized snapshot of the blueprint's data as of the moment
  of spawning (full-copy semantics — feature 008 FR-007 / FR-012).

  Identified by the pair `(blueprint_id, serial)` within its blueprint
  family. The LPMud-style debug identity (`debug_id/1`) is exposed for
  admin / telemetry / debug audiences ONLY — never for player-facing
  surfaces (FR-011).

  See `specs/008-npc-blueprints/data-model.md` §2.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "npc_clones" do
    field :serial, :integer
    field :name, :string
    field :short_description, :string
    field :long_description, :string

    belongs_to :blueprint, AgenticRealms.World.Schemas.NPCBlueprint,
      foreign_key: :blueprint_id,
      type: :string,
      references: :id

    belongs_to :room, AgenticRealms.World.Schemas.Room, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{
          id: String.t() | nil,
          serial: integer() | nil,
          name: String.t() | nil,
          short_description: String.t() | nil,
          long_description: String.t() | nil,
          blueprint_id: String.t() | nil,
          room_id: String.t() | nil
        }

  @doc """
  LPMud-style debug identity: `<display_name>#<serial>`. Used in telemetry
  and admin surfaces. MUST NOT appear in player-facing renders (FR-011).
  """
  @spec debug_id(t()) :: String.t()
  def debug_id(%__MODULE__{name: name, serial: serial}) do
    "#{name}##{serial}"
  end
end
