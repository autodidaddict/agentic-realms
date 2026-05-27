defmodule AgenticRealms.World.Schemas.PlayerDiscoveredRoom do
  use Ecto.Schema

  @primary_key false
  schema "player_discovered_rooms" do
    field :player_id, :id, primary_key: true
    field :room_id, :binary_id, primary_key: true
    field :discovered_at, :utc_datetime
  end
end
