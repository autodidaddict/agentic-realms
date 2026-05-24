# Contract: Domain Events

Two new event types + a legacy event preserved for replay.

## New event: `NPCBlueprintCreated`

```elixir
defmodule AgenticRealms.World.Events.NPCBlueprintCreated do
  @derive Jason.Encoder
  @enforce_keys [:blueprint_id, :name, :short_description, :long_description]
  defstruct [:blueprint_id, :name, :short_description, :long_description, version: 1]
end
```

### Producer

`NPCBlueprint` aggregate on a successful `CreateNPCBlueprint` command.

### Consumers

1. **`WorldProjector`** — upsert into `npc_blueprints` table (`on_conflict: :nothing` on `:id`).
2. None other in this feature. (A future wizard tab might subscribe for audit purposes; not in scope.)

### Replay semantics

Idempotent. `on_conflict: :nothing` makes re-projection a no-op.

## New event: `NPCClonedFromBlueprint`

```elixir
defmodule AgenticRealms.World.Events.NPCClonedFromBlueprint do
  @derive Jason.Encoder
  @enforce_keys [
    :blueprint_id,
    :clone_id,
    :room_id,
    :serial,
    :name,
    :short_description,
    :long_description
  ]
  defstruct [
    :blueprint_id,
    :clone_id,
    :room_id,
    :serial,
    :name,
    :short_description,
    :long_description,
    version: 1
  ]
end
```

### Producer

`NPCBlueprint` aggregate on a successful `SpawnNPCClone` command. The aggregate's CURRENT `name`, `short_description`, `long_description`, and `next_serial` are stamped into the event payload at this moment — this is the **full-copy materialization point** (I-3 / FR-007). After event application, `next_serial` increments; `clone_ids` gains the new id.

### Field semantics

| Field                | Type        | Notes                                                            |
|----------------------|-------------|------------------------------------------------------------------|
| `blueprint_id`       | `string`    | Lineage reference. Stable.                                       |
| `clone_id`           | `binary_id` | Stable identity of the clone. Becomes `npc_clones.id`.           |
| `room_id`            | `binary_id` | Destination room.                                                |
| `serial`             | `integer`   | Assigned at emit time. Per-blueprint monotonic.                  |
| `name`               | `string`    | Copied from blueprint state. Case preserved.                     |
| `short_description`  | `string`    | Copied from blueprint state.                                     |
| `long_description`   | `string`    | Copied from blueprint state.                                     |
| `version`            | `integer`   | Schema version. Starts at `1`.                                   |

### Consumers

1. **`WorldProjector`** — insert into `npc_clones` table. Inserts use the event's full payload; the blueprint table is NOT consulted at projection time.
2. **`UIEventBroadcaster`** — broadcast `RoomNPCArrived{room_id, npc_id: clone_id, npc_name: name}` on `room:<room_id>` topic. Same UI event used by the legacy path so GameLive's handler is one clause covering both.

### Replay semantics

`npc_clones` insert is by PK (`clone_id`). On replay, `on_conflict: :nothing` makes it a no-op. The UI event broadcast on replay is fine (no subscribers during a cold-start replay; even if there were, the GameLive handler is idempotent at the log-entry level).

## Legacy event: `NPCSpawnedInRoom` (feature 007)

Unchanged on disk:

```elixir
defmodule AgenticRealms.World.Events.NPCSpawnedInRoom do
  @derive Jason.Encoder
  @enforce_keys [:room_id, :npc_id, :name, :short_description, :long_description]
  defstruct [:room_id, :npc_id, :name, :short_description, :long_description, version: 1]
end
```

**Status**: No code path in this feature emits new instances of this event. The struct definition stays in the codebase (we don't delete event types from event-sourced systems — the event-store serializer must still deserialize them on replay).

### Producer

None going forward. Historical events emitted by feature 007's `Room` aggregate remain in the event store.

### Consumers (in this feature)

1. **`Room` aggregate apply/2** — a vestigial no-op clause for rehydration safety:

```elixir
# Replay compatibility for feature 007 events. NPC state is no longer tracked
# on the Room aggregate (feature 008 moved it to a per-blueprint aggregate).
def apply(%__MODULE__{} = state, %NPCSpawnedInRoom{}), do: state
```

2. **`WorldProjector`** — the synthetic-blueprint path. Derive a synthetic blueprint id from the event's payload, upsert into `npc_blueprints` with `is_synthetic: true`, then insert into `npc_clones`:

```elixir
def handle(
      %NPCSpawnedInRoom{
        room_id: rid,
        npc_id: nid,
        name: name,
        short_description: short,
        long_description: long
      },
      _meta
    ) do
  bp_id = SyntheticBlueprintId.derive(name, short, long)

  Repo.insert!(
    %NPCBlueprint{
      id: bp_id,
      name: name,
      short_description: short,
      long_description: long,
      is_synthetic: true
    },
    on_conflict: :nothing,
    conflict_target: :id
  )

  serial = next_serial_for_blueprint(bp_id)

  Repo.insert!(
    %NPCClone{
      id: nid,
      blueprint_id: bp_id,
      serial: serial,
      name: name,
      short_description: short,
      long_description: long,
      room_id: rid
    },
    on_conflict: :nothing,
    conflict_target: :id
  )

  :ok
end

defp next_serial_for_blueprint(bp_id) do
  Repo.aggregate(
    from(c in NPCClone, where: c.blueprint_id == ^bp_id),
    :max,
    :serial
  )
  |> case do
    nil -> 1
    n -> n + 1
  end
end
```

3. **`UIEventBroadcaster`** — keep the feature 007 handler that broadcasts `RoomNPCArrived` on `NPCSpawnedInRoom`. No change.

### Replay semantics

- Legacy events project deterministically: same payload always produces the same synthetic blueprint id (UUID5).
- The `npc_clones` insert is idempotent by `clone_id` (PK) with `on_conflict: :nothing`.
- The `next_serial_for_blueprint/1` query is run per-event; the projector is single-threaded so the MAX-then-insert pattern is safe under projector ordering.

## Non-events

This feature does NOT introduce:
- `NPCBlueprintDeleted` — out of scope (FR-016 refuses deletion while clones exist; full deletion semantic is deferred).
- `NPCBlueprintUpdated` — out of scope (FR-005a, blueprints are immutable through the command path in this feature).
- `NPCCloneRemoved` / `NPCCloneDespawned` — out of scope (FR-017, inherited from feature 007).
- Any per-clone-override events — out of scope (FR-014).

The above are explicitly future-feature concerns.

## Event-store evolution

- **Backward compatibility**: legacy `NPCSpawnedInRoom` events project through the synthetic path. Pre-feature-008 worlds replay cleanly.
- **Forward compatibility**: future events that add fields (e.g., `NPCBlueprintCreated v2`) bump `version` and add new fields; the projector handles `v1` and `v2` clauses side-by-side.
- **No event mutation**: the legacy event struct is NOT modified. Adding `blueprint_id` retroactively to legacy events would violate event-source purity.
