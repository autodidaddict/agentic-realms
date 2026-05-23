defmodule AgenticRealms.World.Room do
  @moduledoc """
  Room aggregate. Owns a room's display info (name + description), its exit
  set, the set of objects currently in the room, and the set of NPCs currently
  in the room. Per-room commands (`TakeObject`, `DropObject`, `SpawnNPC`) are
  serialized by Commanded on this aggregate, which is what gives us the
  FR-011 concurrent-take race resolution for free and what enforces per-room
  NPC name uniqueness in-flight (feature 007 FR-001a).

  Occupancy is NOT tracked on this aggregate — `PlayerStateProjector` owns
  that question via the `player_state` read model. This keeps movement
  non-transactional across rooms (per Q2 clarification + research D2).

  Object FIXED-ness is checked at the pre-dispatch layer (`World.Commands.take`)
  via the read model, NOT in the aggregate. The aggregate only owns the
  contested resource — "is this object currently here?" — which is what
  needs serialization. Fixed-ness is a static property; reading it from the
  read model is always definitive.

  See `specs/003-persisted-world/data-model.md` §1.1 and
  `specs/007-static-npcs/data-model.md` §2.
  """

  defstruct id: nil,
            name: nil,
            description: nil,
            exits: %{},
            object_ids: MapSet.new(),
            npc_ids: MapSet.new(),
            npc_names_lower: MapSet.new()

  alias AgenticRealms.World.Commands.{
    CreateRoom,
    AddExit,
    PlaceObject,
    TakeObject,
    DropObject,
    SpawnNPC
  }

  alias AgenticRealms.World.Events.{
    RoomCreated,
    ExitAdded,
    ObjectPlacedInRoom,
    ObjectTakenFromRoom,
    ObjectDroppedInRoom,
    NPCSpawnedInRoom
  }

  # --- CreateRoom ---------------------------------------------------------

  def execute(%__MODULE__{id: nil}, %CreateRoom{
        room_id: id,
        name: name,
        description: description
      }) do
    %RoomCreated{room_id: id, name: name, description: description}
  end

  def execute(%__MODULE__{}, %CreateRoom{}), do: {:error, :room_already_exists}

  # --- AddExit ------------------------------------------------------------

  def execute(%__MODULE__{id: nil}, %AddExit{}), do: {:error, :room_not_found}

  def execute(%__MODULE__{id: id, exits: exits}, %AddExit{
        room_id: id,
        direction: direction,
        target_room_id: target
      })
      when not is_nil(target) do
    if Map.has_key?(exits, direction) do
      {:error, :exit_already_exists}
    else
      %ExitAdded{room_id: id, direction: direction, target_room_id: target}
    end
  end

  # --- PlaceObject --------------------------------------------------------

  def execute(%__MODULE__{id: nil}, %PlaceObject{}), do: {:error, :room_not_found}

  def execute(%__MODULE__{id: rid, object_ids: ids}, %PlaceObject{
        room_id: rid,
        object_id: oid,
        name: name,
        short_description: short,
        long_description: long,
        fixed: fixed
      }) do
    if MapSet.member?(ids, oid) do
      {:error, :object_already_in_room}
    else
      %ObjectPlacedInRoom{
        room_id: rid,
        object_id: oid,
        name: name,
        short_description: short,
        long_description: long,
        fixed: fixed
      }
    end
  end

  # --- TakeObject ---------------------------------------------------------
  # Race-resolution point: when two players concurrently dispatch TakeObject
  # for the same room+object, Commanded serializes them on this aggregate.
  # The first removes the object_id from object_ids; the second arrives,
  # finds it gone, and returns {:error, :object_not_in_room} — which the
  # LiveView renders as the FR-011 message (Q1 clarification).

  def execute(%__MODULE__{id: nil}, %TakeObject{}), do: {:error, :room_not_found}

  def execute(%__MODULE__{id: rid, object_ids: ids}, %TakeObject{
        room_id: rid,
        player_id: pid,
        object_id: oid
      }) do
    if MapSet.member?(ids, oid) do
      %ObjectTakenFromRoom{room_id: rid, player_id: pid, object_id: oid}
    else
      {:error, :object_not_in_room}
    end
  end

  # --- DropObject ---------------------------------------------------------
  # The aggregate only checks that this object isn't already in the room
  # (which would indicate a serious read-model/aggregate divergence — the
  # pre-dispatch layer already verified the player carries this object).

  def execute(%__MODULE__{id: nil}, %DropObject{}), do: {:error, :room_not_found}

  def execute(%__MODULE__{id: rid, object_ids: ids}, %DropObject{
        room_id: rid,
        player_id: pid,
        object_id: oid
      }) do
    if MapSet.member?(ids, oid) do
      {:error, :object_already_in_room}
    else
      %ObjectDroppedInRoom{room_id: rid, player_id: pid, object_id: oid}
    end
  end

  # --- SpawnNPC -----------------------------------------------------------
  # Enforces per-room NPC name uniqueness (FR-001a) in-flight. The DB unique
  # index on (room_id, LOWER(name)) is defense in depth.

  def execute(%__MODULE__{id: nil}, %SpawnNPC{}), do: {:error, :room_not_found}

  def execute(
        %__MODULE__{id: rid, npc_ids: nids, npc_names_lower: names},
        %SpawnNPC{
          room_id: rid,
          npc_id: nid,
          name: name,
          short_description: short,
          long_description: long
        }
      ) do
    cond do
      short in [nil, ""] ->
        {:error, :short_description_required}

      long in [nil, ""] ->
        {:error, :long_description_required}

      MapSet.member?(nids, nid) ->
        {:error, :npc_already_in_room}

      MapSet.member?(names, String.downcase(name)) ->
        {:error, :npc_name_taken_in_room}

      true ->
        %NPCSpawnedInRoom{
          room_id: rid,
          npc_id: nid,
          name: name,
          short_description: short,
          long_description: long
        }
    end
  end

  # --- apply/2 ------------------------------------------------------------

  def apply(%__MODULE__{} = state, %RoomCreated{
        room_id: id,
        name: name,
        description: description
      }) do
    %__MODULE__{state | id: id, name: name, description: description}
  end

  def apply(%__MODULE__{exits: exits} = state, %ExitAdded{
        direction: direction,
        target_room_id: target
      }) do
    %__MODULE__{state | exits: Map.put(exits, direction, target)}
  end

  def apply(%__MODULE__{object_ids: ids} = state, %ObjectPlacedInRoom{object_id: oid}) do
    %__MODULE__{state | object_ids: MapSet.put(ids, oid)}
  end

  def apply(%__MODULE__{object_ids: ids} = state, %ObjectTakenFromRoom{object_id: oid}) do
    %__MODULE__{state | object_ids: MapSet.delete(ids, oid)}
  end

  def apply(%__MODULE__{object_ids: ids} = state, %ObjectDroppedInRoom{object_id: oid}) do
    %__MODULE__{state | object_ids: MapSet.put(ids, oid)}
  end

  def apply(
        %__MODULE__{npc_ids: nids, npc_names_lower: names} = state,
        %NPCSpawnedInRoom{npc_id: nid, name: name}
      ) do
    %__MODULE__{
      state
      | npc_ids: MapSet.put(nids, nid),
        npc_names_lower: MapSet.put(names, String.downcase(name))
    }
  end
end
