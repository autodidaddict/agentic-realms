defmodule AgenticRealms.World.Schemas.Blueprint do
  @moduledoc """
  The unified authored template (`blueprints` read model),
  keyed by slug, discriminated by `kind` (`"object" | "npc"`). Replaces the
  former `object_blueprints` (014) + `npc_blueprints` (008/013) tables.

  Shared core (`name`/`short_description`/`long_description`/`fixed`/`revision`)
  applies to every kind. The NPC-flavored columns (`behaviors`/`lore`/
  `behavior_groups`/`quests`) are empty for objects in this milestone (the table
  supports them; the object authoring UI doesn't expose them yet).

  Spawned instances are freestanding: a blueprint stamps a clone's frozen
  fields at spawn and is never consulted at render time.
  """

  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  schema "blueprints" do
    field :kind, :string, default: "npc"
    field :name, :string
    field :short_description, :string
    field :long_description, :string
    field :fixed, :boolean, default: false
    field :revision, :integer, default: 1
    field :behaviors, {:array, :map}, default: []
    field :lore, :string, default: ""
    field :behavior_groups, {:array, :string}, default: []
    field :quests, {:array, :map}, default: []

    field :str, :integer, default: 12
    field :dex, :integer, default: 12
    field :con, :integer, default: 12
    field :int, :integer, default: 12
    field :wis, :integer, default: 12
    field :cha, :integer, default: 12
    field :level, :integer, default: 1
    field :max_hp, :integer, default: 10
    field :max_mana, :integer, default: 10

    has_many :clones, AgenticRealms.World.Schemas.NPCClone, foreign_key: :blueprint_id

    timestamps(type: :utc_datetime)
  end
end
