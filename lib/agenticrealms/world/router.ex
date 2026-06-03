defmodule AgenticRealms.World.Router do
  @moduledoc """
  Commanded router for the world. Maps command structs to aggregates.

  Dispatch clauses are added per user story as each command type is
  introduced (see `specs/003-persisted-world/tasks.md`).
  """

  use Commanded.Commands.Router

  alias AgenticRealms.World.{Room, Player, NPCBlueprint, Region, Quest, ObjectBlueprint}

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
    RecordRoomDiscovery,
    AcceptQuest,
    FinalizeQuest,
    CreateObjectBlueprint,
    EditObjectBlueprint,
    SpawnObjectFromBlueprint,
    SpawnObjectFreeform,
    EditObject
  }

  identify(Room, by: :room_id, prefix: "room-")
  identify(Player, by: :player_id, prefix: "player-")
  identify(NPCBlueprint, by: :blueprint_id, prefix: "npc-blueprint-")
  identify(Region, by: :region_id, prefix: "region-")
  identify(Quest, by: :quest_id, prefix: "quest-")

  # Feature 014 — Object Blueprints. Command dispatches added per user
  # story (Create in US1, Edit in US5). The identify/2 entry stays here
  # to register the aggregate with the router so the projector / event
  # store can resolve the stream prefix.
  identify(ObjectBlueprint, by: :blueprint_id, prefix: "object-blueprint-")

  # Phase 3 (US5) + Phase 6 (US3): room commands routed to Room.
  # Feature 014 US2: SpawnObjectFromBlueprint also routed to Room (the
  # destination Room aggregate owns object presence, exactly like
  # PlaceObject).
  dispatch(
    [
      CreateRoom,
      AddExit,
      PlaceObject,
      TakeObject,
      DropObject,
      SpawnObjectFromBlueprint,
      SpawnObjectFreeform,
      EditObject
    ],
    to: Room
  )

  # Phase 4 (US1) + Phase 5 (US2): player lifecycle + movement routed to Player.
  # Feature 012: per-player room discovery also routed to Player.
  dispatch([SpawnPlayer, MovePlayer, RecordRoomDiscovery], to: Player)

  # Feature 008: NPC blueprint authoring + cloning
  dispatch([CreateNPCBlueprint, SpawnNPCClone], to: NPCBlueprint)

  # Feature 012: region authoring
  dispatch([CreateRegion], to: Region)

  # Feature 013: quest lifecycle (accept + finalize). Each quest instance
  # is its own aggregate identified by quest_id.
  dispatch([AcceptQuest, FinalizeQuest], to: Quest)

  # Feature 014 US1 + US5: Object Blueprint authoring + editing.
  dispatch([CreateObjectBlueprint, EditObjectBlueprint], to: ObjectBlueprint)
end
