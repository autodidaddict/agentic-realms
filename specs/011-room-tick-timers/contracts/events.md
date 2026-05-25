# Contract: Object event/command extensions + new UIEvent

## Persisted event/command extensions (backward-compatible)

### `AgenticRealms.World.Commands.PlaceObject`

```elixir
# Add `behaviors: []` to the defstruct. NOT in @enforce_keys (backward-compat).
defstruct [
  # ... existing fields ...
  behaviors: []
]
```

Same shape as feature 009's room/NPC behavior-list addition. Validator runs on dispatch.

### `AgenticRealms.World.Events.ObjectPlacedInRoom`

```elixir
# Add `behaviors: []` to the defstruct.
@derive Jason.Encoder
defstruct [
  # ... existing fields ...
  behaviors: [],
  version: 1
]
```

Old payloads without the key deserialize with `behaviors = []`.

### Projector

```elixir
def handle(%ObjectPlacedInRoom{
  # ... existing fields ...
  behaviors: behaviors
}, _meta) do
  Repo.insert!(%Object{
    # ... existing fields ...
    behaviors: behaviors || []
  })
  :ok
end
```

### `AgenticRealms.Application.__behavior_atoms__/0`

```elixir
# Before:
@_behavior_atoms [:trigger, :actions, :type, :text]

# After:
@_behavior_atoms [:trigger, :actions, :type, :text, :interval_ms]
```

Pre-declares the atom for JSON-key atomization. Without this, deserializing an `ObjectPlacedInRoom` with a tick behavior would crash the EventStore notification publisher (per the feature-009 lessons).

## Backward-compatibility test

A replay test (`world_projector_object_replay_test.exs`) constructs an old-shape `ObjectPlacedInRoom` event (no `behaviors` key) and asserts the projector inserts an Object with `behaviors = []`. Mirrors feature 009/010 patterns.

---

## UIEvent extensions (backward-compatible)

### `AgenticRealms.World.UIEvents.RoomPlayerArrived`

```elixir
# Before:
@enforce_keys [:room_id, :actor_id, :actor_username]
defstruct [:room_id, :actor_id, :actor_username, :from_direction]

# After:
@enforce_keys [:room_id, :actor_id, :actor_username]
defstruct [:room_id, :actor_id, :actor_username, :from_direction, carried_object_ids: []]
```

### `AgenticRealms.World.UIEvents.RoomPlayerLeft`

```elixir
# Before:
@enforce_keys [:room_id, :actor_id, :actor_username, :to_direction]
defstruct [:room_id, :actor_id, :actor_username, :to_direction]

# After:
@enforce_keys [:room_id, :actor_id, :actor_username, :to_direction]
defstruct [:room_id, :actor_id, :actor_username, :to_direction, carried_object_ids: []]
```

### Emission sites

Wherever these events are broadcast (in `GameLive.handle_move/3` and any spawn/despawn path), the emission code populates `carried_object_ids` from `Queries.list_inventory(actor_id) |> Enum.map(& &1.id)`. This is one read query per move — bounded by inventory size.

Existing consumers ignore the field; the scheduler is the only consumer that reads it.

---

## New UIEvent

### `AgenticRealms.World.UIEvents.RoomNPCLeft`

```elixir
defmodule AgenticRealms.World.UIEvents.RoomNPCLeft do
  @moduledoc """
  Transient NPC-departure event (feature 011). Mirror of RoomNPCArrived
  from feature 007. Broadcast on `room:<source>` when an NPC clone is
  despawned or removed.

  Used by `RoomTicks.Scheduler` to drop the NPC's tick behaviors from
  its in-scope set. Emission path is forward-compatible: the event is
  defined now; production emission lands whenever NPC despawn ships
  as a feature.
  """

  @enforce_keys [:room_id, :npc_id, :npc_name]
  defstruct [:room_id, :npc_id, :npc_name]
end
```

This is the only NEW event struct in this feature. No emission path is added in production code yet (NPCs don't despawn in the project today). A synthesized event in tests exercises the scheduler's response.

---

## Test surface

`ObjectPlacedInRoomReplayTest` (new):

- An old-shape event (no `behaviors`) projects with `behaviors = []`.
- A new-shape event (`behaviors: [%{...}]`) projects with the supplied list.

`UIEventsTest` extensions:

- `RoomPlayerArrived` accepts the new `carried_object_ids` field; default is `[]`; not in `@enforce_keys`.
- `RoomPlayerLeft` accepts the new `carried_object_ids` field; default is `[]`; not in `@enforce_keys`.
- `RoomNPCLeft` requires `room_id`, `npc_id`, `npc_name`; struct-creation without them raises.

`GameLiveMovementTest` (existing) — confirm that `chat`-adjacent flows do not crash on the new field; no semantic change expected.
