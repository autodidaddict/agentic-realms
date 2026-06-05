defmodule AgenticRealms.World.Router do
  @moduledoc """
  Commanded router for the world. Maps command structs to aggregates.

  Dispatch clauses are added per user story as each command type is
  introduced (see `specs/003-persisted-world/tasks.md`).
  """

  use Commanded.Commands.Router

  alias AgenticRealms.World.{Room, Player, Blueprint, Region, Quest, Entity}

  alias AgenticRealms.World.Commands.{
    CreateRoom,
    AddExit,
    SpawnPlayer,
    MovePlayer,
    CreateBlueprint,
    EditBlueprint,
    CreateRegion,
    RecordRoomDiscovery,
    AcceptQuest,
    FinalizeQuest,
    CloneEntity,
    MoveEntity,
    EditEntity
  }

  identify(Room, by: :room_id, prefix: "room-")
  identify(Player, by: :player_id, prefix: "player-")
  identify(Region, by: :region_id, prefix: "region-")
  identify(Quest, by: :quest_id, prefix: "quest-")

  # Feature 015 — unified Blueprint aggregate (object + npc), keyed by slug.
  identify(Blueprint, by: :blueprint_id, prefix: "blueprint-")

  # Feature 016 — Entity lifecycle. Every movable world entity (object or
  # NPC) is its own aggregate stream, owning its existence + current
  # container. clone/move/edit route here. (Object/NPC spawn, take/drop, and
  # placement are retrofitted onto these in Phases 3–4; the old Room/
  # NPCBlueprint dispatches below are removed at that point.)
  identify(Entity, by: :entity_id, prefix: "entity-")

  # Room authoring. Object/NPC placement and take/drop moved to the Entity
  # aggregate in feature 016, so the Room aggregate owns only rooms + exits.
  dispatch([CreateRoom, AddExit], to: Room)

  # Phase 4 (US1) + Phase 5 (US2): player lifecycle + movement routed to Player.
  # Feature 012: per-player room discovery also routed to Player.
  dispatch([SpawnPlayer, MovePlayer, RecordRoomDiscovery], to: Player)

  # Feature 012: region authoring
  dispatch([CreateRegion], to: Region)

  # Feature 013: quest lifecycle (accept + finalize). Each quest instance
  # is its own aggregate identified by quest_id.
  dispatch([AcceptQuest, FinalizeQuest], to: Quest)

  # Feature 015: unified Blueprint authoring + editing (object + npc).
  dispatch([CreateBlueprint, EditBlueprint], to: Blueprint)

  # Feature 016: entity clone / move / edit — the one uniform lifecycle.
  dispatch([CloneEntity, MoveEntity, EditEntity], to: Entity)
end
