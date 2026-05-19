# Contract — UI Events (Phoenix.PubSub)

**Date**: 2026-05-18
**Branch**: `003-persisted-world`
**Companion docs**: [`../plan.md`](../plan.md), [`commands.md`](commands.md)

This contract defines the second tier of the two-tier event vocabulary (per Q2 clarification and the user's planning input): transient `UIEvent` messages broadcast via `Phoenix.PubSub` for live presentation to subscribed LiveViews. UI events are derived from domain events by a single `Commanded.Event.Handler` — `AgenticRealms.World.UIEventBroadcaster` — and are never persisted.

UI event modules live under `AgenticRealms.World.UIEvents.*`.

---

## Topics

Two topic families on the existing PubSub instance `AgenticRealms.PubSub`:

| Topic pattern | Subscribed by | Carries |
|---|---|---|
| `"room:<room_uuid>"` | Every `GameLive` whose current player's `current_room_id` is this room. | `RoomObjectTaken`, `RoomObjectDropped`, `RoomPlayerArrived`, `RoomPlayerLeft` |
| `"player:<player_id>"` | Every `GameLive` mounted for this player (one per concurrent session — Q5 multi-tab clarification). | `PlayerCurrentRoomChanged`, `PlayerInventoryChanged` |

Topic subscription lifecycle:

- On `GameLive.mount/3`: subscribe to `"player:<id>"` and `"room:<current_room_id>"`.
- On receiving `PlayerCurrentRoomChanged{from, to}`: unsubscribe from `"room:<from>"`, subscribe to `"room:<to>"`. (This is how the player's *other* tabs follow the active tab into the next room.)

---

## UI event payloads

### U1. `RoomObjectTaken`

```elixir
%RoomObjectTaken{
  room_id: uuid,
  actor_id: integer(),          # the player who took the object
  actor_username: String.t(),    # cached at broadcast time for log rendering convenience
  object_id: uuid,
  object_name: String.t()
}
```

**Broadcast on**: `"room:<room_id>"`.
**Derived from**: `%ObjectTakenFromRoom{}` domain event. Resolution of `actor_username` and `object_name` happens in the broadcaster via the read model.
**Backs FR**: FR-025.
**Subscriber rendering rule**: if `actor_id == socket.assigns.current_player.id` → discard (FR-029). Otherwise append a `:system` log entry: `"<actor_username> takes the <object_name>."` and remove the object from the cached room contents (so a re-render of an existing `:room` entry would not show it). Also broadcast a parallel `PlayerInventoryChanged{player_id: actor_id}` is NOT needed — the actor's own tabs get notified via U6 below.

---

### U2. `RoomObjectDropped`

```elixir
%RoomObjectDropped{
  room_id: uuid,
  actor_id: integer(),
  actor_username: String.t(),
  object_id: uuid,
  object_name: String.t()
}
```

**Broadcast on**: `"room:<room_id>"`.
**Derived from**: `%ObjectDroppedInRoom{}`.
**Backs FR**: FR-026.
**Subscriber rendering rule**: if `actor_id == current_player.id` → discard. Otherwise append `"<actor_username> drops the <object_name>."` and add the object to the cached room contents.

---

### U3. `RoomPlayerArrived`

```elixir
%RoomPlayerArrived{
  room_id: uuid,              # the destination room (the topic id)
  actor_id: integer(),
  actor_username: String.t(),
  from_direction: atom() | nil  # the direction the actor came FROM (opposite of the movement direction); nil for first spawn / FR-022 respawn
}
```

**Broadcast on**: `"room:<room_id>"` (destination).
**Derived from**: `%PlayerMoved{}` (broadcast as part of the move) AND `%PlayerSpawned{}` (spawn case, with `from_direction: nil`).
**Backs FR**: FR-027.
**Subscriber rendering rule**: if `actor_id == current_player.id` → discard. Otherwise append either `"<actor_username> arrives from the <from_direction>."` (when `from_direction != nil`) or `"<actor_username> arrives."` (when nil). Add the actor to the cached occupant list.

**Direction-from derivation**: if the originating event is `%PlayerMoved{direction: :north}`, then `from_direction = :south` (the arriving player came from the south of the destination). The broadcaster owns this inversion via a `World.Direction.opposite/1` helper.

---

### U4. `RoomPlayerLeft`

```elixir
%RoomPlayerLeft{
  room_id: uuid,              # the origin room (the topic id)
  actor_id: integer(),
  actor_username: String.t(),
  to_direction: atom()        # the direction the actor headed
}
```

**Broadcast on**: `"room:<room_id>"` (origin).
**Derived from**: `%PlayerMoved{}` (broadcast as part of the move).
**Backs FR**: FR-028.
**Subscriber rendering rule**: if `actor_id == current_player.id` → discard. Otherwise append `"<actor_username> leaves to the <to_direction>."` and remove the actor from the cached occupant list.

---

### U5. `PlayerCurrentRoomChanged`

```elixir
%PlayerCurrentRoomChanged{
  player_id: integer(),
  from_room_id: uuid | nil,    # nil when transitioning from "no current room" (first spawn or FR-022 recovery)
  to_room_id: uuid
}
```

**Broadcast on**: `"player:<player_id>"`.
**Derived from**: `%PlayerSpawned{}` AND `%PlayerMoved{}`.
**Backs FR**: FR-032, FR-033 (multi-session state sync).
**Subscriber rendering rule**: every one of the player's mounted LiveViews receives this. The originating tab discards (it already updated its socket assigns inline after the command returned). Other tabs:

1. Unsubscribe from `"room:<from_room_id>"` (if non-nil).
2. Subscribe to `"room:<to_room_id>"`.
3. Update their `current_room_id` socket assign.
4. Append a `:room` log entry rendered from `World.Queries.look_room/1` (so the other tab sees the new room just as if its user had typed `look`).

**Origin-tab discard rule**: the broadcaster has no concept of "which session originated the command." Tabs distinguish themselves by tracking their last-issued command in a transient socket assign `:awaiting_room_change_ack`. On receipt of a `PlayerCurrentRoomChanged` matching their pending move, they clear the flag and discard. Other tabs see no pending flag and process the event normally. (Implementation alternative: include the originating `socket.id` in the UI event payload and discard on match — equivalent.)

---

### U6. `PlayerInventoryChanged`

```elixir
%PlayerInventoryChanged{
  player_id: integer(),
  change: :added | :removed,
  object_id: uuid,
  object_name: String.t(),
  object_short_description: String.t()
}
```

**Broadcast on**: `"player:<player_id>"`.
**Derived from**: `%ObjectTakenFromRoom{}` and `%ObjectDroppedInRoom{}`.
**Backs FR**: FR-015 (HUD card stays in sync with `inventory` command), FR-032, FR-033.
**Subscriber rendering rule**: update the cached inventory list in the socket assigns so the Inventory HUD card (and the next `inventory` command output) reflects the new state. Do NOT append a log entry — confirmation/witness entries are handled by U1/U2 and by the actor-side branch of `GameLive.handle_event/3`.

---

## Broadcasting algorithm (`UIEventBroadcaster`)

The broadcaster is a `Commanded.Event.Handler` with `consistency: :eventual` (we accept that the broadcaster may be a few hundred milliseconds behind the originating dispatch under load).

```text
on %ObjectTakenFromRoom{room_id, player_id, object_id} →
  fetch object_name from world_objects
  fetch actor_username from players
  PubSub.broadcast("room:#{room_id}", %RoomObjectTaken{…})
  PubSub.broadcast("player:#{player_id}", %PlayerInventoryChanged{change: :added, …})

on %ObjectDroppedInRoom{room_id, player_id, object_id} →
  symmetric to above, but %RoomObjectDropped and %PlayerInventoryChanged{change: :removed}

on %PlayerSpawned{player_id, room_id} →
  fetch actor_username
  PubSub.broadcast("room:#{room_id}", %RoomPlayerArrived{room_id, actor_id: player_id, from_direction: nil, …})
  PubSub.broadcast("player:#{player_id}", %PlayerCurrentRoomChanged{from_room_id: nil, to_room_id: room_id, …})

on %PlayerMoved{player_id, from_room_id, to_room_id, direction} →
  fetch actor_username
  PubSub.broadcast("room:#{from_room_id}", %RoomPlayerLeft{room_id: from_room_id, actor_id: player_id, to_direction: direction, …})
  PubSub.broadcast("room:#{to_room_id}", %RoomPlayerArrived{room_id: to_room_id, actor_id: player_id, from_direction: opposite(direction), …})
  PubSub.broadcast("player:#{player_id}", %PlayerCurrentRoomChanged{from_room_id, to_room_id, …})
```

`RoomCreated`, `ExitAdded`, and `ObjectPlacedInRoom` produce no UI events in this feature — those are seed-time only and there are no subscribers to notify. Future features (live world editing) may add UI events here.

---

## Delivery semantics

- **At-least-once**: `Commanded.Event.Handler` provides at-least-once delivery; the broadcaster's PubSub call is fire-and-forget. A subscriber that misses a UI event (because it crashed, or because it had not yet subscribed when the event was broadcast) reconciles via the next `look` query.
- **Ordering**: within a single domain stream (e.g., one room's stream), Commanded guarantees in-order delivery to the handler. Across streams (e.g., two rooms involved in a move), there is no ordering guarantee — but the two broadcasts derived from one `PlayerMoved` come from the same handler invocation, so they are dispatched on the same OTP message scheduling tick. PubSub fan-out itself is unordered across subscribers; for two subscribers in *different* rooms this is fine, and within the same room there is at most one of {`RoomPlayerArrived`, `RoomPlayerLeft`} per `PlayerMoved` so there is nothing to order.
- **Best-effort**: no acknowledgment, no retries from the broadcaster. The next `look` is the recovery mechanism — exactly as the Q2 clarification's "next look reflects the resulting room contents and occupant list consistently with that entry" allows.
