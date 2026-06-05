defmodule AgenticRealms.World.Schemas.NPCBlueprint do
  @moduledoc """
  Authored template for a kind of NPC. The source of data copied into an
  NPC's `EntityCloned` payload at spawn time (feature 016); never consulted
  at render time.

  The `is_synthetic` flag is a vestige of feature 007's legacy-event replay
  path (removed in feature 016); it now defaults to `false` for every
  blueprint and is retained only to avoid a read-model migration.

  See `specs/008-npc-blueprints/data-model.md` §1.
  """

  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  schema "npc_blueprints" do
    field :name, :string
    field :short_description, :string
    field :long_description, :string
    field :is_synthetic, :boolean, default: false
    # Feature 015 — wizard authoring (mirror object blueprints).
    field :kind, :string, default: "npc"
    field :fixed, :boolean, default: false
    # Referenced toolset names; effective behaviors = union(toolsets) ++ behaviors.
    field :toolsets, {:array, :string}, default: []
    field :revision, :integer, default: 1
    # Direct behaviors (the union with toolsets is composed at spawn time).
    field :behaviors, {:array, :map}, default: []
    field :lore, :string, default: ""

    # Feature 013 — Quests. Per-NPC catalog of FetchQuest definitions.
    # Wizard-authored at blueprint-creation time. Each entry follows the
    # shape in `specs/013-quest-system/contracts/npc-blueprint-quests.md`.
    field :quests, {:array, :map}, default: []

    has_many :clones, AgenticRealms.World.Schemas.NPCClone, foreign_key: :blueprint_id

    timestamps(type: :utc_datetime)
  end
end
