defmodule AgenticRealms.World.Schemas.Region do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "regions" do
    field :name, :string

    # Feature 017 — Transient Regions. `kind` discriminates permanent regions
    # (the seeded world) from on-demand transient ones; the remaining fields
    # are populated only for `kind: "transient"`.
    field :kind, :string, default: "permanent"
    field :provision_owner_id, :integer
    field :provisioned_at, :utc_datetime_usec
    field :source_room_id, :binary_id
    field :origin_room_id, :binary_id
    field :owner_offline_since, :utc_datetime_usec
    field :destroyed_at, :utc_datetime_usec

    has_many :rooms, AgenticRealms.World.Schemas.Room, foreign_key: :region_id

    timestamps(type: :utc_datetime)
  end
end
