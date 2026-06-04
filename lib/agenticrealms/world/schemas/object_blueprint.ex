defmodule AgenticRealms.World.Schemas.ObjectBlueprint do
  @moduledoc """
  Authored archetype for a kind of object. The source of denormalized data
  at the moment a copy is spawned into the world; never consulted at render
  time (consistent with feature 008's `is_synthetic`/`NPCBlueprint` pattern,
  generalized).

  - `id` is the human-typable slug per FR-007a (no UUIDs).
  - `kind` is fixed to `"object"` in milestone 1; milestone 2 widens to
    `"npc"` and folds spec 008's `npc_blueprints` here.
  - `revision` is a monotonic counter (FR-008). Each field-changing edit
    increments by 1. No-op commits don't bump.

  See `specs/014-item-blueprints/data-model.md` §1.2.
  """

  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  schema "object_blueprints" do
    field :kind, :string, default: "object"
    field :name, :string
    field :short_description, :string
    field :long_description, :string
    field :fixed, :boolean, default: false
    field :revision, :integer, default: 1

    timestamps(type: :utc_datetime)
  end
end
