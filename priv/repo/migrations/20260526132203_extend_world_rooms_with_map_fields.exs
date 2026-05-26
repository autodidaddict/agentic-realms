defmodule AgenticRealms.Repo.Migrations.ExtendWorldRoomsWithMapFields do
  use Ecto.Migration

  # Feature 012 — Maps. Add region_id (NOT NULL FK), map_visible bool,
  # elevation integer, optional (map_x, map_y) coordinates. Enforces FR-022a
  # uniqueness via a partial unique index that applies only when coords
  # are set (off-map rooms do not participate in uniqueness).
  #
  # Safe to add region_id as NOT NULL because the previous migration
  # truncated world_rooms — there are zero rows to backfill.
  def change do
    alter table(:world_rooms) do
      add :region_id, references(:regions, type: :binary_id, on_delete: :restrict), null: false
      add :map_visible, :boolean, null: false, default: true
      add :elevation, :integer, null: false, default: 0
      add :map_x, :integer
      add :map_y, :integer
    end

    # Partial unique index: only when coords are set. (region_id, elevation,
    # map_x, map_y) must be unique whenever both x and y are non-null.
    create unique_index(
             :world_rooms,
             [:region_id, :elevation, :map_x, :map_y],
             where: "map_x IS NOT NULL AND map_y IS NOT NULL",
             name: :world_rooms_unique_position
           )

    # Btree for MapView's bounded viewport query.
    create index(:world_rooms, [:region_id, :elevation])
  end
end
