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
            behaviors: [],
            # Feature 012 — Maps
            region_id: nil,
            map_visible: true,
            elevation: 0,
            map_x: nil,
            map_y: nil

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
        behaviors: behaviors,
        region_id: region_id,
        map_visible: map_visible,
        elevation: elevation,
        map_x: map_x,
        map_y: map_y
      }) do
    %RoomCreated{
      room_id: id,
      name: name,
      description: description,
      behaviors: behaviors,
      region_id: region_id,
      map_visible: map_visible,
      elevation: elevation,
      map_x: map_x,
      map_y: map_y
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
        fixed: fixed,
        behaviors: behaviors,
        quest_player_id: quest_player_id,
        quest_instance_id: quest_instance_id
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
        fixed: fixed,
        behaviors: behaviors || [],
        # Feature 013 — both nil for non-quest placements (the seed
        # path); both set for quest-scoped spawns. Carried straight
        # through; aggregate state doesn't track them.
        quest_player_id: quest_player_id,
        quest_instance_id: quest_instance_id
      }
    end
  end

  # --- SpawnObjectFromBlueprint (feature 014 US2) -------------------------

  def execute(%__MODULE__{id: nil}, %AgenticRealms.World.Commands.SpawnObjectFromBlueprint{}),
    do: {:error, :room_not_found}

  def execute(
        %__MODULE__{id: rid, object_ids: ids},
        %AgenticRealms.World.Commands.SpawnObjectFromBlueprint{
          room_id: rid,
          object_id: oid,
          name: name,
          short_description: short,
          long_description: long,
          fixed: fixed
        }
      ) do
    if MapSet.member?(ids, oid) do
      {:error, :object_already_in_room}
    else
      %AgenticRealms.World.Events.ObjectSpawned{
        object_id: oid,
        room_id: rid,
        name: name,
        short_description: short,
        long_description: long,
        fixed: fixed
      }
    end
  end

  # --- SpawnObjectFreeform (feature 014 US3) ------------------------------
  # Identical event shape to SpawnObjectFromBlueprint — the freeform
  # path produces the same `ObjectSpawned` event so the projector and
  # the UI broadcaster don't have to discriminate.

  def execute(%__MODULE__{id: nil}, %AgenticRealms.World.Commands.SpawnObjectFreeform{}),
    do: {:error, :room_not_found}

  def execute(
        %__MODULE__{id: rid, object_ids: ids},
        %AgenticRealms.World.Commands.SpawnObjectFreeform{
          room_id: rid,
          object_id: oid,
          name: name,
          short_description: short,
          long_description: long,
          fixed: fixed
        }
      ) do
    if MapSet.member?(ids, oid) do
      {:error, :object_already_in_room}
    else
      %AgenticRealms.World.Events.ObjectSpawned{
        object_id: oid,
        room_id: rid,
        name: name,
        short_description: short,
        long_description: long,
        fixed: fixed
      }
    end
  end

  # --- EditObject (feature 014 US5) ---------------------------------------
  # The Room aggregate confirms the object is currently in this room
  # (via its `object_ids` MapSet) before emitting `ObjectEdited`. The
  # projector applies the diff to `world_objects` in place.

  def execute(%__MODULE__{id: nil}, %AgenticRealms.World.Commands.EditObject{}),
    do: {:error, :room_not_found}

  def execute(
        %__MODULE__{id: rid, object_ids: ids},
        %AgenticRealms.World.Commands.EditObject{
          room_id: rid,
          object_id: oid,
          fields_changed: fields_changed
        }
      )
      when is_map(fields_changed) do
    cond do
      not MapSet.member?(ids, oid) ->
        {:error, :object_not_in_room}

      map_size(fields_changed) == 0 ->
        :ok

      true ->
        %AgenticRealms.World.Events.ObjectEdited{
          object_id: oid,
          room_id: rid,
          fields_changed: fields_changed
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

  def apply(
        %__MODULE__{} = state,
        %RoomCreated{
          room_id: id,
          name: name,
          description: description,
          behaviors: behaviors
        } = event
      ) do
    %__MODULE__{
      state
      | id: id,
        name: name,
        description: description,
        behaviors: behaviors,
        region_id: Map.get(event, :region_id),
        map_visible: Map.get(event, :map_visible, true),
        elevation: Map.get(event, :elevation, 0),
        map_x: Map.get(event, :map_x),
        map_y: Map.get(event, :map_y)
    }
  end

  def apply(%__MODULE__{exits: exits} = state, %ExitAdded{
        direction: direction,
        target_room_id: target
      }) do
    %__MODULE__{state | exits: Map.put(exits, direction, target)}
  end

  def apply(%__MODULE__{object_ids: ids} = state, %AgenticRealms.World.Events.ObjectSpawned{
        object_id: oid
      }) do
    %__MODULE__{state | object_ids: MapSet.put(ids, oid)}
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

  # Feature 014 US5 — in-place Object edit. No effect on the Room
  # aggregate's tracked object_ids; the projector applies the field
  # diff to `world_objects` directly.
  def apply(%__MODULE__{} = state, %AgenticRealms.World.Events.ObjectEdited{}), do: state
end

# Snapshot serialization for the Room aggregate (issue #6).
# `object_ids` is a `MapSet`, which has no Jason.Encoder impl; we render it
# as a list on serialize and rebuild the MapSet on deserialize via
# `Commanded.Serialization.JsonDecoder`. The custom EventStore serializer
# (`AgenticRealms.EventStore.Serializer`) and the Commanded JsonSerializer
# both invoke that protocol after `struct/2`.
defimpl Jason.Encoder, for: AgenticRealms.World.Room do
  def encode(%AgenticRealms.World.Room{} = room, opts) do
    room
    |> Map.from_struct()
    |> Map.update!(:object_ids, &MapSet.to_list/1)
    |> Jason.Encode.map(opts)
  end
end

defimpl Commanded.Serialization.JsonDecoder, for: AgenticRealms.World.Room do
  # The Jason :atoms!/:atoms key strategy atomizes ALL keys in the decoded
  # JSON — including the keys of `exits`, which the aggregate populates
  # with the string direction from each `ExitAdded` event (e.g. "north").
  # Without re-stringifying, `Map.has_key?(exits, "north")` in execute
  # clauses would miss after a snapshot rehydrate.
  def decode(%AgenticRealms.World.Room{object_ids: ids, exits: exits} = state) do
    %{
      state
      | object_ids: to_mapset(ids),
        exits: stringify_keys(exits)
    }
  end

  defp to_mapset(ids) when is_list(ids), do: MapSet.new(ids)
  defp to_mapset(%MapSet{} = ids), do: ids

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
