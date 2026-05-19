defmodule AgenticRealms.World.Schemas.PlayerState do
  use Ecto.Schema

  @primary_key {:player_id, :id, autogenerate: false}
  schema "player_state" do
    belongs_to :player, AgenticRealms.Accounts.Player,
      foreign_key: :player_id,
      define_field: false

    belongs_to :current_room, AgenticRealms.World.Schemas.Room, type: :binary_id

    timestamps(type: :utc_datetime)
  end
end
