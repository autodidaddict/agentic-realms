---
description: "Task list for feature 016 — entity lifecycle: clone & move with typed containment"
---

# Tasks: Entity Lifecycle — Clone & Move with Typed Containment

**Input**: Design documents from `/specs/016-entity-containment/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md (all present)

**Tests**: Included throughout. This is a substrate refactor whose headline gate is **zero
player-visible regression** (SC-002) — the non-regression suites are release-blocking, not optional.

**Organization**: Phases are ordered so the build/tests are **green at the end of each phase**. This
is a cross-cutting refactor (the `world_objects`/`npc_clones` column change cannot coexist with the
old model), so the object side (Phase 3) and the NPC side (Phase 4) each cut over atomically. Story
labels map to spec.md user stories US1–US5.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: US1–US5 (user-story phases only; Setup/Foundational/Polish carry no story label)
- Paths are repo-root-relative; the existing single Phoenix project layout is used per plan.md.

## Path conventions

- Code: `lib/agenticrealms/...`, `lib/agentic_realms_web/...`
- Tests: `test/agenticrealms/...`
- Migrations: `priv/repo/migrations/`

## Implementation status (2026-06-04)

All phases implemented and **green** on branch `016-entity-containment` (PR #36): `mix compile
--warnings-as-errors` clean; full suite **650 passed, 35 excluded**; SC-003 single spawn/relocation
model achieved. Reconciliation notes:

- The dedicated test-file tasks **T016, T029, T030** were satisfied via the integration suite rather
  than the separately-named files: the entity service, projector, witness mapping, and arrival path
  are exercised by `entity_test`, `container_ref_test`, the ported wrapper tests, the T031a
  concurrent-take test, and `entity_lifecycle_integration_test` (void / relocation / uniformity).
- The Phase 3/4 cutover was a **clean swap** (destroyable log + reseed), not the expand/contract
  hedge the T017 note anticipated — the column change + all call sites landed together per phase.
- **T050** (manual quickstart walkthrough) is the only open item — a browser/dev-seed check, pending.

---

## Phase 1: Setup

**Purpose**: Baseline confirmation. No new dependencies.

- [X] T001 Confirm clean baseline on branch `016-entity-containment`: `mix deps.get` reports nothing new, `mix compile --warnings-as-errors` succeeds, and `mix test` is green before any changes land.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Build the new clone/move substrate **additively** — these compile alongside the old
spawn model (which still owns the table columns until Phase 3). No call site is rewired yet, so the
suite stays green.

**⚠️ CRITICAL**: No user-story phase can begin until this phase is complete.

### Container value + commands + events

- [X] T002 [P] Create `lib/agenticrealms/world/container_ref.ex` — `%ContainerRef{type, id}` with `void/0`, `room/1`, `player/1`, `npc/1`, `valid_type?/1`, `to_map/1`, `from_map/1` per data-model.md §1.
- [X] T003 [P] Unit tests `test/agenticrealms/world/container_ref_test.exs` — helpers, `to_map`/`from_map` round-trip, void⇔nil-id pairing, invalid type rejection.
- [X] T004 [P] Create command `lib/agenticrealms/world/commands/clone_entity.ex` — `entity_id, kind, fields` per contracts/commands.md.
- [X] T005 [P] Create command `lib/agenticrealms/world/commands/move_entity.ex` — `entity_id, expected_from, to, cause`.
- [X] T006 [P] Create command `lib/agenticrealms/world/commands/edit_entity.ex` — `entity_id, fields_changed`.
- [X] T007 [P] Create event `lib/agenticrealms/world/events/entity_cloned.ex` — `entity_id, kind, fields`, `version: 1`.
- [X] T008 [P] Create event `lib/agenticrealms/world/events/entity_moved.ex` — `entity_id, from, to, cause`, `version: 1`.
- [X] T009 [P] Create event `lib/agenticrealms/world/events/entity_edited.ex` — `entity_id, fields_changed`, `version: 1`.

### Entity aggregate + routing

- [X] T010 Create `lib/agenticrealms/world/entity.ex` aggregate (struct `id/kind/container`); `execute/2` for `CloneEntity` (nil→`EntityCloned` void, else `:already_exists`), `MoveEntity` (no-op→`:ok` no event; **`expected_from != current container` → `{:error, :container_conflict}`** so a stale/concurrent move is refused not silently applied — FR-005; unsupported type→`:unsupported_container`; else `EntityMoved`), `EditEntity` (no-op→`:ok`; else `EntityEdited`); `apply/2` clauses; `ContainerRef` JSON (de)serialization per contracts/events.md.
- [X] T011 Register in `lib/agenticrealms/world/router.ex`: `identify(Entity, by: :entity_id, prefix: "entity-")` and dispatch `[CloneEntity, MoveEntity, EditEntity] → Entity`. (Additive — leave existing dispatch intact.)
- [X] T012 [P] Aggregate unit tests `test/agenticrealms/world/entity_test.exs` — clone happy/already_exists; move no-op/real/unsupported-type; **`MoveEntity` with `expected_from` ≠ current container → `{:error, :container_conflict}` (no event)**; edit sparse/no-op; mid-stream replay reconstructs `container`.

### Projector + service + witness (written, not yet active)

> **Reorder note (impl):** T013–T016 reference `world_objects`/`npc_clones` **container columns**
> that don't exist until the Phase 3/4 migrations, so they cannot compile against the current schema.
> They are therefore implemented **together with the Phase 3 object cutover** (expand the schema with
> the container columns first, keeping `room_id`/`player_id` until all call sites move, then contract).
> The pure-additive Phase 2 core (T002–T012) is complete and green on its own.

- [X] T013 Create `lib/agenticrealms/world/projections/entity_projector.ex` (`:strong`) handling `EntityCloned` (insert `world_objects`|`npc_clones` by kind at `container_type='void'`, `on_conflict: :nothing`), `EntityMoved` (absolute container update), `EntityEdited` (apply sparse diff) per data-model.md §7. (Not yet supervised.)
- [X] T014 Add service wrappers to `lib/agenticrealms/world/commands.ex` — `clone_entity/2`, `move_entity/4` (`entity_id, expected_from, to, cause`), `clone_into/4` (mint id; destination-exists + room name-collision pre-checks; `move_entity` passes the resolved source as `expected_from` and maps `:container_conflict` to a caller-facing "no longer there"; clone-then-move uses `expected_from = void` and leaves the entity in void on move failure) per contracts/commands.md. (Not yet wired into existing call sites.)
- [X] T015 Add an `EntityMoved` witness-mapping helper to `lib/agenticrealms/world/ui_event_broadcaster.ex` mapping `(kind, cause, from.type→to.type)` to legacy UI structs per research.md §R3 (pure function; not yet subscribed).
- [X] T016 [P] Tests `test/agentic_realms/world/entity_service_test.exs` + `..._witness_test.exs` — `clone_into` void-on-failure; pre-check refusals; every witness-mapping row; void moves silent.

**Checkpoint**: New substrate compiles and is unit-tested; old spawn model still live and green.

---

## Phase 3: User Story 1 + 2 (Objects) — Object Lifecycle on Clone/Move (Priority: P1) 🎯 MVP

**Goal**: Replace the object spawn/take/drop/quest paths with clone/move. Delivers US1 (bring an
object into the world via `clone_into(room)`) and the object half of US2 (no player-visible change to
objects, `take`/`drop`/`inventory`, or quest items).

**Independent Test**: As a wizard, spawn an object → co-present player sees `... appears.` within ~2s
and `examine` shows fields (US1). `take`/`inventory`/`drop` and the quest flow behave exactly as
before (US2). All object/take-drop/quest suites pass.

**⚠️ Atomic cutover**: T017–T028 land together — they replace the `world_objects` location columns
and every object call site. The suite is green again at T031.

- [X] T017 [US1] Migration `priv/repo/migrations/<ts>_world_objects_container_ref.exs`: add `container_type` (NOT NULL, CHECK ∈ set) + `container_id` (NULL iff void); backfill from `room_id`/`player_id` (dev convenience — canonical path is reseed); drop `room_id`, `player_id`, `exactly_one_location`; replace name-unique index with partial unique `(container_id, lower(name)) WHERE container_type='room'`. (data-model.md §5.1)
- [X] T018 [US1] Update `lib/agenticrealms/world/schemas/object.ex` — `container_type`/`container_id` fields; remove `room_id`/`player_id`; keep quest scope fields.
- [X] T019 [US1] Repoint object reads in `lib/agenticrealms/world/queries.ex` — `list_objects_in_room/1`, `list_inventory/1`, `resolve_object_in_inventory/2`, `resolve_object_in_room/_`, `object_fixed?/1` to `container_type`/`container_id`.
- [X] T020 [US1] Supervise `EntityProjector` in `lib/agenticrealms/application.ex` `commanded_children/0` and `test/support/data_case.ex` `setup_commanded/0`.
- [X] T021 [US1] Subscribe the `EntityMoved` handler in `lib/agenticrealms/world/ui_event_broadcaster.ex` (object cause rows) and preserve `PlayerInventoryChanged` / `PlayerQuestProgress` side-broadcasts on take/drop.
- [X] T022 [US1] Re-express `spawn_object_from_blueprint/3` and `spawn_object_freeform/3` in `lib/agenticrealms/world/commands.ex` via `clone_into(:object, fields, ContainerRef.room(room_id), :spawned)`.
- [X] T023 [US2] Re-express seed object placement in `lib/agenticrealms/world/seed.ex` via `clone_into(:object, fields, room, :placed)` (carry behaviors + quest scope in `fields`).
- [X] T024 [US2] Re-express `take/2` (→ `move_entity(id, ContainerRef.room(rid), ContainerRef.player(pid), :taken)`) and `drop/2` (→ `move_entity(id, ContainerRef.player(pid), ContainerRef.room(rid), :dropped)`) in `lib/agenticrealms/world/commands.ex`, passing the resolved source as `expected_from` and surfacing `:container_conflict` as the existing "you don't see that here" / "already taken" refusal.
- [X] T025 [US2] Re-express quest **creation** paths: quest-item spawn (dispatched on `QuestAccepted`) via `clone_into(:object, fields incl. `quest_player_id`/`quest_instance_id`, ContainerRef.room(rid), :placed)`; `QuestRewardMinted` reward via `clone_into(:object, reward, ContainerRef.player(pid), :spawned)`. Update the dispatch site in `lib/agenticrealms/world/projections/world_projector.ex`.
- [X] T025a [US2] Re-express quest **removal** paths: `QuestItemsConsumed`/`QuestItemsCleanedUp` via `move_entity(id, <current container>, ContainerRef.void(), :relocated)` (removal-via-void, research §R5), resolving each target's current container as `expected_from`. Ensure only the intended `quest_player_id`/`quest_instance_id`-scoped rows are targeted (no over-removal of other players' quest items).
- [X] T026 [US1] Remove the `object_ids` field and all object placement/spawn/take/drop/edit `execute`+`apply` clauses (and the vestigial `NPCSpawnedInRoom` apply) from `lib/agenticrealms/world/room.ex`.
- [X] T027 [US1] Remove the object placement handlers (`ObjectPlacedInRoom`, `ObjectSpawned`, `ObjectTakenFromRoom`, `ObjectDroppedInRoom`, `ObjectEdited`) from `lib/agenticrealms/world/projections/world_projector.ex`.
- [X] T028 [US1] Delete obsolete object commands/events and remove them from `router.ex` dispatch: commands `place_object`, `spawn_object_from_blueprint`, `spawn_object_freeform`, `take_object`, `drop_object`, `edit_object`; events `object_placed_in_room`, `object_spawned`, `object_taken_from_room`, `object_dropped_in_room`, `object_edited`.
- [X] T029 [US1] EntityProjector object tests `test/agentic_realms/world/projections/entity_projector_test.exs` — `EntityCloned(:object)` inserts a `world_objects` row at void; `EntityMoved` updates container; replay idempotent.
- [X] T030 [US1] Arrival test `test/agentic_realms_web/.../object_clone_move_test.exs` — `clone_into(room)` ⇒ co-present player sees `RoomObjectArrived` within budget; `examine` shows fields; spawning is one clone+move.
- [X] T031 [US2] Object non-regression: update event-shape references and confirm green — feature 014 object suites, the `take`/`drop`/`inventory` suites, and feature 013 quest suites (mechanical updates only).
- [X] T031a [US2] Concurrent-take regression test (replaces the old `Room`-aggregate "already taken" guard): two players `take` the same object near-simultaneously — exactly one succeeds, the loser receives the "already taken / not here" refusal (`:container_conflict`), and the object is **not** stolen from the winner (ends in the first taker's inventory, never relocated to the second). Asserts FR-005 at the integration level (the aggregate unit case is T012).

**Checkpoint**: Objects fully on clone/move; suite green. MVP complete.

---

## Phase 4: User Story 2 (NPCs) — NPC Lifecycle on Clone/Move + Lineage Fold-In (Priority: P1)

**Goal**: Rework NPC spawn onto clone/move and drop the blueprint lineage (FR-013, subsuming the
feature-008 fold-in). Completes US2 for NPCs.

**Independent Test**: Fresh world — seeded NPCs appear in "Also here," examine, are ungettable, greet
on entry (009), and converse (010), identically to before. Specs 007/008/009/010 suites pass.

**⚠️ Atomic cutover**: T032–T037 land together; green again at T040.

- [X] T032 [US2] Migration `priv/repo/migrations/<ts>_npc_clones_container_ref.exs`: add `container_type`/`container_id`; backfill from `room_id`; drop `room_id`, `blueprint_id` FK, `serial`, and the `(blueprint_id, serial)` index; replace name-unique index with the partial unique room index. (data-model.md §5.2)
- [X] T033 [US2] Update `lib/agenticrealms/world/schemas/npc_clone.ex` — `container_type`/`container_id`; remove `blueprint_id`, `serial`, `room_id`, and `belongs_to :blueprint`.
- [X] T034 [US2] Repoint NPC reads in `lib/agenticrealms/world/queries.ex` — `list_npcs_in_room/1`, `resolve_npc_in_room/2` to `container_type`/`container_id`.
- [X] T035 [US2] Re-express `spawn_npc_clone/3` in `lib/agenticrealms/world/commands.ex` via `clone_into(:npc, blueprint_fields, ContainerRef.room(room_id), :spawned)`; update NPC spawn in `lib/agenticrealms/world/seed.ex`.
- [X] T036 [US2] Remove `SpawnNPCClone` `execute` + `NPCClonedFromBlueprint` `apply` and the `next_serial`/`clone_ids` struct fields from `lib/agenticrealms/world/npc_blueprint.ex`; remove `SpawnNPCClone` from `router.ex` dispatch.
- [X] T037 [US2] Remove NPC placement handlers from `lib/agenticrealms/world/projections/world_projector.ex` (`NPCClonedFromBlueprint`, legacy `NPCSpawnedInRoom`, and `SyntheticBlueprintId` usage); delete events `npc_cloned_from_blueprint`, `npc_spawned_in_room` and the `spawn_npc_clone` command struct.
- [X] T038 [US2] Add the `npc` cause row to the `EntityMoved` witness mapping in `lib/agenticrealms/world/ui_event_broadcaster.ex` → `RoomNPCArrived`.
- [X] T039 [US2] EntityProjector NPC tests — `EntityCloned(:npc)` inserts an `npc_clones` row; spawn ⇒ `RoomNPCArrived`.
- [X] T040 [US2] NPC non-regression: update event-shape references and confirm green — specs 007/008/009/010 suites (examine, ungettable, greeting behaviors, conversations); fresh-world Garrick walkthrough unchanged.

**Checkpoint**: Objects and NPCs both on one clone/move model; suite green.

---

## Phase 5: User Story 3 — Relocate an Entity Between Containers (Priority: P2)

**Goal**: General room→room (and →void) relocation through the one move pathway, with departure +
arrival witnessing.

**Independent Test**: Move an object from room A to room B — A's occupants witness departure, B's
witness arrival, entity in exactly one container.

- [X] T041 [US3] Add a new `RoomObjectDeparted` UI struct (`room_id, object_id, name`) to `lib/agenticrealms/world/ui_events.ex` (mirrors the dormant `RoomNPCLeft` shape), then add the `:relocated` room→room mapping in `lib/agenticrealms/world/ui_event_broadcaster.ex` — `RoomObjectDeparted` on the source room + `RoomObjectArrived` on the destination; not emitted for `:taken`/`:dropped` or moves into the void; ensure no double-placement.
- [X] T042 [US3] Relocation tests `test/agentic_realms/world/entity_relocation_test.exs` — A→B leaves A / arrives B / exactly one container; departure + arrival witnessed; →void leaves the room and is visible nowhere.

---

## Phase 6: User Story 4 — Cloned-But-Unplaced Entity in the Void (Priority: P2)

**Goal**: The void is a well-defined, observable state.

**Independent Test**: Clone without moving ⇒ exists, in void, in no listing, no witness; then move
into a room ⇒ normal arrival.

- [X] T043 [US4] Void-state tests `test/agentic_realms/world/entity_void_test.exs` — `clone_entity` (no move) ⇒ row at `container_type='void'`, absent from room view and inventory, zero arrival witnesses; subsequent move into a room fires arrival.
- [X] T044 [US4] Move-to-void tests — quest consume/cleanup (T025a) removes objects from all containers (invisible everywhere); exactly-one-container invariant holds with void as the container; **a quest with two players' scoped items consumes only the finalizing player's `quest_player_id`/`quest_instance_id` rows** (no cross-player over-removal).

---

## Phase 7: User Story 5 — Uniform Containment Across Container Types (Priority: P3)

**Goal**: One move/arrival code path across container types; NPC-inventory defined-but-dormant.

**Independent Test**: The move op + arrival pathway is the same code path for room and player
destinations, differing only by type tag; unknown type rejected; NPC-inventory accepted by the model
but unwired.

- [X] T045 [US5] NPC-inventory dormancy: confirm `move_entity` accepts/validates a `:npc` destination (the NPC must exist) but no read model/UI/query exists and no call site writes `container_type='npc'`; test in `test/agentic_realms/world/container_uniformity_test.exs`.
- [X] T046 [US5] Uniformity test — move into a room vs a player inventory route through the same pathway differing only by type tag; an unknown/unsupported container type is rejected with a clear error (FR-010).
- [X] T047 [US5] Invariant + concurrency tests — exactly-one-container after every operation (FR-004); concurrent moves of one entity are serialized so the loser is **refused** with `:container_conflict` (not merely "converge to one container") and the entity stays with the first mover (FR-005; complements the take-specific T031a).

---

## Phase 8: Polish & Cross-Cutting

**Purpose**: Verify the one-model goal and the full non-regression gate.

- [X] T048 One-model audit (SC-003): grep confirms zero references in non-test code to `ObjectSpawned`, `ObjectPlacedInRoom`, `ObjectTakenFromRoom`, `ObjectDroppedInRoom`, `NPCClonedFromBlueprint`, `NPCSpawnedInRoom`; placement flows exclusively through `EntityCloned`/`EntityMoved`.
- [X] T049 Full non-regression gate (SC-002): `mix test` green including specs 006/007/008/009/010/013/014 + take/drop/inventory; `mix compile --warnings-as-errors` clean.
- [ ] T050 Execute `specs/016-entity-containment/quickstart.md` (sections A–D) against a fresh `mix ecto.reset` dev seed; record results.
- [X] T051 [P] `mix format` and tidy any leftover references/comments to the removed spawn model.

---

## Dependencies & Execution Order

- **Phase 1 (Setup)** → **Phase 2 (Foundational)** block everything.
- **Phase 3 (Objects)** depends only on Phase 2. **This is the MVP** — object lifecycle fully on
  clone/move.
- **Phase 4 (NPCs)** depends on Phase 2; independent of Phase 3 (separate table/paths) but sequence
  after Phase 3 to keep one cutover in flight at a time.
- **Phases 5–7** depend on Phases 3–4 (a working move pathway + both kinds retrofitted).
- **Phase 8 (Polish)** last.

Within a phase, `[P]` tasks touch different files and may run in parallel; the atomic-cutover tasks
(T017–T028, T032–T037) are sequential and must land as a set before that phase's suite is green.

## Parallel Execution Examples

- **Phase 2 kickoff**: T002, T004, T005, T006, T007, T008, T009 are all `[P]` (distinct new files) —
  create the value type, commands, and events together; then T010 (aggregate) consumes them.
- **Phase 2 tests**: T003, T012, T016 are `[P]` once their targets exist.

## Implementation Strategy

- **MVP = Phases 1–3**: the substrate + objects fully on clone/move (US1 delivered; objects/take/drop/
  quest non-regressed). Shippable and demonstrable on its own.
- **Increment 2 = Phase 4**: NPCs onto clone/move + lineage fold-in (completes US2).
- **Increment 3 = Phases 5–7**: relocation, the void, and container-type uniformity (US3–US5).
- **Gate = Phase 8**: one-model audit + full non-regression + quickstart.
- Each phase leaves `mix test` green; never split an atomic cutover across a checkpoint.
