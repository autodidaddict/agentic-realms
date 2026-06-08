defmodule AgenticRealms.Repo.Migrations.AddTransientRegionFields do
  use Ecto.Migration

  # Feature 017 — Transient Regions. Adds the lifecycle/ownership columns to
  # the `regions` read model. `source_room_id`/`origin_room_id`/
  # `provision_owner_id` are intentionally plain columns (NOT foreign keys):
  # purge deletes the transient rooms before the region row, so an
  # `origin_room_id` FK with on_delete: :restrict would block teardown, and
  # the columns are operational denormalizations (mirroring `npc_clones.room_id`).
  def change do
    alter table(:regions) do
      add :kind, :string, null: false, default: "permanent"
      add :provision_owner_id, :bigint
      add :provisioned_at, :utc_datetime_usec
      add :source_room_id, :binary_id
      add :origin_room_id, :binary_id
      add :owner_offline_since, :utc_datetime_usec
      add :destroyed_at, :utc_datetime_usec
    end

    # Drives the FR-021 "one active transient region per owner" lookup and the
    # reaper's `WHERE kind = 'transient'` sweep.
    create index(:regions, [:kind, :provision_owner_id])
  end
end
