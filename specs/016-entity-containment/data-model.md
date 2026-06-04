# Phase 1 Data Model: Entity Lifecycle — Clone & Move with Typed Containment

**Feature**: 016-entity-containment | **Date**: 2026-06-04 | **Depends on**: [research.md](./research.md)

Repo-root-relative paths. "New" = introduced here; "altered"/"removed" describe retrofit changes to
shipped code (specs 007/008/013/014). The model mirrors the existing `Player` aggregate (which owns
its own location) generalized to all movable entities.

---

## 1. Value type: `ContainerRef`

`lib/agenticrealms/world/container_ref.ex` (new) — a plain value, not an aggregate.

```
%ContainerRef{type: :void | :room | :player | :npc, id: term() | nil}
```
- `:void` ⇒ `id: nil`. All other types carry the target's id.
- Helpers: `void/0`, `room(id)`, `player(id)`, `npc(id)`, `valid_type?/1`, `to_map/1` + `from_map/1`
  (event serialization). Used in commands, events, and the projector.

---

## 2. Aggregate: `Entity` (new)

`lib/agenticrealms/world/entity.ex` — stream `entity-<entity_id>`; the consistency boundary for an
entity's existence and location.

**Struct**: `defstruct id: nil, kind: nil, container: %ContainerRef{type: :void, id: nil}`

**`execute/2`**:
| Command | Guard | Emits / returns |
|---|---|---|
| `CloneEntity` | `id == nil` | `EntityCloned{entity_id, kind, fields}` (container implicitly void). If already created → `{:error, :already_exists}` |
| `MoveEntity` | created; `to` valid type | no-op if `to == container` → `:ok` (no event, FR-009); else `EntityMoved{entity_id, from: container, to, cause}`. Stale caller-supplied `from` ignored — current `container` is authoritative (FR-005). Unknown type → `{:error, :unsupported_container}` |
| `EditEntity` | created | no-op diff → `:ok`; else `EntityEdited{entity_id, fields_changed}` |

**`apply/2`**: `EntityCloned` → set `kind`, `container = void`. `EntityMoved` → set `container = to`.
`EntityEdited` → no aggregate state change (fields live in the read model).

> The aggregate validates *type* and *self-consistency*; it cannot verify the destination *exists*
> (cross-aggregate) — that is the wrapper's job (§6, R7).

---

## 3. Commands (`lib/agenticrealms/world/commands/`)

| Command | Routed to | Fields | Status |
|---|---|---|---|
| `CloneEntity` | Entity | `entity_id, kind, fields` (map of frozen read-model fields) | **new** |
| `MoveEntity` | Entity | `entity_id, from (ContainerRef), to (ContainerRef), cause` | **new** |
| `EditEntity` | Entity | `entity_id, fields_changed` | **new** (absorbs `EditObject`) |
| `PlaceObject` | — | — | **removed** (→ clone_into) |
| `SpawnObjectFromBlueprint` | — | — | **removed** (wrapper → clone_into) |
| `SpawnObjectFreeform` | — | — | **removed** (wrapper → clone_into) |
| `TakeObject` | — | — | **removed** (wrapper → move_entity) |
| `DropObject` | — | — | **removed** (wrapper → move_entity) |
| `EditObject` | — | — | **removed** (→ EditEntity) |
| `SpawnNPCClone` | — | — | **removed** (wrapper → clone_into) |

`cause` ∈ `:spawned | :placed | :taken | :dropped | :relocated` (R3). `fields` is kind-shaped: for
`:object` — `name, short_description, long_description, fixed, behaviors, quest_player_id,
quest_instance_id`; for `:npc` — `name, short_description, long_description, lore, behaviors`
(015 later adds `fixed, toolsets`).

---

## 4. Events (`lib/agenticrealms/world/events/`)

| Event | Payload | Status |
|---|---|---|
| `EntityCloned` | `entity_id, kind, fields` | **new** |
| `EntityMoved` | `entity_id, from (map), to (map), cause` | **new** |
| `EntityEdited` | `entity_id, fields_changed` | **new** |
| `ObjectPlacedInRoom`, `ObjectSpawned`, `ObjectTakenFromRoom`, `ObjectDroppedInRoom`, `ObjectEdited` | — | **removed** |
| `NPCClonedFromBlueprint`, `NPCSpawnedInRoom` | — | **removed** |

(Destroyable log: removed events are not replayed; a reseed produces clean `EntityCloned`/`EntityMoved`
streams. FR-013 — the NPC lineage fold-in is realized by these removals.)

---

## 5. Read-model schema changes (Ecto migrations)

### 5.1 `world_objects` — altered (`lib/agenticrealms/world/schemas/object.ex`)

| Column | Change |
|---|---|
| `room_id` | **removed** |
| `player_id` | **removed** |
| `exactly_one_location` CHECK (XOR) | **removed** |
| `container_type` | **new** — string NOT NULL; CHECK ∈ `{void,room,player,npc}` |
| `container_id` | **new** — string NULL; CHECK `(container_type='void') = (container_id IS NULL)` |
| `name, short_description, long_description, fixed, behaviors` | unchanged |
| `quest_player_id, quest_instance_id` | unchanged (visibility scope; independent of container) |

Replace the `(room_id, lower(name))` uniqueness with a **partial unique index**
`(container_id, lower(name)) WHERE container_type = 'room'` (feature-007 rule, FR-012b).

### 5.2 `npc_clones` — altered (`lib/agenticrealms/world/schemas/npc_clone.ex`)

| Column | Change |
|---|---|
| `blueprint_id` (FK), `serial` | **removed** — lineage dropped (FR-013) |
| `room_id` | **removed** (replaced by container columns) |
| `container_type`, `container_id` | **new** — same shape as world_objects (room-only in practice) |
| `name, short_description, long_description, behaviors, lore` | unchanged |
| `(room_id, lower(name))` unique index | **replaced** by the same partial unique room index |

(The `npc_clones`/`NPCClone` name is retained per spec-015 R9; lineage *semantics* are gone.)

### 5.3 No new container tables

Rooms, players, NPCs already have identities/tables. A container is just a typed reference; the void
is `container_type='void', container_id=NULL`. NPC-inventory rows would be `container_type='npc'` —
**not written by any path this milestone** (R8, dormant).

---

## 6. Thin world service (wrappers in `lib/agenticrealms/world/commands.ex`)

| Wrapper | Behavior |
|---|---|
| `clone_entity(kind, fields)` | mint `entity_id`; dispatch `CloneEntity`; ⇒ `{:ok, entity_id}` |
| `move_entity(entity_id, to, cause)` | validate destination exists (read model) + room name-collision pre-check (R7); dispatch `MoveEntity` |
| `clone_into(kind, fields, to, cause)` | `clone_entity` then `move_entity`; on move failure entity is left in void (FR-003) |
| `spawn_object_from_blueprint/3` | reads blueprint payload → `clone_into(:object, fields, room, :spawned)` |
| `spawn_object_freeform/3` | `clone_into(:object, fields, room, :spawned)` |
| `place_object` (seed/quest) | `clone_into(:object, fields+quest scope, room, :placed)` |
| `take/2` | resolve object in room → `move_entity(id, player, :taken)` |
| `drop/2` | resolve object in inventory → `move_entity(id, room, :dropped)` |
| `spawn_npc_clone/3` | reads blueprint payload → `clone_into(:npc, fields, room, :spawned)` |
| quest consume/cleanup | `move_entity(id, ContainerRef.void(), :relocated)` (removal-via-void, R5) |
| quest reward | `clone_into(:object, reward, player, :spawned)` |

Authorization (`ensure_wizard/1`) stays on the wizard-only wrappers exactly as today.

---

## 7. Projector: `EntityProjector` (new) (`lib/agenticrealms/world/projections/entity_projector.ex`)

| Event | Action |
|---|---|
| `EntityCloned` | insert row into `world_objects` (kind `:object`) or `npc_clones` (kind `:npc`) with the frozen `fields` and `container_type='void'`, `container_id=NULL`. `on_conflict: :nothing` |
| `EntityMoved` | update the row's `container_type`/`container_id` to `to`. Idempotent (absolute assignment) |
| `EntityEdited` | apply sparse `fields_changed` to the row |

`:strong` consistency; supervised in `application.ex` `commanded_children/0` and `data_case.ex`
`setup_commanded/0`. `WorldProjector` loses its object/NPC placement/take/drop/clone handlers (now
owns rooms, exits, regions, quest orchestration only).

---

## 8. UI witnessing (`lib/agenticrealms/world/ui_event_broadcaster.ex`)

Replace the per-event object/NPC handlers with **one** `EntityMoved` handler that maps
`(kind, cause, from.type → to.type)` to the existing UI structs (full table in research §R3):
`RoomObjectArrived`, `RoomObjectTaken`, `RoomObjectDropped`, `RoomNPCArrived`, and inventory/quest
side-broadcasts (`PlayerInventoryChanged`, `PlayerQuestProgress`) preserved on take/drop. `EntityCloned`
and moves into the void broadcast nothing. No new "X picks up Y"-style announcement is introduced
(FR-014). `:eventual` consistency unchanged.

---

## 9. Router (`lib/agenticrealms/world/router.ex`)

- **Add** `identify(Entity, by: :entity_id, prefix: "entity-")`.
- **Add** dispatch `[CloneEntity, MoveEntity, EditEntity] → Entity`.
- **Remove** from the `Room` dispatch list: `PlaceObject, TakeObject, DropObject,
  SpawnObjectFromBlueprint, SpawnObjectFreeform, EditObject`. (Keep `CreateRoom, AddExit`.)
- **Remove** `SpawnNPCClone` from the `NPCBlueprint` dispatch list (keep `CreateNPCBlueprint`).

---

## 10. Aggregate retrofit (existing aggregates)

- **`Room`** (`room.ex`): remove the `object_ids` MapSet field and every object placement/take/drop/
  spawn/edit `execute`+`apply` clause (and the vestigial `NPCSpawnedInRoom` apply). Keep room
  creation, exits, regions, map fields, behaviors.
- **`NPCBlueprint`** (`npc_blueprint.ex`): remove `SpawnNPCClone` execute + `NPCClonedFromBlueprint`
  apply, and the `next_serial` / `clone_ids` struct fields. Keep `CreateNPCBlueprint`.

---

## 11. Read queries (`lib/agenticrealms/world/queries.ex`)

- `list_objects_in_room/1` → `WHERE container_type='room' AND container_id=$room` (was `room_id`).
- `list_inventory/1` / `resolve_object_in_inventory/2` → `WHERE container_type='player' AND
  container_id=$player` (was `player_id`).
- `list_npcs_in_room/1` / `resolve_npc_in_room/2` → `WHERE container_type='room' AND
  container_id=$room`.
- Quest visibility filters on `quest_player_id`/`quest_instance_id` unchanged.

---

## 12. Invariants (consolidated)

- An entity is in **exactly one** container at all times (void counts) — guaranteed by single-valued
  aggregate `container` + the read-row CHECK (FR-004).
- Moves of one entity **serialize** on its aggregate stream (FR-005).
- A move into a real container fires that container type's existing **witness convention**; into the
  void fires nothing (FR-007/FR-008/FR-014).
- A no-op move changes nothing and fires nothing (FR-009).
- Destination must exist and (for rooms) not collide on name — wrapper pre-check + partial unique
  index (FR-010, FR-012b).
- Exactly **one** spawn/relocation model exists post-retrofit; zero room-specific spawn events remain
  (FR-012, SC-003).
