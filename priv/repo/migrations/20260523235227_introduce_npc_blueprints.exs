defmodule AgenticRealms.Repo.Migrations.IntroduceNpcBlueprints do
  use Ecto.Migration

  def change do
    drop_if_exists(table(:world_npcs))

    create table(:npc_blueprints, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string, null: false
      add :short_description, :string, null: false
      add :long_description, :text, null: false
      add :is_synthetic, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create table(:npc_clones, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :blueprint_id,
          references(:npc_blueprints, type: :string, on_delete: :restrict),
          null: false

      add :serial, :integer, null: false
      add :name, :string, null: false
      add :short_description, :string, null: false
      add :long_description, :text, null: false

      add :room_id,
          references(:world_rooms, type: :binary_id, on_delete: :restrict),
          null: false

      timestamps(type: :utc_datetime)
    end

    create index(:npc_clones, [:room_id])
    create index(:npc_clones, [:blueprint_id])
    create unique_index(:npc_clones, [:blueprint_id, :serial])

    create unique_index(
             :npc_clones,
             ["room_id", "LOWER(name)"],
             name: :npc_clones_room_id_lower_name_index
           )

    # NOTE: WorldProjector subscription reset for FR-021a is NOT done here.
    # The Commanded subscription tracking lives in the EventStore database,
    # which is separate from the main Repo. The recommended development
    # workflow after this migration lands is:
    #
    #   mix event_store.reset && mix ecto.reset
    #
    # ... which wipes both stores and re-seeds from scratch. For production-
    # style migrations that preserve event history, the deployment runbook
    # includes a manual step:
    #
    #   AgenticRealms.EventStore.delete_subscription(
    #     "$all",
    #     "AgenticRealms.World.Projections.WorldProjector"
    #   )
    #
    # The projector then re-subscribes from event position 0 on the next
    # application start, exercising the synthetic-blueprint path for any
    # legacy NPCSpawnedInRoom events. See
    # specs/008-npc-blueprints/contracts/migration.md.
  end
end
