defmodule AgenticRealms.World.Room do
  @moduledoc """
  Room aggregate. Owns a room's display info (name + description), its exit
  set, and the set of objects currently in the room. Per-room commands
  (`TakeObject`, `DropObject`) are serialized by Commanded on this aggregate.

  Occupancy is NOT tracked on this aggregate — `PlayerStateProjector` owns
  that question via the `player_state` read model.

  Object FIXED-ness is checked at the pre-dispatch layer via the read
  model, NOT in the aggregate.

  **Feature 008 note**: NPC state (`npc_ids`, `npc_names_lower`) was
  removed from this aggregate when the blueprint/clone split moved NPC
  spawning to `World.NPCBlueprint`. Per-room display name uniqueness for
  clones is enforced at the read-model layer (DB unique index + pre-dispatch
  check in `World.Commands.spawn_npc_clone/3`). The `apply/2` clause for
  `NPCSpawnedInRoom` is preserved as a vestigial no-op for aggregate
  rehydration compatibility — feature 007 emitted those events from this
  aggregate, and they remain in the event store.

  See `specs/003-persisted-world/data-model.md` §1.1 and
  `specs/008-npc-blueprints/data-model.md` §3.
  """

  defstruct id: nil,
            name: nil,
            description: nil,
            exits: %{},
            object_ids: MapSet.new(),
            behaviors: []

  alias AgenticRealms.World.Commands.{
    CreateRoom,
    AddExit,
    PlaceObject,
    TakeObject,
    DropObject
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
        description: description,
        behaviors: behaviors
      }) do
    %RoomCreated{
      room_id: id,
      name: name,
      description: description,
      behaviors: behaviors
    }
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

  # --- apply/2 ------------------------------------------------------------

  def apply(%__MODULE__{} = state, %RoomCreated{
        room_id: id,
        name: name,
        description: description,
        behaviors: behaviors
      }) do
    %__MODULE__{
      state
      | id: id,
        name: name,
        description: description,
        behaviors: behaviors
    }
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

  # Feature 008: vestigial no-op for legacy `NPCSpawnedInRoom` events. The
  # Room aggregate no longer tracks NPC state; per-room name uniqueness is
  # enforced at the read-model layer (DB unique index + pre-dispatch check).
  # This clause exists only so rehydrating a Room aggregate from its event
  # stream doesn't crash on historical events emitted by feature 007.
  def apply(%__MODULE__{} = state, %NPCSpawnedInRoom{}), do: state
end
