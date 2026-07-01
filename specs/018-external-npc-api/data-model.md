# Phase 1 Data Model — External NPC Brains (Game-Side)

This feature adds **one command + one event** to the write side, **no new
read-model tables or columns** (removal deletes existing rows), one new **read
query**, and several **transient in-memory shapes** (contract snapshots +
reconciler state). Existing entities referenced: `NPCClone` (`npc_clones`),
`Exit` (`world_exits`), `Object` (`world_objects`), `PlayerState`, `Room`.

---

## 1. Write side (event-sourced)

### Command: `AgenticRealms.World.Commands.RemoveEntity`

| Field | Type | Notes |
|---|---|---|
| `entity_id` | string (UUID) | The object/NPC entity aggregate id. `@enforce_keys`. |

Routed to the `Entity` aggregate (`identify(Entity, by: :entity_id, prefix:
"entity-")`). Facade: `Commands.remove_entity/1` and `Commands.remove_npc/1`,
dispatched `consistency: :strong`, returning `:ok | {:error, :not_found}`.

### Event: `AgenticRealms.World.Events.EntityRemoved`

| Field | Type | Notes |
|---|---|---|
| `entity_id` | string (UUID) | Removed entity. |
| `kind` | `:npc` \| `:object` | Copied from aggregate state (originally from `EntityCloned`). Drives projector + witness + lifecycle. |
| `from` | container map | The entity's current container at removal (`%{type, id}`), e.g. `%{type: :room, id: <room>}` — lets the witness broadcast `RoomNPCLeft` to the right room. `nil`/void when unplaced. |
| `version` | integer | `version: 1`, `@derive Jason.Encoder` (matches `EntityMoved`/`EntityCloned`). |

### Aggregate changes: `AgenticRealms.World.Entity`

- `execute(%Entity{id: nil}, %RemoveEntity{})` → `{:error, :not_found}` (never cloned).
- `execute(%Entity{removed?: true}, %RemoveEntity{})` → `{:error, :not_found}` (already removed; keeps `RemoveEntity` idempotent at the aggregate).
- `execute(%Entity{...}, %RemoveEntity{entity_id: id})` → `%EntityRemoved{entity_id: id, kind: state.kind, from: state.container}`.
- `apply(state, %EntityRemoved{})` → mark `removed?: true` (and/or clear container).
- **Lifespan**: `after_event(%EntityRemoved{})` → `:stop` (evict the aggregate; the stream persists per event-log policy).

**State transitions (Entity):**
```
(absent) --CloneEntity--> Cloned(void) --MoveEntity(:spawned)--> Placed(room)
Placed/void --MoveEntity(:relocated|:taken|:dropped)--> (new container)
any existing --RemoveEntity--> Removed (terminal; aggregate stops)
```

### Projector change (entity/world projector)

`handle(%EntityRemoved{entity_id: id, kind: :npc}, _)` → delete `npc_clones` row
`id` (idempotent: delete-by-pk, no error if absent). `kind: :object` → delete
`world_objects` row. Must be **replay-safe** (Principle II): re-handling a
redelivered `EntityRemoved` is a no-op.

> **Invariant**: after `EntityRemoved{kind: :npc}` is projected, no `npc_clones`
> row remains for that id — this is what stops the reconciler from resurrecting
> the mind (see §4).

---

## 2. Read model (existing — impact only)

No new tables/columns. Reads used by the contract:

| Read | Source | Shape returned to contract |
|---|---|---|
| Identity | `Repo.get(NPCClone, id)` | `name, short_description, long_description, lore` (+ `entity_id`) |
| Room of NPC | `NPCClone.room_id` | `room_id` or `nil` (void) |
| Exits (**new** `list_global_exits/1`) | `world_exits` where `source_room_id = room AND visible_to_user_id IS NULL` | `[%{direction, target_room_id}]` |
| NPC occupants | `list_npcs_in_room/1` | `[%{id, name}]` tagged `kind: "npc"` |
| Object occupants | `list_objects_in_room/1` | `[%{id, name}]` tagged `kind: "object"` (all objects; trusted view) |
| Player occupants | existing room-players query | `[%{id→string, username→name}]` tagged `kind: "player"` |

`EntityRemoved` projector deletes rows here; no other read-model write is added.

---

## 3. Contract snapshots (transient, wire shapes)

Conform to the shared schema (`agentic-realms-npc` feature 001). See
`contracts/npc-service-api.md` for full JSON + status codes.

**Identity snapshot**
```
{ entity_id, name, short_description, long_description, lore }
```

**Surroundings snapshot**
```
{ entity_id,
  room_id: <string|null>,
  exits:     [ { direction, to_room_id } ],
  occupants: [ { id, kind: "npc"|"player"|"object", name } ] }
```
Void/removed NPC → `{ entity_id, room_id: null, exits: [], occupants: [] }`.

**Move request / result**
```
request:  { direction, expected_room_id }
result:   { result: "ok", from_room_id, to_room_id }   // 200
        | { result: "conflict" }                        // 409  (:container_conflict)
        | { result: "no_such_exit" }                    // 422  (direction not a global exit / :unsupported_container)
        // 404 unknown entity ; 401 bad/missing token
```

Direction ∈ `north south east west northeast northwest southeast southwest up down rift`.

---

## 4. Lifecycle & reconciler shapes (transient, in-memory)

**Mind identity (agreed with `agentic-realms-npc`)**
| Value | Value |
|---|---|
| workflow type | `NpcWorkflow` |
| workflow id | `npc-<entity_id>` |
| task queue | `npc-minds` |
| input | `{ "entity_id": "<uuid>" }` (Temporal Payload, base64) |
| conflict policy | `WORKFLOW_ID_CONFLICT_POLICY_USE_EXISTING` |

**Reconciler**: no persisted state. Per sweep it computes over transient sets:
- `live  = MapSet(ids from npc_clones)`
- `running = MapSet(ids from TemporalClient.list_running_npc_ids/0)`
- `Reconciler.diff(live, running) => {to_start: live − running, to_terminate: running − live}` (pure, unit-tested)
- then `start_workflow` each `to_start`, `terminate_workflow` each `to_terminate` (both idempotent/tolerant).

The reconciler holds only its timer ref/config in GenServer state; it is
crash-safe because it rebuilds `live`/`running` from source every sweep
(Principle VI — restartable, no state to lose).

---

## 5. Validation rules (from requirements)

- **Move**: `direction` must be a current **global** exit of `expected_room_id`
  (else `no_such_exit`); the NPC must still be in `expected_room_id` (aggregate
  `expected_from` guard → `:container_conflict` = `conflict`); retry-idempotent
  (guard makes a stale retry a `conflict`, never a double move). FR-015..021.
- **Reads**: pure, no world change; unknown id → `404`; void/removed → empty
  surroundings snapshot (not an error). FR-006..013.
- **Auth**: every route requires a valid bearer token before any read/write;
  missing vs. wrong not disclosed. FR-030, FR-027, FR-033.
- **Lifecycle**: start on `EntityCloned{:npc}` for every NPC; terminate on
  `EntityRemoved{:npc}` and in the purge path; both keyed to `npc-<entity_id>`;
  uniqueness/tolerance enforced by Temporal, not the game. FR-024..028.
- **Reconcile**: converge live↔running each interval. FR-029a, SC-013.
