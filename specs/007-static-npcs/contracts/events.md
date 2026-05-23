# Contract: `NPCSpawnedInRoom` Domain Event

## Event struct

`AgenticRealms.World.Events.NPCSpawnedInRoom`

```elixir
defmodule AgenticRealms.World.Events.NPCSpawnedInRoom do
  @derive Jason.Encoder
  @enforce_keys [
    :room_id,
    :npc_id,
    :name,
    :short_description,
    :long_description
  ]
  defstruct [
    :room_id,
    :npc_id,
    :name,
    :short_description,
    :long_description,
    version: 1
  ]
end
```

## Field semantics

| Field               | Type        | Notes                                                                 |
|---------------------|-------------|-----------------------------------------------------------------------|
| `room_id`           | `binary_id` | Destination room. FK target for the read-model insert.                |
| `npc_id`            | `binary_id` | Stable identity. Becomes `world_npcs.id`.                             |
| `name`              | `string`    | Display name. Case preserved.                                         |
| `short_description` | `string`    | Used in `world_npcs.short_description` and the room view.             |
| `long_description`  | `string`    | Used in `world_npcs.long_description`. Surfaced on examine.           |
| `version`           | `integer`   | Schema version. Starts at `1`. Future migrations bump and branch.     |

## Producers

Only the `Room` aggregate's `SpawnNPC` command handler. No other code path in this feature emits this event.

## Consumers

1. **`WorldProjector`** — inserts/upserts a row into `world_npcs`.
2. **`UIEventBroadcaster`** — translates into a `RoomNPCArrived` UI event and broadcasts on the room topic.

Both consumers are configured with `consistency: :strong` (matches the existing posture for room-mutating events). Callers that dispatch `SpawnNPC` with `consistency: :strong` are guaranteed:
- The `world_npcs` row exists when `dispatch/1,2` returns.
- The `RoomNPCArrived` PubSub broadcast has been published when `dispatch/1,2` returns (i.e., all currently-subscribed `GameLive` processes have already enqueued the message).

This matches the seed's expectations — `Seed.run/0` dispatches `SpawnNPC` synchronously and proceeds, but in this feature there are no live sessions to race with at seed time. The `consistency: :strong` posture is required so the integration test (which simulates a live session present during a `SpawnNPC` dispatch) does not flake.

## Forward compatibility

Adding new event types is backward-compatible. Existing event streams (`PlayerSpawned`, `PlayerMoved`, `RoomCreated`, etc.) continue to project as before. Replaying the entire event store after this feature ships will:
- Replay all existing events into their existing projections (unchanged).
- Replay any `NPCSpawnedInRoom` events into `world_npcs` (newly inserted on first replay).

If a future feature introduces NPC removal, that feature adds a new event type (e.g., `NPCRemovedFromRoom`) and a new `Room` aggregate command handler — without modifying `NPCSpawnedInRoom`. The `version: 1` field is the slot used if the spawn event itself ever needs schema evolution.

## Non-events

This feature does NOT define:
- `NPCDespawned` / `NPCRemovedFromRoom`
- `NPCMoved`
- `NPCSpoke` / `NPCEmoted`
- Any combat- or dialogue-related event

Per FR-017 / FR-018 / FR-019 / FR-017b, these are out of scope. Future features may introduce them; this feature explicitly does not.
