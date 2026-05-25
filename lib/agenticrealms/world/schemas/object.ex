defmodule AgenticRealms.World.Schemas.Object do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "world_objects" do
    field :name, :string
    field :short_description, :string
    field :long_description, :string
    field :fixed, :boolean, default: false
    field :behaviors, {:array, :map}, default: []

    belongs_to :room, AgenticRealms.World.Schemas.Room, type: :binary_id
    belongs_to :player, AgenticRealms.Accounts.Player

    timestamps(type: :utc_datetime)
  end
end
