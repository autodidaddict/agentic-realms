# Implementation Plan: Entity Lifecycle — Clone & Move with Typed Containment

**Branch**: `016-entity-containment` | **Date**: 2026-06-04 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/016-entity-containment/spec.md`

## Summary

Replace the world's two divergent, room-bound spawn paths and the ad-hoc two-FK-XOR object location
model with **one uniform entity lifecycle**, modeled on the existing `Player` aggregate (which
already owns its own location):

- A generic **`Entity` aggregate** (`entity-<id>`) owns each movable entity's existence, `kind`
  (`:object|:npc`), and current **container**. It handles `CloneEntity` (born in the void),
  `MoveEntity` (relocate; current container authoritative), and `EditEntity`.
- A typed **`ContainerRef` `(type, id)`** — `void | room | player | npc` — replaces
  `world_objects.room_id`/`player_id` + the `exactly_one_location` XOR, admitting the void and NPC
  possession. `npc_clones` is generalized the same way and **loses its blueprint lineage** (this
  subsumes the feature-008 fold-in).
- A thin **world-service** wrapper layer provides `clone_entity`, `move_entity`, and `clone_into`,
  and re-expresses every existing call site — wizard spawn, seed/quest placement, `take`/`drop`,
  quest reward/consumption, NPC spawn — on top of them. **Full retrofit now**: exactly one
  spawn/relocation model exists at the end (SC-003).
- A dedicated **`EntityProjector`** owns all `world_objects`/`npc_clones` row writes from
  `EntityCloned`/`EntityMoved`/`EntityEdited`. The **`UIEventBroadcaster`** maps `EntityMoved`
  `(kind, cause, from→to)` to the *existing* witness structs so observable behavior is unchanged
  (FR-014): wizard spawn announces arrival, seed/quest placement stays silent, `take`/`drop` keep
  their current room broadcasts, moves into the void are silent.

Wired this milestone: **void + room + player-inventory**. **NPC-inventory** is a valid container in
the model but **dormant** (no read model/UI). Player movement stays on the `Player` aggregate (not
folded in). All design decisions and their rationale are in [research.md](./research.md); the
concrete shapes are in [data-model.md](./data-model.md) and [contracts/](./contracts/).

This is a **foundational substrate** and a **prerequisite of spec 015 (NPC blueprints)**, which
rebases its "spawn an NPC" onto `clone_into(room)` and inherits the lineage fold-in from here.

## Technical Context

**Language/Version**: Elixir 1.20 on OTP 26+ (current project baseline; consistent with feature 014).

**Primary Dependencies (existing, reused — no new dependencies)**:
- `commanded ~> 1.4` + `commanded_eventstore_adapter ~> 1.4` — new `Entity` aggregate + commands/
  events; router `identify`/dispatch changes; retrofit of `Room`/`NPCBlueprint` aggregates.
- `ecto_sql ~> 3.11` + `postgrex` — migrations altering `world_objects` and `npc_clones` (container
  columns; drop XOR + NPC lineage; partial unique room-name index).
- `phoenix_pubsub` — the existing room/player topics carry the same witness broadcasts, now driven by
  one `EntityMoved` handler in `UIEventBroadcaster`.
- `jason ~> 1.4` — event payload serialization (`ContainerRef` ⇄ map).

**Reused project infrastructure**:
- `AgenticRealms.World.Router` — add `identify(Entity, by: :entity_id, prefix: "entity-")` + dispatch
  `[CloneEntity, MoveEntity, EditEntity]`; remove object/NPC placement commands from `Room` /
  `NPCBlueprint` dispatch lists.
- `AgenticRealms.World.Commands` — add `clone_entity/2`, `move_entity/3`, `clone_into/4`; re-express
  `spawn_object_from_blueprint/3`, `spawn_object_freeform/3`, seed `place_object`, `take/2`, `drop/2`,
  `spawn_npc_clone/3`, and the quest reward/consume call sites on top of them. `ensure_wizard/1`
  authz unchanged on wizard wrappers.
- `AgenticRealms.World.Projections.WorldProjector` — drop its object/NPC placement/take/drop/clone
  handlers (keep rooms/exits/regions/quest orchestration). New `EntityProjector` owns
  `world_objects`/`npc_clones` writes.
- `AgenticRealms.World.UIEventBroadcaster` — replace per-event object/NPC handlers with one
  `EntityMoved` → witness mapping (table in research §R3); preserve inventory/quest side-broadcasts.
- `AgenticRealms.World.Queries` — repoint room/inventory/NPC reads to `container_type`/`container_id`.
- `AgenticRealms.World.Seed` — object placement + NPC spawn via `clone_into`.
- `application.ex` `commanded_children/0` + `test/support/data_case.ex` `setup_commanded/0` — supervise
  `EntityProjector`.

**Storage**:
- **`world_objects`** (altered): drop `room_id`, `player_id`, `exactly_one_location`; add
  `container_type` (NOT NULL, CHECK set) + `container_id` (NULL iff void); partial unique index
  `(container_id, lower(name)) WHERE container_type='room'`. Quest scope columns unchanged.
- **`npc_clones`** (altered): drop `blueprint_id`, `serial`, `room_id`; add `container_type`/
  `container_id`; same partial unique room-name index. Name/module retained (lineage semantics gone).
- **No new tables.** The void is `container_type='void', container_id=NULL`; NPC-inventory rows
  (`container_type='npc'`) are unwritten this milestone.
- **Replay-safe**: `EntityCloned` insert `on_conflict: :nothing`; `EntityMoved`/`EntityEdited` are
  absolute/sparse writes (idempotent). Destroyable log ⇒ removed events not replayed; reseed produces
  clean streams.

**Testing** (`ExUnit`):
- **Entity aggregate** (`test/agentic_realms/world/entity_test.exs`, new): `CloneEntity` from
  `id:nil` emits `EntityCloned` (void), re-clone → `{:error, :already_exists}`; `MoveEntity` no-op →
  `:ok`/no event, real move emits `EntityMoved` with current container authoritative, unsupported
  type → error; `EditEntity` sparse/no-op semantics; replay reconstructs container.
- **EntityProjector** (new): `EntityCloned` inserts the kind-right table at void; `EntityMoved`
  updates container idempotently; `EntityEdited` applies diff.
- **Wrapper/service** (new): `clone_into` leaves entity in void on move failure; destination-exists +
  room name-collision pre-checks; `ensure_wizard/1` refusals preserved.
- **Witness mapping** (new): each `(kind, cause, from→to)` row produces exactly the legacy UI struct;
  void moves silent; no new announcements.
- **Retrofit non-regression**: the existing specs 006/007/008/009/010/013/014 suites and the
  take/drop/inventory suites pass with only mechanical event-shape updates.
- **Invariants/concurrency**: exactly-one-container after every op; concurrent moves of one entity →
  single terminal container.

**Target Platform**: Linux server BEAM cluster (prod); macOS single-node (dev). Identical to 014.

**Project Type**: Phoenix LiveView web application (single project).

**Performance Goals**: clone+move arrival end-to-end ≤ 2s p95 (SC-001, the existing spawn budget);
container queries are single-table indexed lookups (sub-ms at milestone scale).

**Constraints**: No new dependencies. No player-visible behavior change (FR-014/SC-002). Exactly one
spawn/relocation model at completion (SC-003).

**Scale/Scope**: Substrate refactor touching the object + NPC placement paths; ~1 new aggregate, 3
new commands/events, 2 altered aggregates, 1 new + 1 trimmed projector, 2 table migrations, ~8
re-expressed wrappers, seed + quest call-site updates. No UI redesign.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The project constitution (`.specify/memory/constitution.md`) is an **unratified template** (no
concrete principles defined), so there are no enumerated gates to evaluate. Applying the project's
de facto conventions as observed in shipped features 012–014:

- **No new dependencies** — satisfied (reuses Commanded/Ecto/PubSub).
- **Event-sourced read models, replay-safe projectors** — satisfied (idempotent handlers).
- **CQRS aggregate-as-consistency-boundary** — satisfied and strengthened (entity owns its location,
  mirroring the `Player` aggregate).
- **Test surface ships with the feature** — satisfied (enumerated above).
- **No player-visible regression for a substrate refactor** — explicit gate (SC-002).

**Result**: PASS (no constitutional violations; no Complexity Tracking entries required).

*Post-Phase-1 re-check*: design introduces exactly one new aggregate and one new projector, removes
more than it adds (seven commands/events retired), and adds no dependencies — net simplification of
the spawn surface. PASS.

## Project Structure

### Documentation (this feature)

```text
specs/016-entity-containment/
├── plan.md              # This file
├── research.md          # Phase 0 — design decisions (R1–R8)
├── data-model.md        # Phase 1 — aggregate, container ref, events, schema, projector, queries
├── quickstart.md        # Phase 1 — verification walkthrough
├── contracts/
│   ├── commands.md      # CloneEntity / MoveEntity / EditEntity + service wrappers
│   └── events.md        # EntityCloned / EntityMoved / EntityEdited + witness mapping
└── tasks.md             # Phase 2 (/speckit.tasks — NOT created by /speckit.plan)
```

### Source Code (repository root) — existing single Phoenix project

```text
lib/agenticrealms/world/
├── entity.ex                         # NEW — generic Entity aggregate (clone/move/edit)
├── container_ref.ex                  # NEW — ContainerRef value + serialization
├── room.ex                           # ALTERED — remove object_ids + placement/take/drop/edit clauses
├── npc_blueprint.ex                  # ALTERED — remove SpawnNPCClone + next_serial/clone_ids
├── router.ex                         # ALTERED — identify(Entity); dispatch retrofit
├── commands.ex                       # ALTERED — clone_entity/move_entity/clone_into + re-expressed wrappers
├── seed.ex                           # ALTERED — placement/NPC spawn via clone_into
├── queries.ex                        # ALTERED — container_type/container_id reads
├── commands/                         # NEW: clone_entity.ex, move_entity.ex, edit_entity.ex
│                                     #   REMOVED: place_object, spawn_object_*, take_object, drop_object, edit_object, spawn_npc_clone
├── events/                           # NEW: entity_cloned.ex, entity_moved.ex, entity_edited.ex
│                                     #   REMOVED: object_placed_in_room, object_spawned, object_taken_from_room, object_dropped_in_room, object_edited, npc_cloned_from_blueprint, npc_spawned_in_room
├── projections/
│   ├── entity_projector.ex           # NEW — world_objects + npc_clones writes from Entity events
│   └── world_projector.ex            # ALTERED — drop object/NPC placement handlers
├── ui_event_broadcaster.ex           # ALTERED — one EntityMoved → witness mapping
└── schemas/
    ├── object.ex                     # ALTERED — container columns (drop room_id/player_id/XOR)
    └── npc_clone.ex                  # ALTERED — container columns; drop blueprint_id/serial

priv/repo/migrations/
├── <ts>_world_objects_container_ref.exs   # NEW
└── <ts>_npc_clones_container_ref.exs       # NEW

lib/agenticrealms/application.ex            # ALTERED — supervise EntityProjector
test/support/data_case.ex                   # ALTERED — start EntityProjector in setup_commanded
test/agentic_realms/world/…                  # NEW + UPDATED test suites (see Technical Context)
```

**Structure Decision**: Existing single Phoenix project layout (identical to features 012–014). All
changes live under `lib/agenticrealms/world/` and `priv/repo/migrations/`; no new app or boundary.

## Phasing (for /speckit.tasks)

Suggested dependency-ordered grouping (details emerge in tasks.md):

1. **Foundational** — `ContainerRef`; `Entity` aggregate + `CloneEntity`/`MoveEntity`/`EditEntity`
   commands/events; router `identify`/dispatch for Entity; `EntityProjector`; container-column
   migrations + schema updates; supervision wiring. (Blocks everything.)
2. **Service layer** — `clone_entity`/`move_entity`/`clone_into` wrappers + destination/name-collision
   validation; witness mapping in `UIEventBroadcaster`.
3. **Object retrofit (US1/US2)** — re-express wizard spawn, seed placement, `take`/`drop`, quest
   reward/consume on the service; remove `Room` object clauses + old object events/commands; repoint
   `Queries`.
4. **NPC retrofit (US2/US3, FR-013)** — re-express NPC spawn via `clone_into(:npc, …)`; remove
   `SpawnNPCClone`/`NPCClonedFromBlueprint` + lineage columns; drop legacy `NPCSpawnedInRoom` handling.
5. **Relocation + void (US3/US4)** — room→room moves; move-to-void removal (quest consumption);
   invariant/concurrency tests.
6. **Polish** — one-model audit (SC-003), full-suite non-regression (SC-002), quickstart walkthrough.

## Complexity Tracking

No Constitution Check violations — section intentionally empty. (The refactor *reduces* surface area:
seven commands/events removed, one aggregate + one projector added, no new dependencies.)
