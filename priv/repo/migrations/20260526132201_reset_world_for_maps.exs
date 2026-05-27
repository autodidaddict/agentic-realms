defmodule AgenticRealms.Repo.Migrations.ResetWorldForMaps do
  use Ecto.Migration

  # Feature 012 — Maps. Hard reset per spec FR-020b: the existing world
  # tables are truncated before the new region/coord schema lands, and
  # any references to those rows in `player_state` are nullified. Paired
  # with a one-time `mix event_store.drop, event_store.create, event_store.init`
  # documented in `specs/012-maps/quickstart.md` §1. The seed then re-
  # authors the full Blackmire + Hollowvale world under the new schema.
  #
  # Safe because the software has not yet been used by real users
  # (clarification Q3). No backfill path is provided; no down migration
  # is required.
  def up do
    execute("""
    TRUNCATE world_rooms, world_exits, world_objects, npc_clones, npc_blueprints
    RESTART IDENTITY CASCADE
    """)

    execute("UPDATE player_state SET current_room_id = NULL")
  end

  def down do
    :ok
  end
end
