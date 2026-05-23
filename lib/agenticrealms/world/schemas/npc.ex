defmodule AgenticRealms.World.Schemas.NPC do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "world_npcs" do
    field :name, :string
    field :short_description, :string
    field :long_description, :string

    belongs_to :room, AgenticRealms.World.Schemas.Room, type: :binary_id

    timestamps(type: :utc_datetime)
  end
end
