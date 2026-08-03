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
    ProvisionTransientRegion,
    OpenTransientEntryExit,
    DestroyRegion,
    RecordRoomDiscovery,
    AwardXp,
    CreateCharacter,
    AcceptQuest,
    FinalizeQuest,
    CloneEntity,
    MoveEntity,
    EditEntity,
    RemoveEntity
  }

  identify(Room, by: :room_id, prefix: "room-")
  identify(Player, by: :player_id, prefix: "player-")
  identify(Region, by: :region_id, prefix: "region-")
  identify(Quest, by: :quest_id, prefix: "quest-")

  identify(Blueprint, by: :blueprint_id, prefix: "blueprint-")

  identify(Entity, by: :entity_id, prefix: "entity-")

  dispatch([CreateRoom, AddExit], to: Room)

  dispatch([SpawnPlayer, MovePlayer, RecordRoomDiscovery, AwardXp, CreateCharacter], to: Player)

  dispatch(
    [CreateRegion, ProvisionTransientRegion, OpenTransientEntryExit, DestroyRegion],
    to: Region,
    lifespan: AgenticRealms.World.RegionLifespan
  )

  dispatch([AcceptQuest, FinalizeQuest], to: Quest)

  dispatch([CreateBlueprint, EditBlueprint], to: Blueprint)

  dispatch([CloneEntity, MoveEntity, EditEntity, RemoveEntity],
    to: Entity,
    lifespan: AgenticRealms.World.EntityLifespan
  )
end
