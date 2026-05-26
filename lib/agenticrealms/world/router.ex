defmodule AgenticRealms.World.Router do
  @moduledoc """
  Commanded router for the world. Maps command structs to aggregates.

  Dispatch clauses are added per user story as each command type is
  introduced (see `specs/003-persisted-world/tasks.md`).
  """

  use Commanded.Commands.Router

  alias AgenticRealms.World.{Room, Player, NPCBlueprint, Region}

  alias AgenticRealms.World.Commands.{
    CreateRoom,
    AddExit,
    PlaceObject,
    SpawnPlayer,
    MovePlayer,
    TakeObject,
    DropObject,
    CreateNPCBlueprint,
    SpawnNPCClone,
    CreateRegion,
    RecordRoomDiscovery
  }

  identify(Room, by: :room_id, prefix: "room-")
  identify(Player, by: :player_id, prefix: "player-")
  identify(NPCBlueprint, by: :blueprint_id, prefix: "npc-blueprint-")
  identify(Region, by: :region_id, prefix: "region-")

  # Phase 3 (US5) + Phase 6 (US3): room commands routed to Room
  dispatch([CreateRoom, AddExit, PlaceObject, TakeObject, DropObject], to: Room)

  # Phase 4 (US1) + Phase 5 (US2): player lifecycle + movement routed to Player.
  # Feature 012: per-player room discovery also routed to Player.
  dispatch([SpawnPlayer, MovePlayer, RecordRoomDiscovery], to: Player)

  # Feature 008: NPC blueprint authoring + cloning
  dispatch([CreateNPCBlueprint, SpawnNPCClone], to: NPCBlueprint)

  # Feature 012: region authoring
  dispatch([CreateRegion], to: Region)
end
