# Contract: `AgenticRealms.World.Ticks.Scope` (pure scope computation)

Pure module (DB-bound on `compute/1`; pure list operations otherwise) that computes the in-scope tick-behavior set for a room, plus incremental update helpers used by the scheduler.

## Functions

### `compute/1`

```elixir
@spec compute(room_id :: String.t()) :: [behavior_entry()]
```

Returns the full in-scope tick-behavior set for `room_id`, sorted per FR-008a (target_kind → target_serial/id → behavior_index).

**Implementation** (queries the read-side):

1. **Room behaviors**: `Repo.get(Room, room_id).behaviors |> filter_tick |> map(&room_entry/1)`
2. **NPC behaviors**: for each clone in `Queries.list_npc_clones_in_room_with_behaviors(room_id)`: `clone.behaviors |> filter_tick |> map(&npc_entry(clone, &1))`
3. **In-room object behaviors**: for each object in `Queries.list_objects_in_room(room_id)` (new helper, promoted from private): `object.behaviors |> filter_tick |> map(&object_entry(object, &1))`
4. **Carried-object behaviors**: for each object held by ANY player whose `current_room_id == room_id` AND who is online: `object.behaviors |> filter_tick |> map(&object_entry(object, &1))`. (NPCs don't currently carry inventory in the project; this is a no-op pending that feature.)
5. Sort combined list per FR-008a.

Each entry has the shape from `data-model.md` §2.1.

### `add_npc/2`, `remove_npc/2`

```elixir
@spec add_npc([behavior_entry()], npc_id :: String.t()) :: [behavior_entry()]
@spec remove_npc([behavior_entry()], npc_id :: String.t()) :: [behavior_entry()]
```

Add/remove the entries for a single NPC clone. `add_npc/2` queries the read-side for the clone's `behaviors`; `remove_npc/2` is a pure list filter on `target_kind == :npc and target_id == npc_id`.

The returned list is re-sorted per FR-008a.

### `add_carried_object/3`, `remove_carried_object/3`

```elixir
@spec add_carried_object([behavior_entry()], player_id :: integer(), object_id :: String.t()) :: [behavior_entry()]
@spec remove_carried_object([behavior_entry()], player_id :: integer(), object_id :: String.t()) :: [behavior_entry()]
```

Add/remove entries for a single object carried by a player. `add_carried_object/3` queries the read-side for the object's behaviors.

The `player_id` parameter is currently used only for clarity/logging — the scope set itself doesn't store carrier info because all carried-object behaviors in scope of a room dispatch identically regardless of who's carrying.

### `add_in_room_object/2`, `remove_in_room_object/2`

```elixir
@spec add_in_room_object([behavior_entry()], object_id :: String.t()) :: [behavior_entry()]
@spec remove_in_room_object([behavior_entry()], object_id :: String.t()) :: [behavior_entry()]
```

For objects placed in or removed from the room directly (not via inventory). Used by `RoomObjectTaken` (when an object leaves the room floor) and `RoomObjectDropped` (when an object lands on the room floor) — though typically these don't change scope because the object was already in scope via the player's inventory before the drop. The helpers exist for completeness and for the rare case of objects appearing/disappearing without a carrier transition (e.g., spawned/destroyed by future actions).

## Behavior contracts

- All functions are deterministic given the same DB state.
- `compute/1` performs at most 4 queries (one per source).
- Incremental helpers (`add_*`, `remove_*`) perform 0 or 1 DB query (the `add_*` variants fetch the target's behaviors; `remove_*` is pure list filtering).
- Empty list (`[]`) is returned when a target has no tick behaviors — never `nil`.

## Test surface

`ScopeTest`:

- `compute/1` for a room with one tick behavior + one tick NPC + one tick room-object + one tick carried-object returns 4 entries in FR-008a order.
- `compute/1` for an empty room (no behaviors) returns `[]`.
- `compute/1` correctly EXCLUDES NPCs whose `current_room_id` is a different room.
- `compute/1` correctly INCLUDES objects held by a player in the room AND EXCLUDES objects held by a player in a different room.
- `compute/1` correctly EXCLUDES non-tick triggers (filters to `trigger == "tick"`).
- `add_npc/2` adds the NPC's tick entries to the scope set; the returned list is re-sorted.
- `remove_npc/2` filters out all entries for that NPC, regardless of behavior_index.
- `add_carried_object/3` / `remove_carried_object/3` work symmetrically.
- `add_in_room_object/2` / `remove_in_room_object/2` work symmetrically.
- Multiple invocations of `add_npc/2` for the same npc_id do NOT duplicate entries (caller-side dedup is acceptable; pure-list semantics tolerate it but the scheduler avoids the dup by calling remove-then-add).
