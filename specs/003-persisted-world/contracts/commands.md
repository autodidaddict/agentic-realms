# Contract — Commands & Domain Events

**Date**: 2026-05-18
**Branch**: `003-persisted-world`
**Companion docs**: [`../plan.md`](../plan.md), [`../data-model.md`](../data-model.md), [`ui_events.md`](ui_events.md)

This contract defines every command that crosses the `AgenticRealms.World` write boundary and every domain event that may be appended to the event store. Command and event modules live under `AgenticRealms.World.Commands.*` and `AgenticRealms.World.Events.*` respectively.

Each command is documented as: **payload**, **aggregate** it dispatches to, **preconditions** (which `execute/2` must check), **success → events**, and **error returns**. Error atoms are stable wire shapes: the LiveView (`GameLive.handle_event/3`) maps them to FR-aligned log entries.

---

## C1. `CreateRoom`

**Payload**:

```elixir
%CreateRoom{room_id: uuid, name: String.t(), description: String.t()}
```

**Aggregate**: `World.Room` (creates a new instance).

**Preconditions**: the aggregate is uninitialized (`state.id == nil`).

**Success → events**: `[%RoomCreated{room_id, name, description}]`

**Errors**: `{:error, :room_already_exists}` if the aggregate has already been initialized.

**Caller**: `World.Seed` only (and, in future features, the wizard authoring tools).

---

## C2. `AddExit`

**Payload**:

```elixir
%AddExit{room_id: uuid, direction: :north|:south|:east|:west|:up|:down, target_room_id: uuid}
```

**Aggregate**: `World.Room` (the source room).

**Preconditions**:

- `state.id != nil` (room exists).
- `Map.has_key?(state.exits, direction) == false` (no duplicate exit).
- `target_room_id` is a non-nil UUID. (Existence of the target room is **not** enforced at the aggregate level — it is the seed's responsibility to call `CreateRoom` for the target first. Justification: cross-aggregate referential integrity would require a process manager; the read model's foreign-key constraint catches violations at projection time, and the seed test in `quickstart.md` covers it.)

**Success → events**: `[%ExitAdded{room_id, direction, target_room_id}]`

**Errors**: `{:error, :room_not_found}`, `{:error, :exit_already_exists}`.

**Caller**: `World.Seed`.

---

## C3. `PlaceObject`

**Payload**:

```elixir
%PlaceObject{
  room_id: uuid,
  object_id: uuid,
  name: String.t(),
  short_description: String.t(),
  long_description: String.t(),
  fixed: boolean()
}
```

**Aggregate**: `World.Room`.

**Preconditions**:

- `state.id != nil`.
- `object_id ∉ state.object_ids`.

**Success → events**: `[%ObjectPlacedInRoom{room_id, object_id, name, short_description, long_description, fixed}]`

**Errors**: `{:error, :room_not_found}`, `{:error, :object_already_in_room}`.

**Caller**: `World.Seed` (this feature). In future features, wizard authoring + commit flows.

---

## C4. `TakeObject`

**Payload**:

```elixir
%TakeObject{room_id: uuid, player_id: integer(), object_id: uuid}
```

**Aggregate**: `World.Room`.

**Preconditions**:

- `state.id != nil`.
- `object_id ∈ state.object_ids` — if not, return `{:error, :object_not_in_room}` (the race-loser path for FR-011 / clarification Q1).
- `state.known_objects[object_id].fixed == false` — if true, return `{:error, :object_is_fixed}` (FR-010).

**Success → events**: `[%ObjectTakenFromRoom{room_id, player_id, object_id}]`

**Errors**: `{:error, :room_not_found}`, `{:error, :object_not_in_room}`, `{:error, :object_is_fixed}`.

**Caller**: `World.Commands.take/3` (via `GameLive.handle_event("submit_command", ...)`).

**Note on race resolution**: when two `TakeObject` commands for the same `(room_id, object_id)` are dispatched concurrently from two different players, Commanded serializes them on the Room aggregate. The first removes the object from `object_ids`; the second's `execute/2` finds the object absent and returns `:object_not_in_room`. This is the entire race-handling mechanism.

---

## C5. `DropObject`

**Payload**:

```elixir
%DropObject{
  room_id: uuid,
  player_id: integer(),
  object_id: uuid
}
```

**Aggregate**: `World.Room` (the room being dropped into = the player's current room).

**Preconditions**:

- `state.id != nil`.
- `object_id ∉ state.object_ids` (sanity check; if the object were already in the room, the player can't be carrying it).
- The pre-dispatch layer (`World.Commands.drop/3`) verifies that the player actually carries the object (`world_objects.player_id == player_id`); if not, returns `{:error, :not_in_inventory}` without dispatching (FR-013).

**Success → events**: `[%ObjectDroppedInRoom{room_id, player_id, object_id}]`

**Errors**: `{:error, :room_not_found}`, `{:error, :object_already_in_room}`, `{:error, :not_in_inventory}` (caught pre-dispatch).

**Caller**: `World.Commands.drop/3`.

---

## C6. `SpawnPlayer`

**Payload**:

```elixir
%SpawnPlayer{player_id: integer(), starting_room_id: uuid}
```

**Aggregate**: `World.Player` (creates a new instance for this player).

**Preconditions**:

- `state.current_room_id == nil` (the player has never spawned). The pre-dispatch layer (`World.Commands.spawn/2`) short-circuits via the `player_state` read model: if a row exists with non-null `current_room_id`, no command is dispatched.

**Success → events**: `[%PlayerSpawned{player_id, room_id: starting_room_id}]`

**Errors**: `{:error, :already_spawned}`.

**Caller**: `GameLive.mount/3` on the first time a player reaches the Play view (FR-003), and `World.Recovery.respawn_if_room_missing/1` for FR-022 cases (described in C7's recovery note).

---

## C7. `MovePlayer`

**Payload**:

```elixir
%MovePlayer{
  player_id: integer(),
  from_room_id: uuid,
  to_room_id: uuid,
  direction: :north|:south|:east|:west|:up|:down
}
```

**Aggregate**: `World.Player`.

**Preconditions**:

- `state.current_room_id == from_room_id`.
- `to_room_id != nil`.

(`to_room_id` is resolved by the pre-dispatch layer: `World.Commands.move/2` reads `world_exits WHERE source_room_id = current_room_id AND direction = direction`; if no row, returns `{:error, :no_exit_in_direction}` without dispatching — this is the FR-007 path.)

**Success → events**: `[%PlayerMoved{player_id, from_room_id, to_room_id, direction}]`

**Errors**: `{:error, :stale_from_room}` (aggregate state disagrees with caller — extremely rare, indicates a bug), `{:error, :no_exit_in_direction}` (pre-dispatch).

**Caller**: `World.Commands.move/2`.

**Recovery note (FR-022)**: when `PlayerMoved` references a `to_room_id` that no longer exists, the `PlayerStateProjector` sets `current_room_id = NULL` rather than raising. On the next entry to the Play view, `GameLive.mount/3` detects `current_room_id == nil`, dispatches `SpawnPlayer` into the starting room, and appends the FR-022 "previous location no longer reachable" system message to the player's session log.

---

## Domain event payloads (summary)

Detailed shape definitions live in [`../data-model.md` §2](../data-model.md). The complete list:

| Event module | Fields | Stream |
|---|---|---|
| `AgenticRealms.World.Events.RoomCreated` | `room_id, name, description` | `"room-<uuid>"` |
| `AgenticRealms.World.Events.ExitAdded` | `room_id, direction, target_room_id` | `"room-<uuid>"` (source room) |
| `AgenticRealms.World.Events.ObjectPlacedInRoom` | `room_id, object_id, name, short_description, long_description, fixed` | `"room-<uuid>"` |
| `AgenticRealms.World.Events.ObjectTakenFromRoom` | `room_id, player_id, object_id` | `"room-<uuid>"` |
| `AgenticRealms.World.Events.ObjectDroppedInRoom` | `room_id, player_id, object_id` | `"room-<uuid>"` |
| `AgenticRealms.World.Events.PlayerSpawned` | `player_id, room_id` | `"player-<integer>"` |
| `AgenticRealms.World.Events.PlayerMoved` | `player_id, from_room_id, to_room_id, direction` | `"player-<integer>"` |

Every event carries an implicit `version: 1` field reserved for upcasting; no upcasters are in scope for this feature.

---

## Command → log-entry mapping (LiveView side)

For reference — these are the strings GameLive renders into the narrative log from command results. Exact wording is owned by `GameLive`; this table is the FR ↔ atom contract:

| Outcome | FR | Log entry kind | Text (illustrative) |
|---|---|---|---|
| `:ok` for `TakeObject` | FR-009 | `:system` | `"You take the brass lantern."` |
| `{:error, :object_not_in_room}` | FR-011 | `:system` | `"You don't see that here."` |
| `{:error, :object_is_fixed}` | FR-010 | `:system` | `"You can't take the reading lectern."` |
| `{:error, :ambiguous}` | FR-024 | `:system` | `"Which one do you mean?"` |
| `:ok` for `DropObject` | FR-012 | `:system` | `"You drop the leather-bound journal."` |
| `{:error, :not_in_inventory}` | FR-013 | `:system` | `"You aren't carrying that."` |
| `:ok` for `MovePlayer` | FR-008 | `:room` (arrival) | room view of destination, rendered by `RoomView` struct |
| `{:error, :no_exit_in_direction}` | FR-007 | `:system` | `"You can't go that way."` |
| Parser `{:unknown, raw}` | FR-018 | `:system` | `"I don't understand \"#{raw}\"."` |
| Parser `{:empty}` | FR-019 | (no entry) | — |
| `inventory` (non-empty) | FR-014 | `:system` | multi-line listing of `World.Queries.list_inventory/1` |
| `inventory` (empty) | FR-014 | `:system` | `"You aren't carrying anything."` |
| `look` | FR-005 | `:room` | room view of `World.Queries.look_room/1` |
| FR-022 recovery | FR-022 | `:system` | `"Your previous location is no longer reachable. You find yourself back at the start."` |
