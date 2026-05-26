defmodule AgenticRealms.World.Schemas.Region do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "regions" do
    field :name, :string

    has_many :rooms, AgenticRealms.World.Schemas.Room, foreign_key: :region_id

    timestamps(type: :utc_datetime)
  end
end
