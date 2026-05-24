defmodule AgenticRealms.World.Schemas.Room do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "world_rooms" do
    field :name, :string
    field :description, :string
    field :behaviors, {:array, :map}, default: []

    has_many :exits, AgenticRealms.World.Schemas.Exit, foreign_key: :source_room_id
    has_many :objects, AgenticRealms.World.Schemas.Object, foreign_key: :room_id

    timestamps(type: :utc_datetime)
  end
end
