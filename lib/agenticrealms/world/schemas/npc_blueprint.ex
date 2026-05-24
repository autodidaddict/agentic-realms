defmodule AgenticRealms.World.Schemas.NPCBlueprint do
  @moduledoc """
  Authored template for a kind of NPC. The source of data at the moment a
  clone is spawned; never consulted at render time.

  Blueprints with `is_synthetic: true` are created by the projector's
  legacy-event replay path (feature 007 `NPCSpawnedInRoom` events). They
  are functionally identical to authored blueprints; the flag exists so
  future authoring tools can identify and optionally promote them.

  See `specs/008-npc-blueprints/data-model.md` §1.
  """

  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  schema "npc_blueprints" do
    field :name, :string
    field :short_description, :string
    field :long_description, :string
    field :is_synthetic, :boolean, default: false
    field :behaviors, {:array, :map}, default: []
    field :lore, :string, default: ""

    has_many :clones, AgenticRealms.World.Schemas.NPCClone, foreign_key: :blueprint_id

    timestamps(type: :utc_datetime)
  end
end
