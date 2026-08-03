defmodule AgenticRealms.World.Schemas.Exit do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "world_exits" do
    field :direction, :string

    field :visible_to_user_id, :integer

    belongs_to :source_room, AgenticRealms.World.Schemas.Room, type: :binary_id
    belongs_to :target_room, AgenticRealms.World.Schemas.Room, type: :binary_id

    timestamps(type: :utc_datetime)
  end
end
