defmodule AgenticRealms.Repo.Migrations.WorldObjectsContainerRef do
  use Ecto.Migration

  @moduledoc """
  Feature 016 — replace the ad-hoc `room_id`/`player_id` + XOR location
  model on `world_objects` with a single typed container reference
  `(container_type, container_id)`.

  `container_id` is a string holding the room UUID as-is, or a player id
  stringified, or NULL for the void. The event log is destroyable in the
  pre-launch phase, so this is a clean swap; the up-migration backfills
  existing rows for convenience but the canonical path is `mix world.reset`.
  """

  def up do
    alter table(:world_objects) do
      add :container_type, :string
      add :container_id, :string
    end

    # Backfill existing rows from the old location columns.
    execute("""
    UPDATE world_objects
    SET container_type = CASE WHEN room_id IS NOT NULL THEN 'room' ELSE 'player' END,
        container_id   = COALESCE(room_id::text, player_id::text)
    """)

    drop constraint(:world_objects, :exactly_one_location)
    drop index(:world_objects, [:room_id])
    drop index(:world_objects, [:player_id])

    alter table(:world_objects) do
      modify :container_type, :string, null: false
      remove :room_id
      remove :player_id
    end

    create constraint(:world_objects, :container_type_in_set,
             check: "container_type IN ('void','room','player','npc')"
           )

    create constraint(:world_objects, :void_iff_null_container_id,
             check: "(container_type = 'void') = (container_id IS NULL)"
           )

    create index(:world_objects, [:container_type, :container_id])
  end

  def down do
    alter table(:world_objects) do
      add :room_id, references(:world_rooms, type: :binary_id, on_delete: :restrict)
      add :player_id, references(:players, on_delete: :nilify_all)
    end

    execute("""
    UPDATE world_objects
    SET room_id   = CASE WHEN container_type = 'room' THEN container_id::uuid ELSE NULL END,
        player_id = CASE WHEN container_type = 'player' THEN container_id::integer ELSE NULL END
    """)

    drop constraint(:world_objects, :container_type_in_set)
    drop constraint(:world_objects, :void_iff_null_container_id)
    drop index(:world_objects, [:container_type, :container_id])

    alter table(:world_objects) do
      remove :container_type
      remove :container_id
    end

    create index(:world_objects, [:room_id])
    create index(:world_objects, [:player_id])

    create constraint(:world_objects, :exactly_one_location,
             check: "(room_id IS NOT NULL) <> (player_id IS NOT NULL)"
           )
  end
end
