defmodule AgenticRealms.World.Schemas.PlayerState do
  use Ecto.Schema

  @primary_key {:player_id, :id, autogenerate: false}
  schema "player_state" do
    belongs_to :player, AgenticRealms.Accounts.Player,
      foreign_key: :player_id,
      define_field: false

    belongs_to :current_room, AgenticRealms.World.Schemas.Room, type: :binary_id

    # Feature 019 — Real Stats. Ability scores, progression, vitals.
    field :str, :integer, default: 12
    field :dex, :integer, default: 12
    field :con, :integer, default: 12
    field :int, :integer, default: 12
    field :wis, :integer, default: 12
    field :cha, :integer, default: 12
    field :level, :integer, default: 1
    field :xp, :integer, default: 0
    field :hp, :integer, default: 10
    field :max_hp, :integer, default: 10
    field :mana, :integer, default: 10
    field :max_mana, :integer, default: 10

    timestamps(type: :utc_datetime)
  end
end
