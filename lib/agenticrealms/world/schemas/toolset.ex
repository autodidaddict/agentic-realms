defmodule AgenticRealms.World.Schemas.Toolset do
  @moduledoc """
  A named, reusable group of behaviors (feature-009 `(trigger, [action])`
  tuples) applicable to items, NPCs, or rooms (cross-entity). Composed via
  union onto a blueprint (feature 015). Seed-populated only this milestone.
  """
  use Ecto.Schema

  @primary_key {:name, :string, autogenerate: false}
  schema "toolsets" do
    field :description, :string
    field :behaviors, {:array, :map}, default: []
    field :applies_to, {:array, :string}, default: ["npc"]

    timestamps(type: :utc_datetime)
  end
end
