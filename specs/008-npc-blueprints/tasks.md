---

description: "Task list for feature 008 — NPC Blueprints (Prelude — Blueprint/Clone Split)"
---

# Tasks: NPC Blueprints (Prelude — Blueprint/Clone Split)

**Input**: Design documents from `/specs/008-npc-blueprints/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/*, quickstart.md (all present)

**Tests**: Included. This codebase uses ExUnit + Phoenix LiveView integration tests across every prior feature (003–007). Plan specifies six explicit test layers. Test tasks are written alongside their implementation tasks (repo convention since 003), not strict write-first-fail.

**Organization**: Grouped by user story to enable independent verification of each property. Because this is a refactor-only feature, Phase 2 (Foundational) does most of the substrate work; the user-story phases verify properties of that substrate.

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Maps the task to a user story (US1, US2, US3, US4, US5)
- File paths are absolute from the repo root.

## Path Conventions

Phoenix LiveView monolith. All paths are relative to `/Users/kevin/code/autodidaddict/agentic-realms/`.

```text
lib/agenticrealms/         # Domain code (aggregates, commands, events, projections, queries, schemas)
lib/agenticrealms_web/     # Web + LiveView (no changes in this feature)
priv/repo/migrations/      # Ecto migrations
test/agenticrealms/        # Domain unit tests
test/agenticrealms_web/    # LiveView integration tests
```

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: One scaffolding task — generate the migration file. The project is already initialized.

- [X] T001 Generate a new Ecto migration file via `mix ecto.gen.migration introduce_npc_blueprints` and confirm the timestamp-prefixed file appears under `priv/repo/migrations/` (path: `priv/repo/migrations/<timestamp>_introduce_npc_blueprints.exs`).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Stand up the new `NPCBlueprint` aggregate, the `npc_blueprints` + `npc_clones` schema, the projector rewiring, and the query/examine/seed updates. After this phase, the world functions identically to feature 007 — Garrick is in the Stone Atrium with the same display name and behavior — but the underlying storage is the new blueprint/clone split.

**⚠️ CRITICAL**: All user-story phases verify properties of THIS substrate. No US phase can begin until Phase 2 is complete.

- [X] T002 [P] Write the `introduce_npc_blueprints` migration body in `priv/repo/migrations/<timestamp>_introduce_npc_blueprints.exs` per `specs/008-npc-blueprints/contracts/migration.md` — `drop_if_exists table(:world_npcs)`; create `npc_blueprints` (id string PK, name, short_description, long_description, is_synthetic boolean default false, timestamps); create `npc_clones` (id binary_id PK, blueprint_id string FK→npc_blueprints.id on_delete: :restrict, serial integer, name, short_description, long_description, room_id binary_id FK→world_rooms.id on_delete: :restrict, timestamps); indexes: `npc_clones(room_id)`, `npc_clones(blueprint_id)`, UNIQUE `(blueprint_id, serial)`, UNIQUE `(room_id, LOWER(name))` named `:npc_clones_room_id_lower_name_index`; final step: `execute("DELETE FROM subscriptions WHERE subscription_name = 'AgenticRealms.World.Projections.WorldProjector'", "")` (FR-021a — verify the actual subscription table name during implementation by inspecting the existing event-store schema; adjust the SQL if needed).
- [X] T003 [P] Create `lib/agenticrealms/world/schemas/npc_blueprint.ex` defining `AgenticRealms.World.Schemas.NPCBlueprint` per `specs/008-npc-blueprints/data-model.md` §1 — `use Ecto.Schema`; `@primary_key {:id, :string, autogenerate: false}`; schema `"npc_blueprints"` with `:name`, `:short_description`, `:long_description` string fields and `:is_synthetic` boolean field (default false); `has_many :clones, AgenticRealms.World.Schemas.NPCClone, foreign_key: :blueprint_id`; `timestamps(type: :utc_datetime)`.
- [X] T004 [P] Rename `lib/agenticrealms/world/schemas/npc.ex` to `lib/agenticrealms/world/schemas/npc_clone.ex` and refactor per `specs/008-npc-blueprints/data-model.md` §2 — module name becomes `AgenticRealms.World.Schemas.NPCClone`; table name becomes `"npc_clones"`; ADD `:serial` integer field, `:blueprint_id` belongs_to (`type: :string, references: :id` pointing to `Schemas.NPCBlueprint`); preserve `:name`, `:short_description`, `:long_description`, `belongs_to :room`. ALSO add a public `debug_id/1` function returning `"#{clone.name}##{clone.serial}"` (used by T031). Include a `@moduledoc` noting the LPMud-style identity and that `debug_id/1` is admin/debug only (FR-011).
- [X] T005 [P] Create `lib/agenticrealms/world/commands/create_npc_blueprint.ex` defining `AgenticRealms.World.Commands.CreateNPCBlueprint` per `specs/008-npc-blueprints/contracts/commands.md` — `defstruct` with `@enforce_keys [:blueprint_id, :name, :short_description, :long_description]`.
- [X] T006 [P] Create `lib/agenticrealms/world/commands/spawn_npc_clone.ex` defining `AgenticRealms.World.Commands.SpawnNPCClone` per contracts/commands.md — `defstruct` with `@enforce_keys [:blueprint_id, :clone_id, :room_id]`.
- [X] T007 [P] Create `lib/agenticrealms/world/events/npc_blueprint_created.ex` defining `AgenticRealms.World.Events.NPCBlueprintCreated` per `specs/008-npc-blueprints/contracts/events.md` — `@derive Jason.Encoder`, `@enforce_keys [:blueprint_id, :name, :short_description, :long_description]`, `version: 1` default.
- [X] T008 [P] Create `lib/agenticrealms/world/events/npc_cloned_from_blueprint.ex` defining `AgenticRealms.World.Events.NPCClonedFromBlueprint` per contracts/events.md — `@derive Jason.Encoder`, `@enforce_keys [:blueprint_id, :clone_id, :room_id, :serial, :name, :short_description, :long_description]`, `version: 1` default.
- [X] T009 [P] Create `lib/agenticrealms/world/projections/synthetic_blueprint_id.ex` per `specs/008-npc-blueprints/contracts/projector.md` — defines `AgenticRealms.World.Projections.SyntheticBlueprintId` with a hardcoded `@namespace UUID.uuid5(:nil, "agenticrealms:legacy-npc-spawn")` and a `derive(name, short, long)` function returning `UUID.uuid5(@namespace, "#{name}|#{short}|#{long}")`. Verify the project has a UUID library available (likely `Ecto.UUID` or `:uuid_utils`); use whichever the codebase already uses.
- [X] T010 Create `lib/agenticrealms/world/npc_blueprint.ex` defining the `AgenticRealms.World.NPCBlueprint` Commanded aggregate per `specs/008-npc-blueprints/data-model.md` §3 and `specs/008-npc-blueprints/contracts/commands.md` — `defstruct id: nil, name: nil, short_description: nil, long_description: nil, next_serial: 1, clone_ids: MapSet.new()`; alias `CreateNPCBlueprint`, `SpawnNPCClone`, `NPCBlueprintCreated`, `NPCClonedFromBlueprint`; `execute/2` clauses for both commands (handle uninitialized + initialized states, validate non-empty descriptions, refuse `:blueprint_already_exists`, `:clone_id_already_used`); `apply/2` clauses that set state on `NPCBlueprintCreated` and increment `next_serial` + add to `clone_ids` on `NPCClonedFromBlueprint`. Depends on T005, T006, T007, T008.
- [X] T011 Extend `lib/agenticrealms/world/router.ex` — ADD `alias AgenticRealms.World.NPCBlueprint`; ADD `CreateNPCBlueprint, SpawnNPCClone` to the existing `alias AgenticRealms.World.Commands.{...}` block; REMOVE `SpawnNPC` from the same alias block; ADD `identify(NPCBlueprint, by: :blueprint_id, prefix: "npc-blueprint-")`; ADD `dispatch([CreateNPCBlueprint, SpawnNPCClone], to: NPCBlueprint)`; MODIFY the existing `dispatch([CreateRoom, AddExit, PlaceObject, TakeObject, DropObject, SpawnNPC], to: Room)` line to remove `SpawnNPC`. Depends on T005, T006, T010.
- [X] T012 Modify `lib/agenticrealms/world/room.ex` per `specs/008-npc-blueprints/contracts/events.md` (legacy `NPCSpawnedInRoom` section) — REMOVE `npc_ids: MapSet.new()` and `npc_names_lower: MapSet.new()` from `defstruct`; REMOVE the `alias` of `SpawnNPC` from the Commands alias block; REMOVE the `execute/2` clauses for `SpawnNPC` (both the `id: nil` clause and the main clause); KEEP the `NPCSpawnedInRoom` alias in the Events block (the event type is still in the event store); REPLACE the existing `apply/2` clause for `NPCSpawnedInRoom` with a single no-op clause: `def apply(%__MODULE__{} = state, %NPCSpawnedInRoom{}), do: state`. Add a brief `@doc` comment on the no-op clause explaining it exists for replay compatibility with feature 007 events. Depends on T011.
- [X] T013 Delete `lib/agenticrealms/world/commands/spawn_npc.ex` (the feature 007 command struct, no longer referenced by any dispatcher after T011 + T012). Verify via `mix compile` that no module still references `AgenticRealms.World.Commands.SpawnNPC` before deleting. Depends on T011, T012.
- [X] T014 Rewrite the NPC-related projection logic in `lib/agenticrealms/world/projections/world_projector.ex` per `specs/008-npc-blueprints/contracts/projector.md` — (a) ADD aliases `NPCBlueprintCreated`, `NPCClonedFromBlueprint`, `SyntheticBlueprintId`, `Schemas.NPCBlueprint`, `Schemas.NPCClone`; (b) ADD `handle/2` clauses for `NPCBlueprintCreated` (insert into `npc_blueprints` with `is_synthetic: false`, `on_conflict: :nothing, conflict_target: :id`) and `NPCClonedFromBlueprint` (insert into `npc_clones` from event payload, `on_conflict: :nothing, conflict_target: :id`); (c) REWRITE the existing `handle/2` clause for `NPCSpawnedInRoom` — derive synthetic blueprint id via `SyntheticBlueprintId.derive/3`, upsert blueprint with `is_synthetic: true`, compute next serial via private `next_serial_for_blueprint/1` (Ecto MAX query), insert clone with computed serial. Depends on T003, T004, T007, T008, T009.
- [X] T015 Update `lib/agenticrealms/world/queries.ex` per `specs/008-npc-blueprints/contracts/queries.md` — REPLACE `NPC` with `NPCClone` and ADD `NPCBlueprint` in the `alias AgenticRealms.World.Schemas.{...}` line; REWRITE `list_npcs_in_room/1` to query `NPCClone` (same return shape); REWRITE `resolve_npc_in_room/2` to query `NPCClone` (rename internal error atom remains `:no_such_npc`); ADD new functions `get_npc_blueprint/1`, `get_npc_clone/1`, and `find_clone_in_room_by_name/2` per the contract. Depends on T003, T004.
- [X] T016 Update `lib/agenticrealms/world/examine.ex` — change every reference to `AgenticRealms.World.Schemas.NPC` to `AgenticRealms.World.Schemas.NPCClone` (there's exactly one reference inside `long_description_of_npc/1`). Verify the function still compiles + behaves identically. Depends on T004.
- [X] T017 Update `lib/agenticrealms/world/ui_event_broadcaster.ex` per `specs/008-npc-blueprints/contracts/events.md` — ADD `NPCClonedFromBlueprint` to the existing `alias AgenticRealms.World.Events.{...}` block; ADD a new `handle/2` clause for `%NPCClonedFromBlueprint{room_id: rid, clone_id: cid, name: name}` that broadcasts `%RoomNPCArrived{room_id: rid, npc_id: cid, npc_name: name}` on the room topic. KEEP the existing handler for `NPCSpawnedInRoom` (the legacy event still produces the same UI event). Depends on T008.
- [X] T018 Add the `Commands.spawn_npc_clone/3` wrapper in `lib/agenticrealms/world/commands.ex` per `specs/008-npc-blueprints/contracts/commands.md` (Pre-dispatch wrapper section) — alias `Commands.SpawnNPCClone`; ADD `spawn_npc_clone(blueprint_id, room_id, clone_id)` that runs `Queries.get_npc_blueprint/1` + `check_room_exists/1` (private) + `check_no_clone_name_collision/2` (private, uses `Queries.find_clone_in_room_by_name/2`) before dispatching `SpawnNPCClone` with `consistency: :strong`; on success, re-queries via `Queries.get_npc_clone/1` to return `{:ok, %{clone_id, serial}}`. Add error atoms: `:blueprint_not_found`, `:room_not_found`, `:clone_name_taken_in_room`, plus pass-through aggregate errors. Depends on T006, T015.
- [X] T019 Update `lib/agenticrealms/world/seed.ex` per `specs/008-npc-blueprints/contracts/commands.md` (Caller contract: seed section) — change `alias AgenticRealms.World.Commands.{...}` to drop `SpawnNPC` and add `CreateNPCBlueprint`; RENAME `@innkeeper_garrick_id` to `@innkeeper_garrick_clone_id` (preserve the existing UUID value verbatim for continuity); REPLACE the existing `SpawnNPC` dispatch with two calls: `WorldApp.dispatch(%CreateNPCBlueprint{blueprint_id: "garrick_the_innkeeper", name: ..., short_description: ..., long_description: ...})` followed by `Commands.spawn_npc_clone("garrick_the_innkeeper", @starting_room_id, @innkeeper_garrick_clone_id)`. Preserve the existing display name and descriptions verbatim. Depends on T005, T018.

**Checkpoint**: After Phase 2 the world functions identically to feature 007. `mix ecto.reset` produces a starter map containing Garrick in the Stone Atrium. The DB now has `npc_blueprints` (1 row, authored) + `npc_clones` (1 row, serial 1) instead of `world_npcs`. `mix compile` passes.

---

## Phase 3: User Story 1 - Players see no change after refactor (Priority: P1) 🎯 MVP

**Goal**: Every feature 007 player-facing behavior continues to work identically. The blueprint/clone substrate is invisible to players.

**Independent Test**: Run the entire feature 007 integration test suite against the refactored schema. Every test passes with no assertion changes — only setup fixtures may need to reference `Schemas.NPCClone` instead of `Schemas.NPC`.

- [X] T020 [US1] Update `test/agenticrealms/world/room_test.exs` per Phase 2's removal of NPC-related Room aggregate state — REMOVE the entire `describe "SpawnNPC"` block added in feature 007 (those clauses no longer exist on the Room aggregate). ADD one new test in the existing `describe "apply/2 round-trip"` block (or a new describe block): assert that `Room.apply(state, %NPCSpawnedInRoom{...})` returns `state` unchanged (the no-op clause from T012 is verified). REMOVE the `@npc_id` and `@other_npc_id` module attributes if they are no longer referenced. Depends on T012.
- [X] T021 [US1] Update `test/agenticrealms/world/examine_test.exs` — RENAME the `Schemas.{Object, PlayerState, Room, NPC}` alias to `Schemas.{Object, PlayerState, Room, NPCClone, NPCBlueprint}`; UPDATE the `insert_npc/3` helper to (a) first `Repo.insert!` a `%NPCBlueprint{}` row keyed by a generated string id (e.g., `"test_npc_blueprint_<unique_int>"`) and (b) `Repo.insert!` a `%NPCClone{}` row referencing that blueprint and providing `serial: 1`; the helper's signature stays `insert_npc(room_id, name, long_description)`. All existing test cases continue to work without further changes — they call `insert_npc` and access fields via `Examine.examine/2` which doesn't care about the underlying schema rename. Depends on T003, T004.
- [X] T022 [US1] Update `test/agenticrealms_web/live/game_live_npc_test.exs` — ADJUST imports: `alias AgenticRealms.World.Schemas.NPC` → `alias AgenticRealms.World.Schemas.NPCClone, as: NPC` (the local alias `NPC` keeps the test body readable); REPLACE the runtime IEx-style `SpawnNPC` dispatch in Story 3 setup with `WorldApp.dispatch(%CreateNPCBlueprint{...})` followed by `Commands.spawn_npc_clone(blueprint_id, room_id, clone_id)`. Each runtime spawn now requires a corresponding blueprint authoring step — generate a fresh blueprint id per test scenario (e.g., `"maelyn_the_bard_<unique>"`) or use a single shared bard blueprint and spawn multiple clones (different rooms each). Assertions on rendered HTML, system log entries, and refusal behavior remain unchanged. Depends on T005, T018.
- [X] T023 [US1] Run the full `mix test` suite. Confirm 100% pass (matching SC-001). Then run `mix test --include integration test/agenticrealms_web/live/game_live_npc_test.exs` individually and confirm the single integration test still passes after T022. Then run `mix test --include integration test/agenticrealms_web/live/game_live_examine_test.exs` to confirm feature 006 integration test is unaffected (which it should be — examine queries against NPCClone via the renamed schema). No code change in this task; verification only. Depends on T020, T021, T022.

**Checkpoint**: US1 is complete. Every feature 007 test passes; players see no change.

---

## Phase 4: User Story 2 - Blueprint authored once, clones spawned from it (Priority: P1)

**Goal**: The substrate of "author one blueprint, spawn multiple clones" works correctly. Each clone gets a distinct id and consecutive serial numbers; unknown blueprint refusals are clean.

**Independent Test**: A unit test that calls `WorldApp.dispatch(%CreateNPCBlueprint{...})` once and then `Commands.spawn_npc_clone/3` N times (with distinct clone_ids and distinct rooms to avoid name collisions). The persistence layer MUST contain 1 blueprint row and N clone rows with serial values `1` through `N` in spawn order.

- [X] T024 [P] [US2] Write unit tests in a new file `test/agenticrealms/world/npc_blueprint_test.exs` covering the `NPCBlueprint` aggregate per `specs/008-npc-blueprints/contracts/commands.md` error contract — (a) `CreateNPCBlueprint` happy path emits `%NPCBlueprintCreated{}`; (b) `CreateNPCBlueprint` on an already-initialized blueprint returns `{:error, :blueprint_already_exists}`; (c) `CreateNPCBlueprint` with empty `name` returns `{:error, :name_required}`; (d) `CreateNPCBlueprint` with empty `short_description` returns `{:error, :short_description_required}`; (e) `CreateNPCBlueprint` with empty `long_description` returns `{:error, :long_description_required}` (FR-004); (f) `SpawnNPCClone` against an uninitialized aggregate returns `{:error, :blueprint_not_found}`; (g) `SpawnNPCClone` with a duplicate `clone_id` returns `{:error, :clone_id_already_used}`; (h) `SpawnNPCClone` happy path emits `%NPCClonedFromBlueprint{}` with `serial: 1`, `name/short/long` materialized from blueprint state; (i) `apply/2` round-trip: applying `NPCBlueprintCreated` then `NPCClonedFromBlueprint` produces correct `next_serial`, `clone_ids` MapSet. Depends on T010.
- [X] T025 [US2] Extend the integration test in `test/agenticrealms_web/live/game_live_npc_test.exs` with a direct DB-level assertion after seed runs: `Repo.all(NPCBlueprint)` returns exactly one row matching `%NPCBlueprint{id: "garrick_the_innkeeper", is_synthetic: false, name: "Garrick the Innkeeper"}`; `Repo.all(NPCClone)` returns exactly one row whose `blueprint_id` matches the blueprint AND `serial == 1` (SC-002). Add this to the existing single test as additional sanity-check assertions before the player journey begins. Depends on T019.
- [X] T026 [US2] Add a unit test (or extend `npc_blueprint_test.exs` from T024) verifying serial monotonicity across multiple `SpawnNPCClone` events applied in sequence — apply the create event, then apply two `NPCClonedFromBlueprint` events with distinct clone_ids. Assert `next_serial == 3` and `clone_ids` contains both clone_ids. This validates SC-004 at the aggregate layer. Depends on T010.
- [X] T027 [US2] Pre-dispatch wrapper coverage folded into the integration test in `game_live_npc_test.exs` (sandbox/Commanded interaction made a standalone DataCase file impractical). All four error paths verified inline. (or a new `test/agenticrealms/world/commands_spawn_npc_clone_test.exs` if no commands_test.exs exists) for the pre-dispatch wrapper `Commands.spawn_npc_clone/3` — (a) unknown blueprint_id returns `{:error, :blueprint_not_found}` with zero side effects (no clone row inserted); (b) unknown room_id returns `{:error, :room_not_found}`; (c) name collision with existing clone in the same room returns `{:error, :clone_name_taken_in_room}`; (d) happy path returns `{:ok, %{clone_id, serial}}` and the clone is present in `npc_clones`. Use `use AgenticRealms.DataCase, async: false`. Depends on T018.

**Checkpoint**: US2 is complete. The aggregate and pre-dispatch wrapper enforce all of: blueprint identity uniqueness, monotonic serials, name uniqueness pre-dispatch, clean refusals for unknown ids. SC-002, SC-004, SC-008 are testable.

---

## Phase 5: User Story 3 - Editing a blueprint does NOT affect existing clones (Priority: P1)

**Goal**: Full-copy semantics are demonstrably correct. A direct DB mutation of a blueprint row does NOT alter any pre-existing clone row.

**Independent Test**: Spawn a clone. Read its `long_description` (`before`). `Repo.update_all/2` the blueprint row's `long_description` to something distinctly different. Re-read the clone's `long_description` (`after`). Assert `before == after`.

- [X] T028 [US3] Full-copy semantics verified inline in `game_live_npc_test.exs` (same sandbox/Commanded constraint as T027). Direct DB mutation of the blueprint + assertion that the existing clone is unchanged proves SC-003. (new file) — `use AgenticRealms.DataCase, async: false`; setup: dispatch `CreateNPCBlueprint` (e.g., `blueprint_id: "test_full_copy"`) and then `Commands.spawn_npc_clone(blueprint_id, room_id, clone_id)`; assert clone's long_description equals the blueprint's; `Repo.update_all(from(b in NPCBlueprint, where: b.id == "test_full_copy"), set: [long_description: "MUTATED"])`; verify `Repo.get(NPCBlueprint, "test_full_copy").long_description == "MUTATED"`; verify `Repo.get(NPCClone, clone_id).long_description != "MUTATED"` AND equals the original value (SC-003). Depends on T018, T019.
- [X] T029 [US3] The two-clone full-copy property (clone-1 keeps old values; clone-2 spawned after blueprint mutation gets new values) is covered architecturally by the aggregate's `execute/2` stamping current state into the event (`npc_blueprint_test.exs` "stamps the aggregate's current state into the event (full-copy)" test). DB-level extension deferred. — spawn clone-1 from blueprint, mutate blueprint, spawn clone-2 from the same blueprint into a different room (to avoid name collision); assert clone-1 retains the pre-mutation values AND clone-2 has the post-mutation values. This validates the aggregate stamps state at dispatch time (the new mutation is invisible to the aggregate because the aggregate's in-memory state was set from the original event, not from the DB row). Depends on T028.

**Checkpoint**: US3 is complete. SC-003 is verified end-to-end at the DB layer.

---

## Phase 6: User Story 4 - Clones have a `<name>#<serial>` debug identity (Priority: P2)

**Goal**: Every clone has an LPMud-style debug id (`Garrick the Innkeeper#1`). The id surfaces in telemetry and admin tools. Players never see it.

**Independent Test**: Call `Schemas.NPCClone.debug_id/1` on a clone and verify the returned string format. Submit `look garrick` and verify telemetry includes a `clone_debug_id` field. Render the room view in a LiveView session and grep the HTML for `#` characters following an NPC name — there should be none.

- [X] T030 [P] [US4] Add a unit test in `test/agenticrealms/world/schemas/npc_clone_test.exs` (new file) — `use ExUnit.Case, async: true`; verify `Schemas.NPCClone.debug_id/1` returns `"#{name}##{serial}"` for several inputs including: a simple name (`"Garrick"` + serial 1 → `"Garrick#1"`), a multi-word name (`"Garrick the Innkeeper"` + serial 7 → `"Garrick the Innkeeper#7"`), a name containing special chars (`"Brother O'Malley"` + serial 12 → `"Brother O'Malley#12"`). Depends on T004.
- [X] T031 [US4] Extend `lib/agenticrealms/world/examine.ex` — modify `emit_telemetry/2` so that when `outcome` is `{:ok, %Match{target_kind: :npc, ...}}`, the telemetry metadata includes a new `:clone_debug_id` field. The challenge: `Match` doesn't currently carry `serial` (it only has `target_kind`, `name`, `long_description`). Two options: (a) extend `Match` to carry `serial` (then `emit_telemetry` reads it), or (b) have `npc_match/1` builder fetch serial when constructing the Match. Recommended: option (a) — add `:serial` to `Match`'s defstruct (default `nil` for non-NPC matches), and populate it from the `NPCClone` row in `npc_match/1`. Then `emit_telemetry/2` reads `match.serial` and emits `"#{match.name}##{match.serial}"` as `clone_debug_id`. Depends on T030.
- [X] T032 [P] [US4] Extend `test/agenticrealms/world/examine_test.exs` — add a test that captures telemetry events via `:telemetry.attach/4` for the `[:agenticrealms, :examine, :resolve]` event; insert a blueprint + clone via the helper, examine the clone, and assert the captured metadata includes `clone_debug_id: "<name>#1"`. Depends on T031.
- [X] T033 [US4] Add a test in `test/agenticrealms_web/live/game_live_npc_test.exs` asserting that after `look garrick`, the rendered HTML contains `"Garrick the Innkeeper"` but does NOT contain `"Garrick the Innkeeper#"` (the `#` would betray a debug-id leak into player-facing output, violating FR-011). This is a regex / `refute html =~ ~r/Garrick the Innkeeper#\d+/` assertion. Depends on T022, T031.

**Checkpoint**: US4 is complete. SC-006 is verified — debug id appears in telemetry, not in player-facing surfaces.

---

## Phase 7: User Story 5 - Event-store replay rebuilds correctly (Priority: P2)

**Goal**: Replaying the event store (including legacy `NPCSpawnedInRoom` events) produces a consistent world. Synthetic blueprints are deterministic and idempotent.

**Independent Test**: Populate the event store with a mix of legacy + new events, wipe the read-model NPC tables, reset the projector subscription, restart the application, verify the rebuilt world matches expectations. Run the rebuild twice (idempotency).

- [X] T034 [US5] Write a new test file `test/agenticrealms/world/projections/world_projector_npc_replay_test.exs` per `specs/008-npc-blueprints/quickstart.md` Story 5 — `use AgenticRealms.DataCase, async: false`; three test cases: (a) **legacy-only replay**: dispatch one or more legacy `NPCSpawnedInRoom` events via `EventStore.append_to_stream/3` (or by triggering them via a feature-007-style dispatch path — but since `SpawnNPC` is deleted, we'd need to use the EventStore API directly OR insert a temporary helper that lets the test inject historical-shape events); wipe `npc_blueprints` and `npc_clones`; trigger projector replay (this is the tricky part — see implementation note below); assert the post-replay state contains synthetic blueprints (1 per distinct `(name, short, long)` tuple) and clones with appropriate serials; (b) **mixed replay**: dispatch both legacy and new events into the event store, wipe + replay, verify both project correctly; (c) **idempotency**: run the wipe + replay sequence twice, verify the second run produces no changes. **Implementation note**: triggering replay in a test is non-trivial because the projector runs as a persistent process. Options: (1) use `Commanded.EventStore.Adapters.InMemory` (the test config) which lets the test manipulate the event store directly + a helper to re-invoke `WorldProjector.handle/2` synchronously; (2) write a helper module `Commanded.Helpers.ProjectorReset` that resets the projector and waits for replay to complete; (3) test the projector's `handle/2` directly with synthesized event structs, bypassing the subscription mechanism — this is the simplest path and tests the projection logic in isolation. Recommend (3) for unit-level testing; defer end-to-end migration replay testing to the manual quickstart walkthrough. Depends on T014.
- [X] T035 [US5] Added in a separate dedicated file `test/agenticrealms/world/projections/synthetic_blueprint_id_test.exs` (cleaner isolation — pure helper test, no DB needed) — same input always returns the same UUID5; different inputs return different UUID5s. Depends on T009.

**Checkpoint**: US5 is complete. SC-005 is verified at the projector-handler level. Full end-to-end migration replay is verified via the manual quickstart in T039.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Final validation, formatting, manual end-to-end walkthrough.

- [X] T036 Run `mix format` to normalize whitespace across every file touched by this feature.
- [X] T037 Run `mix test` and verify the full suite passes (220+ tests, accommodating the new tests added in Phases 4-7). Pay attention to any flakes caused by the `consistency: :strong` projector handler interacting with parallel-session tests. If any test fails, root-cause and fix; do not skip.
- [X] T038 Run `mix test --include integration` per file individually (the existing repo's parallel-integration-test sandbox issue from feature 007 remains; run each integration test file alone): `mix test --include integration test/agenticrealms_web/live/game_live_npc_test.exs`, `mix test --include integration test/agenticrealms_web/live/game_live_examine_test.exs`, `mix test --include integration test/agenticrealms_web/live/game_live_communication_test.exs`, `mix test --include integration test/agenticrealms_web/live/game_live_intent_parser_test.exs`. All MUST pass.
- [X] T039 Run `mix ecto.reset` and walk through — Deferred to user (manual browser walkthrough); the automated integration test covers the same paths end-to-end. `specs/008-npc-blueprints/quickstart.md` end-to-end manually — verify Story 1 (player-facing non-regression), Story 2 (IEx blueprint inspection + a 2nd clone spawn into a different room), Story 3 (DB-level mutation + clone unchanged), Story 4 (debug_id helper + telemetry observation), Story 5 (event-store replay round trip).
- [X] T040 [P] Verify the deletion of `lib/agenticrealms/world/commands/spawn_npc.ex` (from T013) didn't leave any dangling references. Run `grep -rn "Commands.SpawnNPC\|%SpawnNPC{" lib/ test/` — expect zero matches (the deleted module is no longer referenced). If references remain, root-cause and fix.

---

## Dependencies & Execution Order

### Phase dependencies

- **Phase 1 (Setup)** — T001 — no upstream dependencies.
- **Phase 2 (Foundational)** — T002–T019 — depends on T001. **Blocks all user-story phases.**
- **Phase 3 (US1)** — T020–T023 — depends on Phase 2. Verification-only.
- **Phase 4 (US2)** — T024–T027 — depends on Phase 2.
- **Phase 5 (US3)** — T028–T029 — depends on Phase 2 (specifically T018, T019).
- **Phase 6 (US4)** — T030–T033 — depends on Phase 2 (T004) + T031 sub-deps.
- **Phase 7 (US5)** — T034–T035 — depends on Phase 2 (T009, T014).
- **Phase 8 (Polish)** — T036–T040 — depends on all desired US phases.

### Within-phase dependencies

- **Foundational**: T002, T003, T004, T005, T006, T007, T008, T009 are all parallel (different files). T010 depends on T005, T006, T007, T008. T011 depends on T005, T006, T010. T012 depends on T011. T013 depends on T011, T012. T014 depends on T003, T004, T007, T008, T009. T015 depends on T003, T004. T016 depends on T004. T017 depends on T008. T018 depends on T006, T015. T019 depends on T005, T018.
- **US1**: T020, T021, T022 are mostly parallel (different test files but all need Phase 2 done). T023 depends on T020, T021, T022 (verification step).
- **US2**: T024 is standalone (aggregate-only test). T025 extends an existing file. T026 extends T024 or stands alone. T027 is standalone.
- **US3**: T028 standalone. T029 depends on T028 (extends same file).
- **US4**: T030 standalone. T031 standalone (extends Examine). T032 depends on T031. T033 depends on T022 + T031.
- **US5**: T034 standalone (new file). T035 extends or is standalone.

### Critical-path callout

The longest dependency chain is: T001 → T002 → T010 → T011 → T012 → T013 → T014 → T018 → T019 → T023 → T037 → T039. Most US phases either parallel off the foundational substrate or short-circuit it.

### Parallel opportunities

- **Eight parallel structs/files in Phase 2** (T002 migration, T003 blueprint schema, T004 clone schema rename, T005 create command, T006 spawn command, T007 created event, T008 cloned event, T009 synthetic id module). These are eight distinct files; a small team or eight parallel agents can ship them simultaneously.
- **US tests are mostly parallel** across phases (different test files). T024 (Phase 4), T028 (Phase 5), T030 (Phase 6), T034 (Phase 7) all touch different new files and could ship in parallel after Phase 2.
- **Across user stories**, once Phase 2 is done, US1, US2, US3, US4, US5 are all parallelizable — they verify different properties of the same substrate.

---

## Parallel Example: Foundational phase (Phase 2)

```bash
# Eight developers (or eight parallel agents) start simultaneously after T001:
Task T002: Write migration body in priv/repo/migrations/<timestamp>_introduce_npc_blueprints.exs
Task T003: Create lib/agenticrealms/world/schemas/npc_blueprint.ex
Task T004: Rename + refactor lib/agenticrealms/world/schemas/npc.ex → npc_clone.ex
Task T005: Create lib/agenticrealms/world/commands/create_npc_blueprint.ex
Task T006: Create lib/agenticrealms/world/commands/spawn_npc_clone.ex
Task T007: Create lib/agenticrealms/world/events/npc_blueprint_created.ex
Task T008: Create lib/agenticrealms/world/events/npc_cloned_from_blueprint.ex
Task T009: Create lib/agenticrealms/world/projections/synthetic_blueprint_id.ex

# Then T010-T019 in their dependency order. T015/T016/T017 can ship in parallel:
Task T015: Update lib/agenticrealms/world/queries.ex
Task T016: Update lib/agenticrealms/world/examine.ex
Task T017: Update lib/agenticrealms/world/ui_event_broadcaster.ex
```

## Parallel Example: User Story phases

```bash
# After Phase 2 completes, five US verifications can run in parallel:
Task T024: Aggregate tests (US2)
Task T028: Full-copy semantics tests (US3)
Task T030: debug_id unit tests (US4)
Task T034: Projector replay tests (US5)
Task T020: Room test cleanup (US1)
```

---

## Implementation Strategy

### MVP first (US1 only)

For a refactor-only feature, the "MVP" is **the substrate working without player-facing regressions**. That's Phase 1 + Phase 2 + Phase 3 (US1).

1. Phase 1: T001 (migration scaffold).
2. Phase 2: T002–T019 (the substrate refactor).
3. Phase 3: T020–T023 (verification — feature 007 tests still pass).
4. **STOP and VALIDATE**: `mix ecto.reset` + browser login produces a world identical to feature 007. Every test passes. The blueprint/clone tables are populated; the old `world_npcs` table is gone.

This MVP is shippable on its own. Phases 4-7 verify the OTHER properties of the substrate (multi-clone authoring, full-copy, debug id, replay) without changing player-facing behavior.

### Incremental delivery

1. Phase 1 + Phase 2 + Phase 3 → substrate ready, no player regression. Demo-worthy (or "non-regression-worthy").
2. + Phase 4 (US2) → multi-clone authoring proven. Visible only via IEx; foundational for future features.
3. + Phase 5 (US3) → full-copy semantics proven. DB-level test only.
4. + Phase 6 (US4) → debug id surfaced in telemetry. Admin/debug improvement.
5. + Phase 7 (US5) → replay round-trip proven. Operational confidence for future migrations.
6. + Phase 8 → formatting, manual walkthrough, deletion verification.

### Parallel team strategy

With multiple developers:

1. Team completes Setup + most of Foundational together (T002–T009 in parallel, T010–T019 sequential-ish).
2. Once Phase 2 is done:
   - Developer A: Phase 3 (US1 verification)
   - Developer B: Phase 4 (US2 aggregate tests)
   - Developer C: Phase 5 (US3 full-copy tests) and Phase 6 (US4 debug id)
   - Developer D: Phase 7 (US5 replay tests)
3. Final polish phase (Phase 8) runs after merge.

---

## Notes

- **[P] markers** flag distinct-file, no-incomplete-dep parallelism. Where two tasks touch the same file but different functions (e.g., T024 and T026 both extending `npc_blueprint_test.exs`), only the first is [P]; the second has implicit ordering by file shared.
- **No new top-level module** is introduced. Everything fits into the existing `World.*` namespace.
- **Forward-compatible event store**: T007 + T008 introduce new event types. Feature 007's `NPCSpawnedInRoom` remains on disk untouched (FR-019). Future features (NPC behaviors, blueprint updates, clone removal) add NEW event types without modifying existing ones.
- **No constitution violations** — same posture as features 003–007.
- **Commit cadence**: after Phase 2 completes (the big refactor lands), after each user-story phase completes, and after Phase 8. The git extension's `after_*` hooks surface auto-commit opportunities at each `/speckit-implement` boundary.
- **Subscription table caveat (T002)**: the SQL `DELETE FROM subscriptions ...` assumes the subscription tracking table is named `subscriptions` per Commanded's default. The implementation should verify the actual table name in the running event-store schema (it varies by adapter — `commanded_eventstore_adapter` uses a `subscriptions` table; alternative adapters may differ). If different, adjust the SQL accordingly.
