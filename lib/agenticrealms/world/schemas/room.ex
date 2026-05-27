defmodule AgenticRealms.World.Schemas.Room do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "world_rooms" do
    field :name, :string
    field :description, :string
    field :behaviors, {:array, :map}, default: []

    # Feature 012 — Maps. region_id becomes NOT NULL post-migration; the
    # other four fields default per FR-019 / FR-021 / FR-022.
    field :region_id, :binary_id
    field :map_visible, :boolean, default: true
    field :elevation, :integer, default: 0
    field :map_x, :integer
    field :map_y, :integer

    belongs_to :region, AgenticRealms.World.Schemas.Region,
      foreign_key: :region_id,
      references: :id,
      define_field: false

    has_many :exits, AgenticRealms.World.Schemas.Exit, foreign_key: :source_room_id
    has_many :objects, AgenticRealms.World.Schemas.Object, foreign_key: :room_id

    timestamps(type: :utc_datetime)
  end
end
