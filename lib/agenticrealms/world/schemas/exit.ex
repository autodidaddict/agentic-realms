defmodule AgenticRealms.World.Schemas.Exit do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "world_exits" do
    field :direction, :string

    # Feature 017 — Transient Regions. NULL = visible to everyone (global
    # exit). When set, the exit is listed and traversable only by this player
    # (the transient region's provision-owner, for the `:rift` entry exit).
    field :visible_to_user_id, :integer

    belongs_to :source_room, AgenticRealms.World.Schemas.Room, type: :binary_id
    belongs_to :target_room, AgenticRealms.World.Schemas.Room, type: :binary_id

    timestamps(type: :utc_datetime)
  end
end
