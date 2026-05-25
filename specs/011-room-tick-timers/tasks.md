# Tasks: Room-Scoped Tick Timers (Feature 011)

**Input**: Design documents from `/specs/011-room-tick-timers/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Test tasks are INCLUDED — every prior feature (009/010) shipped with paired test coverage and the spec defines 8 measurable success criteria. The pattern continues.

**Organization**: Tasks are grouped by user story (US1–US5 from spec.md) so each story can be implemented and verified after the foundational layer is complete. Within stories, tests are co-located with the implementation they verify.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: parallelizable — different files, no dependency on incomplete tasks.
- **[Story]**: US1–US5; omitted for Setup, Foundational, and Polish phases.

## Path Conventions

Phoenix LiveView single project. All paths under repo root `/Users/kevin/code/autodidaddict/agentic-realms/`. Implementation files under `lib/`, tests under `test/`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project-level config + directory scaffolding.

- [X] T001 [P] Create directory `lib/agenticrealms/world/ticks/` for the new module tree.
- [X] T002 [P] Create directory `test/agenticrealms/world/ticks/` for the new test tree.
- [X] T003 [P] In `config/config.exs`, add `config :agenticrealms, AgenticRealms.World.Ticks, base_tick_rate_ms: 1_000, join_grace_ms: 250, leave_grace_ms: 5_000` with a brief comment naming each value's purpose.
- [X] T004 [P] In `config/test.exs`, override the three values for fast tests: `config :agenticrealms, AgenticRealms.World.Ticks, base_tick_rate_ms: 50, join_grace_ms: 10, leave_grace_ms: 50`.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Object behaviors plumbing, validator extension, UIEvent extensions, atom-table pre-declaration, cluster supervision tree wiring, ActionExecutor recipient fanout for tick. Every task below MUST complete before any user-story phase begins.

### Object `behaviors` plumbing (mirrors feature 009/010 pattern)

- [X] T005 Create migration `priv/repo/migrations/<timestamp>_add_object_behaviors_column.exs` that adds `behaviors` JSONB column to `world_objects` with `add :behaviors, :map, null: false, default: fragment("'[]'::jsonb")`. Use the existing migration timestamp scheme (`YYYYMMDDHHMMSS`).
- [X] T006 Run `mix ecto.migrate` and verify the column exists (one-line `psql` query or `mix ecto.dump`).
- [X] T007 [P] Add `field :behaviors, {:array, :map}, default: []` to `lib/agenticrealms/world/schemas/object.ex`.
- [X] T008 [P] Add `behaviors: []` default field to the defstruct in `lib/agenticrealms/world/commands/place_object.ex` (NOT in `@enforce_keys` — backward compat).
- [X] T009 [P] Add `behaviors: []` default field to the defstruct in `lib/agenticrealms/world/events/object_placed_in_room.ex` (NOT in `@enforce_keys`).
- [X] T010 Extend the dispatch path that produces `ObjectPlacedInRoom` (locate via `grep` of `PlaceObject` in `lib/agenticrealms/world/`) so that `behaviors` from the command is carried into the event payload. If an aggregate exists for objects/rooms-with-objects, update its `execute/2` clause to pass `behaviors` through; otherwise update the direct dispatcher.
- [X] T011 Extend `lib/agenticrealms/world/projections/world_projector.ex` `handle/2` clause for `%ObjectPlacedInRoom{...}` to include `behaviors: behaviors || []` in the `Repo.insert!/2` keyword list.
- [X] T012 In `lib/agenticrealms/application.ex`, extend `@_behavior_atoms` to include `:interval_ms` so the atom is pre-declared at compile time for the EventStore's `keys: :atoms!` deserialization path. (The atom-table-existence trick from features 009/010.)

### Backward-compat replay test

- [X] T013 Create `test/agenticrealms/world/projections/world_projector_object_replay_test.exs` that synthesizes an old-shape `ObjectPlacedInRoom` event (no `behaviors` field) and asserts the projector inserts an `Object` with `behaviors == []`. Mirrors the feature 010 `world_projector_npc_replay_test.exs` `lore` backward-compat test.

### Validator extension

- [X] T014 In `lib/agenticrealms/world/behaviors/validator.ex`, update `@valid_triggers` to include `"tick"` and add a `validate_tick_interval/1` private helper that runs when `trigger == "tick"`. It MUST validate `interval_ms` per FR-005 / Q5: present, integer, positive, positive multiple of the base rate (read from `Application.get_env(:agenticrealms, AgenticRealms.World.Ticks, [])[:base_tick_rate_ms] || 1_000`). Failure shapes per contracts/validator.md.
- [X] T015 Extend `test/agenticrealms/world/behaviors/validator_test.exs` with cases for: valid tick behavior; missing `interval_ms`; null `interval_ms`; string `interval_ms`; float `interval_ms`; zero/negative; non-multiple of base. Each invalid case asserts the specific `:reason` atom per contracts/validator.md.

### UIEvent extensions

- [X] T016 [P] In `lib/agenticrealms/world/ui_events.ex`, extend `RoomPlayerArrived` defstruct to include `carried_object_ids: []` (NOT in `@enforce_keys`). Add the field to the existing module's defstruct line, after the existing fields.
- [X] T017 [P] In `lib/agenticrealms/world/ui_events.ex`, extend `RoomPlayerLeft` defstruct to include `carried_object_ids: []` (NOT in `@enforce_keys`).
- [X] T018 [P] Add a new `AgenticRealms.World.UIEvents.RoomNPCLeft` module in `lib/agenticrealms/world/ui_events.ex` per contracts/events.md: keys `:room_id, :npc_id, :npc_name` (all `@enforce_keys`).

### Emit `carried_object_ids` from movement code

- [X] T019 Locate every site that emits `RoomPlayerArrived` and `RoomPlayerLeft` (grep `lib/` for the struct names). Update each emission to populate `carried_object_ids` from `AgenticRealms.World.Queries.list_inventory(actor_id) |> Enum.map(& &1.id)`. Typical site: `lib/agenticrealms_web/live/game_live.ex` in the move handler; possibly also in a movement command/projection path.
- [X] T020 [P] Add a unit test or update an existing test in `test/agenticrealms_web/live/game_live_*_test.exs` to assert that a `RoomPlayerArrived` / `RoomPlayerLeft` broadcast after a move carries the player's inventory ids in `carried_object_ids`. (If a focused integration test for movement doesn't exist, add one in `test/agenticrealms/world/queries_test.exs` style as a unit on the emission helper.)

### Cluster supervision tree

- [X] T021 Create `lib/agenticrealms/world/ticks/registry.ex` per contracts/registry.md — `Horde.Registry` wrapper with `via_tuple/1` and `lookup/1` helpers.
- [X] T022 Create `lib/agenticrealms/world/ticks/supervisor.ex` per contracts/registry.md — `Horde.DynamicSupervisor` wrapper with `find_or_start/1`.
- [X] T023 Create `lib/agenticrealms/world/ticks/lifecycle.ex` SHELL per contracts/lifecycle.md: GenServer with init that reads grace-period config and subscribes to `Phoenix.Presence` topic. The full event-handler clauses are added in the per-US phases below. For Phase 2, only `init/1` + `:get_state` handle_call are required (sufficient to bring the process up under the supervision tree).
- [X] T024 Update `lib/agenticrealms/application.ex` `start/2` to include the three new children in the supervision tree (siblings of feature-010's `NPCChat.*` triad): `AgenticRealms.World.Ticks.Registry`, `AgenticRealms.World.Ticks.Supervisor`, `AgenticRealms.World.Ticks.Lifecycle`.

### ActionExecutor recipient fanout for tick (R-007)

- [X] T025 In `lib/agenticrealms/world/behaviors/action_executor.ex`, audit the `execute/4` clauses. For room-speaker `:say` actions, when `triggering_player_id` is `nil` (tick-driven), the recipients MUST be ALL live occupants of `room_id` — not just one player. Add this branch. The existing `triggering_player_id`-is-an-integer branch (event-driven) stays unchanged. Add a small private helper `live_occupants_of/1` that calls into `Queries.live_occupants_of/1` (added below in T026).
- [X] T026 [P] In `lib/agenticrealms/world/queries.ex`: (a) promote `list_objects_in_room/1` from private to public (used by `Scope`); (b) add `live_occupants_of/1` — returns the list of player ids whose `current_room_id == room_id` AND who appear in `Phoenix.Presence`'s online set (reuse the existing online filter from feature 003b); (c) add `list_carried_objects_in_room/1` — returns objects held by any player whose `current_room_id == room_id` (regardless of online status — the scheduler caller filters further).
- [X] T027 [P] Add tests for the three new/promoted Queries helpers in `test/agenticrealms/world/queries_test.exs` (or wherever existing queries tests live): each returns the expected set under representative fixtures.

### Foundational test for the new structs

- [X] T028 [P] Add a small unit test to `test/agenticrealms/world/ui_events_test.exs` (create if missing) asserting: `RoomPlayerArrived` and `RoomPlayerLeft` accept the new `carried_object_ids` field with default `[]`; `RoomNPCLeft` requires all three keys.

---

## Phase 3: User Story 1 — A room comes alive when a player enters (P1)

**Story goal**: A player enters a previously empty room; after the join grace period, the room's `tick` behaviors begin firing on schedule.

**Independent test**: From a fresh login, the player walks into a room with at least one `tick`-triggered room behavior. After `join_grace_ms + interval_ms`, the first action is delivered to the player. Subsequent ticks fire at the configured cadence.

### Scheduler core (MVP slice)

- [X] T029 [P] [US1] Create `lib/agenticrealms/world/ticks/scope.ex` per contracts/scope.md. Implement `compute/1` (returns room behaviors only for this story; NPC + object scope is added in US4 per their tasks — but include the function stubs `add_npc/2`, `remove_npc/2`, `add_carried_object/3`, `remove_carried_object/3`, `add_in_room_object/2`, `remove_in_room_object/2` so US4 can fill them out without API drift). Sorting per FR-008a.
- [X] T030 [US1] Create `lib/agenticrealms/world/ticks/scheduler.ex` per contracts/scheduler.md — the `use GenServer` module:
  - `start_link/1` accepting `room_id`, registered via `Registry.via_tuple(room_id)`.
  - `init/1`: read config; subscribe to `room_topic(room_id)`; call `Scope.compute(room_id)`; populate `live_occupants` via `Queries.live_occupants_of(room_id)`; set `scheduler_start_time`; schedule first `:beat` via `Process.send_after`.
  - `handle_info(:beat, state)`: compute `due` via `filter_due/4`; sort per FR-008a; for each due entry, synchronously dispatch its actions via `Behaviors.ActionExecutor.execute(speaker_ctx, action, room_id, nil)`; update `last_fire[key] = now`; re-arm next beat.
  - `handle_call(:get_state, _, state)` returns state for tests.
  - `handle_call(:refresh, _, state)` recomputes `in_scope` via `Scope.compute/1`.
- [X] T031 [US1] In `lib/agenticrealms/world/ticks/lifecycle.ex`, implement the 0 → ≥1 detection path: handle `%{event: "presence_diff", payload: ...}` from the global `connected_players` topic, plus `%RoomPlayerArrived{}`. Update `live_per_room` and call `occupancy_changed/2` (internal helper per contracts/lifecycle.md). For 0 → ≥1: schedule a `{:start_scheduler, room_id}` self-message via `Process.send_after(self(), ..., join_grace_ms)`. Handle the self-message by calling `RoomTicks.Supervisor.find_or_start(room_id)` after re-checking live count.
- [X] T032 [US1] Update `lib/agenticrealms/world/seed.ex` to add a `tick`-triggered room behavior to the Stone Atrium (e.g., a periodic atmospheric narration line at a 1-second interval for fast demonstration; or a longer interval if desired). Use `validate_behaviors!/2` to confirm the seed's tick behaviors pass the extended validator.

### Tests for US1

- [X] T033 [P] [US1] Create `test/agenticrealms/world/ticks/registry_test.exs` per contracts/registry.md test surface: `via_tuple/1` shape; `lookup/1` empty + populated; `find_or_start/1` idempotent.
- [X] T034 [P] [US1] Create `test/agenticrealms/world/ticks/scope_test.exs` per contracts/scope.md test surface for room-only scope: `compute/1` returns only `trigger == "tick"` entries from the room's behaviors; empty list for a room without tick behaviors; correct FR-008a sorting.
- [X] T035 [US1] Create `test/agenticrealms/world/ticks/scheduler_test.exs` with US1 cases: scheduler starts; first beat after `init` fires no behavior because no interval has elapsed; second beat fires a 1-base-rate behavior; sequence of N beats fires the behavior approximately N-1 times (one less due to the start-grace). Uses `start_supervised(Scheduler)` bypassing the registry for unit-test isolation, or `Registry.via_tuple/1` directly via a private start helper.
- [X] T036 [US1] Create `test/agenticrealms/world/ticks/lifecycle_test.exs` with US1 cases: starts with empty state; on a synthesized `RoomPlayerArrived` event, schedules the join-grace timer; after `join_grace_ms`, the scheduler IS registered (via `RoomTicks.Registry.lookup/1` returning `{:ok, pid}`). Tests use a short `join_grace_ms` override (the test config default of 10 ms).

---

## Phase 4: User Story 2 — A room goes quiet when the last player leaves (P1)

**Story goal**: After the last player leaves, the scheduler stops after the leave grace; re-entry within grace preserves the schedule.

**Independent test**: Enter, observe ticks, leave, wait `leave_grace_ms + base_tick_rate_ms`, confirm no further ticks. Re-enter within the grace window and confirm the schedule continues uninterrupted.

- [X] T037 [US2] Extend `lib/agenticrealms/world/ticks/lifecycle.ex` to implement the ≥1 → 0 detection path: handle `%RoomPlayerLeft{}` and presence-diff leave entries; update `live_per_room`; if count drops to 0, schedule a `{:stop_scheduler, room_id}` self-message via `Process.send_after(self(), ..., leave_grace_ms)`. Handle the self-message by re-checking count and, if still 0, calling `Horde.DynamicSupervisor.terminate_child(RoomTicks.Supervisor, pid)`. Re-occupancy within grace MUST cancel the pending `:stop_scheduler` timer — implement `cancel_timer` in the helper.
- [X] T038 [US2] Extend `lib/agenticrealms/world/ticks/scheduler.ex` to handle `%RoomPlayerLeft{}` — update `live_occupants`. Scheduler does NOT self-terminate; lifecycle owns teardown.
- [X] T039 [P] [US2] Extend `test/agenticrealms/world/ticks/lifecycle_test.exs` with: ≥1 → 0 transition schedules a `:stop_scheduler` timer; after `leave_grace_ms`, scheduler is terminated (registry lookup returns `:error`). Re-entry within grace cancels the timer and scheduler stays alive (lookup still returns `{:ok, pid}` after re-entry and after the original grace would have expired). Re-entry AFTER grace expires results in a fresh scheduler (start_time is later than the original).
- [X] T040 [P] [US2] Extend `test/agenticrealms/world/ticks/scheduler_test.exs` with: while occupants present, ticks fire; after Lifecycle terminates the scheduler, no further beats are observed (process is dead per `Process.alive?/1`).

---

## Phase 5: User Story 3 — Per-behavior interval semantics (P2)

**Story goal**: A behavior with an N-second interval (N a positive multiple of the base rate) fires every N seconds, drift-free, and multiple behaviors at different intervals on the same room don't drift together.

**Independent test**: Two tick behaviors, one at 3× base and one at 5× base, both on the same room. Over a window long enough for the LCM of intervals, each fires at its expected count within tolerance.

- [X] T041 [US3] In `lib/agenticrealms/world/ticks/scheduler.ex`, confirm/refine the cadence anchor per FR-008 / Q3: `next_fire = last_fire + interval_ms`. Already implemented in T030, but this task is the formal verification + comments explicitly naming the anchor as "last-fire-time-based, drift-free." Add the `inflight` MapSet field to state for FR-010 (skip-stale) — even though MVP actions are synchronous, the structure is in place.
- [X] T042 [US3] In `lib/agenticrealms/world/ticks/scheduler.ex`, refine the due-set sorting per FR-008a to include both the cross-target order (room → npc → object) AND the within-target authored order (`behavior_index` ascending). The sort comparator should be a stable tuple sort.
- [X] T043 [P] [US3] Extend `test/agenticrealms/world/ticks/scheduler_test.exs` with cadence tests:
  - A 1-base-rate behavior fires every base beat after the first (within tolerance).
  - A 3-base-rate behavior fires once per 3 base beats (counted across a window of ~10 beats).
  - Two behaviors at different intervals on the same scheduler: each fires on its own cadence (asserted by counting fires of each over a window).
  - Drift-free check: across 10 fires of a 2-base-rate behavior, consecutive fire-timestamps differ by `2 * base_rate ± dispatch_tolerance` (≤ 20 ms).
- [X] T044 [P] [US3] Extend `test/agenticrealms/world/ticks/scheduler_test.exs` with ordering tests: a room with two behaviors of the same interval fires in the order they appear in the `behaviors` list (FR-008a within-target). Across different target kinds at the same interval, fire order is room → NPC → object.
- [X] T045 [P] [US3] Extend `test/agenticrealms/world/behaviors/validator_test.exs` (already extended in T015) with a base-rate-aware test: temporarily override the test base rate (via `Application.put_env`); a behavior with `interval_ms = 750` is rejected when base is 1000 but accepted when base is 250; an `on_exit` restores the original config.

---

## Phase 6: User Story 4 — NPC + object tick behaviors driven by room timer (P2)

**Story goal**: The room scheduler drives tick behaviors on (a) the room itself, (b) NPCs in the room, (c) objects in the room, and (d) objects carried by any live occupant. Carry/drop/move-room transfers behaviors between schedulers atomically.

**Independent test**: An NPC in the room ticks; an object in the room ticks; pick up the object → continues ticking (same room); move north with the object → ticks stop in the old room and start in the new room.

### Scope completion (NPCs + objects)

- [X] T046 [US4] In `lib/agenticrealms/world/ticks/scope.ex`, complete `compute/1` to include: NPC behaviors (via `Queries.list_npc_clones_in_room_with_behaviors/1`), in-room object behaviors (via `Queries.list_objects_in_room/1`), and carried-object behaviors (via `Queries.list_carried_objects_in_room/1` filtered to objects held by live occupants). All filtered to `trigger == "tick"`. Re-sort per FR-008a.
- [X] T047 [US4] In `lib/agenticrealms/world/ticks/scope.ex`, implement the incremental update helpers: `add_npc/2`, `remove_npc/2`, `add_carried_object/3`, `remove_carried_object/3`, `add_in_room_object/2`, `remove_in_room_object/2`. Each is a pure list operation (plus, for `add_*` variants, a single DB query for the target's `behaviors`).

### Scheduler event handlers

- [X] T048 [US4] In `lib/agenticrealms/world/ticks/scheduler.ex`, add handle_info clauses for: `%RoomNPCArrived{}` (calls `Scope.add_npc/2`), `%RoomNPCLeft{}` (calls `Scope.remove_npc/2` and drops the NPC's `last_fire` entries), and the carry/move-room cases on `%RoomPlayerArrived{carried_object_ids: ids}` / `%RoomPlayerLeft{carried_object_ids: ids}` (calls `Scope.add_carried_object/3` / `Scope.remove_carried_object/3` for each id in the list).
- [X] T049 [P] [US4] Update seed `lib/agenticrealms/world/seed.ex` to (a) add a `tick`-triggered emote/say behavior to Garrick's blueprint (so it's inherited by his clone) and (b) place a ticking object in the Stone Atrium (e.g., the existing brass lantern or a new "flickering oil lamp"). The behavior validator must accept all three (room + NPC + object) tick behaviors.

### Tests for US4

- [X] T050 [P] [US4] Extend `test/agenticrealms/world/ticks/scope_test.exs` with the NPC + object cases: `compute/1` includes an NPC's tick behaviors when the clone is in the room; excludes NPCs in different rooms; includes in-room object behaviors; includes carried-object behaviors when the carrier's `current_room_id == room_id`; excludes carried-object behaviors when carrier is offline or in another room.
- [X] T051 [US4] Extend `test/agenticrealms/world/ticks/scheduler_test.exs` with:
  - An NPC with a tick behavior in the room → its action fires on schedule.
  - An object in the room with a tick behavior → its action fires on schedule.
  - A `%RoomNPCLeft{}` event removes the NPC's behaviors from scope (subsequent beats don't fire them).
  - A `%RoomPlayerLeft{carried_object_ids: [obj_id]}` event removes the carried object's behaviors from scope.
  - A `%RoomPlayerArrived{carried_object_ids: [obj_id]}` event adds them.

---

## Phase 7: User Story 5 — Operator-tunable base tick rate (P3)

**Story goal**: An operator changing `base_tick_rate_ms` in config and restarting the system results in tick cadence at the new rate; authored intervals must remain valid multiples.

**Independent test**: Override `base_tick_rate_ms: 100` in test config (or in a dev session); a 300 ms-interval behavior fires every 300 ms. A behavior authored at 50 ms is rejected by the validator (50 is not a multiple of 100).

- [X] T052 [US5] Validate that the existing Application config block from T003 is read by both the Validator (T014) and the Scheduler (T030/T041) at runtime (not at compile time) — write a test asserting that two consecutive validator calls under different `Application.put_env(..., base_tick_rate_ms: ...)` settings yield different validation outcomes for the same input.
- [X] T053 [P] [US5] Add to `test/agenticrealms/world/ticks/scheduler_test.exs`: with `Application.put_env(:agenticrealms, AgenticRealms.World.Ticks, base_tick_rate_ms: 100)` for the test scope, a 100-ms interval behavior fires approximately 10 times in a 1-second window (within tolerance). `on_exit` restores the original config.
- [X] T054 [P] [US5] Add a `quickstart` note (already present in `quickstart.md` step 10) — no code change needed for this task; it's the documentation verification step.

---

## Phase 8: Polish & Cross-Cutting

**Purpose**: Integration test, lint, format, manual smoke.

### Integration test (US1–US5 end-to-end)

- [X] T055 Create `test/agenticrealms_web/live/game_live_ticks_test.exs` tagged `@moduletag :integration` as a single comprehensive test covering US1–US5 in sequence. With the test-config base rate of 50 ms and 10 ms join grace, the test should run in well under a second per US.
  - **US1**: Alice mounts; within `join_grace + base_rate` (~60 ms), the first room tick fires; `:room_speech` log entry asserted in Alice's rendered HTML.
  - **US2**: Alice moves to a different room; after `leave_grace_ms` (50 ms in tests), the original room's scheduler is terminated (`Registry.lookup` returns `:error`).
  - **US3**: Two behaviors at different intervals on the same room — both fire on their own cadence over a 500 ms observation window.
  - **US4**: An NPC's tick behavior fires; an object's tick behavior fires; carrying the object through a move re-routes the ticks to the new room's scheduler.
  - **US5**: `Application.put_env` change to `base_tick_rate_ms` results in observably different cadence (within the test's lifecycle).

### Quality gates

- [X] T056 [P] Run `mix format --check-formatted` and resolve any formatting drift.
- [X] T057 [P] Run `mix compile --warnings-as-errors` and resolve any new warnings.
- [X] T058 [P] Run `mix test` (default, excludes `:integration`) and confirm all tests pass.
- [X] T059 [P] Run `mix test --include integration test/agenticrealms_web/live/game_live_ticks_test.exs` and confirm the integration test passes.

### Documentation

- [X] T060 Add module @moduledoc to each new file under `lib/agenticrealms/world/ticks/` and `lib/agenticrealms/world/ui_events.ex` additions; reference `specs/011-room-tick-timers/` and the relevant FR(s). Mirror the docstring style established in features 009/010.
- [X] T061 [P] Add a `Logger.debug` line in `Scheduler.handle_info(:beat, ...)` when at least one behavior fires that beat ("scheduler #{room_id}: fired N behaviors on beat #{beat_count}"); add a `Logger.debug` in `Lifecycle.{start,stop}_scheduler` when a scheduler is started or terminated. Supports operator visibility during US3/US5 verification.

### Manual smoke

- [X] T062 Execute the `specs/011-room-tick-timers/quickstart.md` walkthrough on a clean `mix ecto.reset` + `mix phx.server`. Confirm steps 1–9 produce the expected log entries and timing. Record any deviations as new tasks.

---

## Dependencies

```text
Setup (Phase 1) — T001–T004
       │
       ▼
Foundational (Phase 2) — T005–T028
       │
       ▼
US1 (Phase 3) — T029–T036       ←──── MVP slice (room ticks + 0→1 lifecycle)
       │
       ▼
US2 (Phase 4) — T037–T040       ←──── leave grace + teardown
       │
       ▼
US3 (Phase 5) — T041–T045       ←──── per-behavior cadence + ordering
       │
       ▼
US4 (Phase 6) — T046–T051       ←──── NPC + object + carry/drop scope
       │
       ▼
US5 (Phase 7) — T052–T054       ←──── operator-tunable base rate
       │
       ▼
Polish (Phase 8) — T055–T062
```

**Cross-story dependencies**:

- US2 depends on US1's scheduler + lifecycle being in place (extends both).
- US3 depends on the scheduler having a beat loop (US1) — adds cadence/ordering tests + minor refinements.
- US4 depends on the scope module (US1 created with stubs) — fills in the NPC/object/carried-object paths.
- US5 depends on the validator (Phase 2) and the scheduler (US1) being configurable — verifies via test-config overrides.
- Polish depends on everything.

**Within-phase dependencies**:

- T006 must run after T005 (migration must exist before it can be applied).
- T010, T011 must wait for T008, T009 (event/command extended fields).
- T012 can run in parallel with T007–T011.
- T014 must complete before T015 (test depends on the extended validator).
- T021, T022, T023 (registry/supervisor/lifecycle shells) can run in parallel.
- T024 depends on T021–T023 (must register the three children).
- T025 depends on T026 (`live_occupants_of/1` must exist for ActionExecutor to use).
- T029 (scope) depends on T026 (queries).
- T030 (scheduler) depends on T029 (scope) + T025 (action executor fanout).
- T031 (lifecycle 0→1) depends on T030 + T022.
- T037 (lifecycle 1→0) depends on T031.
- T046, T047 (scope completion) depend on T029.
- T048 (scheduler event handlers for NPCs/objects) depends on T030 + T046/T047.

---

## Parallel Execution Examples

### Setup (Phase 1)

T001, T002, T003, T004 are all independent file additions — all parallel.

### Foundational (Phase 2)

After T005+T006 (migration applied):
- T007, T008, T009, T012 in parallel (independent file edits)
- T010, T011 sequential after T008/T009
- T013 (replay test) after T011
- T014 (validator) standalone; T015 (validator test) after T014
- T016, T017, T018 in parallel (UIEvent module edits)
- T019 (emit carried_object_ids) after T016, T017
- T020 (emission test) after T019
- T021, T022, T023 in parallel
- T024 (supervision tree) after T021–T023
- T025 (action executor) after T026; T026 standalone; T027 in parallel with T028

### US1 (Phase 3)

T029 (Scope), T032 (seed) can be parallel after Phase 2; T033, T034 in parallel after their respective implementations; T030 (Scheduler), T031 (Lifecycle 0→1), T035 (Scheduler test), T036 (Lifecycle test) sequential within the file but with parallel test files across.

### US3 (Phase 5)

T041, T042 are sequential edits to `scheduler.ex`; T043, T044, T045 are parallel test files.

### US4 (Phase 6)

T046, T047 are sequential within `scope.ex`; T048 in `scheduler.ex` depends on them; T049 (seed) parallel with the rest; T050, T051 are parallel test files.

### Polish (Phase 8)

T056, T057, T058 in parallel; T059 depends on T055; T060, T061 in parallel.

---

## Implementation Strategy

### MVP first

Phase 1 + Phase 2 + Phase 3 (US1). After 36 tasks the system supports:

- The Stone Atrium scheduler starts when a player arrives.
- Within `join_grace + interval`, the room's tick behavior fires.
- Subsequent ticks fire on schedule.
- Validator rejects malformed tick behaviors at load.

Ship this as a demonstrable slice. The remaining phases are layered refinements:

1. **+US2** — graceful teardown when the room empties.
2. **+US3** — multi-behavior cadence + FR-008a ordering verified by tests.
3. **+US4** — NPC + object ticks driven by the same room scheduler; carry/drop/move-room handoff.
4. **+US5** — operator-tunable base tick rate.

Then Polish wraps with the end-to-end integration test, format/compile/test gates, and a manual smoke run.

### Validation gates

- **After Phase 2**: `mix compile` clean; T013 replay test passes (backward compat); supervision tree starts cleanly (`iex -S mix` → `Process.whereis(AgenticRealms.World.Ticks.Lifecycle)` returns a pid).
- **After Phase 3 (US1)**: T035, T036 pass; manual `iex` test: a synthesized `RoomPlayerArrived` event produces a scheduler registration within `join_grace_ms`.
- **After Phase 4 (US2)**: T039, T040 pass; leave/re-entry grace behavior verified.
- **After Phase 5 (US3)**: T043, T044, T045 pass; cadence is drift-free.
- **After Phase 6 (US4)**: T050, T051 pass; NPC and object ticks fire; carry/move handoff works.
- **After Phase 7 (US5)**: T052, T053 pass; config-driven cadence changes are observable.
- **After Phase 8**: T055 integration test passes; quickstart smoke passes; format/compile/test gates green.
