defmodule AgenticRealms.Repo.Migrations.CreatePlayerDiscoveredRooms do
  use Ecto.Migration

  # Feature 012 — Maps. Per-player record of personally-entered rooms.
  # Projected from PlayerDiscoveredRoom events emitted by the World.Player
  # aggregate's RecordRoomDiscovery handler. Composite PK guarantees
  # at most one row per (player, room).
  def change do
    create table(:player_discovered_rooms, primary_key: false) do
      add :player_id, references(:players, on_delete: :delete_all),
        primary_key: true,
        null: false

      add :room_id, references(:world_rooms, type: :binary_id, on_delete: :delete_all),
        primary_key: true,
        null: false

      add :discovered_at, :utc_datetime, null: false
    end
  end
end
