---

description: "Task list for feature 009 — NPC and Room Behaviors (Triggers + Actions, Minimal Set)"
---

# Tasks: NPC and Room Behaviors

**Input**: Design documents from `/specs/009-npc-behaviors/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/*, quickstart.md (all present)

**Tests**: Included. The project uses ExUnit + Phoenix LiveView integration tests across every prior feature (003–008). Plan specifies six explicit test layers (Validator, Interpreter, aggregates, projector, queries, LiveView integration). Test tasks are written alongside their implementation tasks (repo convention since 003), not strict write-first-fail.

**Organization**: Grouped by user story. Because feature 009 is substrate-heavy, Phase 2 (Foundational) does most of the implementation work; the user-story phases primarily verify properties of that substrate by extending one comprehensive integration test in `game_live_behaviors_test.exs`.

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Maps the task to a user story (US1, US2, US3, US4, US5)
- File paths are absolute from the repo root.

## Path Conventions

Phoenix LiveView monolith. All paths are relative to `/Users/kevin/code/autodidaddict/agentic-realms/`.

```text
lib/agenticrealms/         # Domain code (aggregates, commands, events, projections, queries, schemas, behaviors)
lib/agenticrealms_web/     # Web + LiveView
priv/repo/migrations/      # Ecto migrations
test/agenticrealms/        # Domain unit tests
test/agenticrealms_web/    # LiveView integration tests
```

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Generate the migration file. The project is already initialized.

- [X] T001 Generate a new Ecto migration file via `mix ecto.gen.migration add_behaviors_columns` and confirm the timestamp-prefixed file appears under `priv/repo/migrations/` (path: `priv/repo/migrations/<timestamp>_add_behaviors_columns.exs`).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Build the full behavior substrate — schema columns, validator, interpreter, action executor, three extended events, two extended commands, two extended aggregates, three extended projector handlers, two queries, the UIEvent struct, the GameLive handlers, the render clauses, and the seed extensions. After this phase, fresh `mix event_store.reset && mix ecto.reset` produces a world where Garrick greets and bids farewell, and the Stone Atrium murmurs atmospheric narration.

**⚠️ CRITICAL**: No user-story phase can begin until this phase is complete. All US phases verify properties of THIS substrate.

- [X] T002 [P] Write the migration body in `priv/repo/migrations/<timestamp>_add_behaviors_columns.exs` per `specs/009-npc-behaviors/contracts/migration.md` (implicit from data-model.md §2) — add `behaviors :jsonb, null: false, default: fragment("'[]'::jsonb")` column to each of `npc_blueprints`, `npc_clones`, `world_rooms` tables. Use `alter table(...) do add ... end` blocks. Three columns, three default values, one migration.
- [X] T003 [P] Create `lib/agenticrealms/world/behaviors/validator.ex` defining `AgenticRealms.World.Behaviors.Validator` per `specs/009-npc-behaviors/contracts/validator.md` — `@valid_triggers ~w(player_entered player_left)`, `@max_say_text_length 500`, public `validate/1` that returns `:ok | {:error, atom_or_tuple}`. Validates the 7 rules in the contract: list at top level, map entries with `"trigger"` + `"actions"` keys, known trigger string, non-empty actions list, action maps with `"type"` key, `:say` action has non-empty text ≤500 chars, only `:say` actions accepted.
- [X] T004 [P] Extend `lib/agenticrealms/world/schemas/npc_blueprint.ex` — add `field :behaviors, {:array, :map}, default: []` to the schema block. No other changes.
- [X] T005 [P] Extend `lib/agenticrealms/world/schemas/npc_clone.ex` — add `field :behaviors, {:array, :map}, default: []` to the schema block.
- [X] T006 [P] Extend `lib/agenticrealms/world/schemas/room.ex` — add `field :behaviors, {:array, :map}, default: []` to the schema block.
- [X] T007 [P] Extend `lib/agenticrealms/world/commands/create_room.ex` — add `:behaviors` to `defstruct` with default `[]`. Do NOT add to `@enforce_keys` (so feature 003/008 callers continue to work).
- [X] T008 [P] Extend `lib/agenticrealms/world/commands/create_npc_blueprint.ex` — same pattern: add `:behaviors` to `defstruct` with default `[]`, not in `@enforce_keys`.
- [X] T009 [P] Extend `lib/agenticrealms/world/events/room_created.ex` per `contracts/events.md` — add `behaviors: []` to `defstruct` (between `description` and `version: 1`). NOT in `@enforce_keys`. Confirms backward-compat: feature 003/008 events deserialize with `behaviors: []`.
- [X] T010 [P] Extend `lib/agenticrealms/world/events/npc_blueprint_created.ex` — same pattern: add `behaviors: []` to `defstruct`.
- [X] T011 [P] Extend `lib/agenticrealms/world/events/npc_cloned_from_blueprint.ex` — same pattern: add `behaviors: []` to `defstruct`.
- [X] T012 [P] Add `BehaviorUtterance` defmodule in `lib/agenticrealms/world/ui_events.ex` per `contracts/ui_events.md` — `@enforce_keys [:kind, :text, :room_id, :triggering_player_id]`, `defstruct [:kind, :actor_name, :text, :room_id, :triggering_player_id]`. Place alongside the existing `RoomNPCArrived` / `RoomPlayerArrived` / `RoomUtterance` defmodules.
- [X] T013 Extend the `Room` aggregate at `lib/agenticrealms/world/room.ex` — (a) add `behaviors: []` to `defstruct`; (b) modify the `execute/2` clause for `%CreateRoom{}` to read `command.behaviors` and pass it through into the emitted `%RoomCreated{behaviors: command.behaviors}` event; (c) modify the `apply/2` clause for `%RoomCreated{}` to set `state.behaviors` from the event. Depends on T006, T007, T009.
- [X] T014 Extend the `NPCBlueprint` aggregate at `lib/agenticrealms/world/npc_blueprint.ex` — (a) add `behaviors: []` to `defstruct`; (b) modify `execute/2` for `%CreateNPCBlueprint{}` to pass `command.behaviors` through to the emitted `%NPCBlueprintCreated{behaviors: ...}` event; (c) modify `apply/2` for `%NPCBlueprintCreated{}` to set `state.behaviors`; (d) modify `execute/2` for `%SpawnNPCClone{}` to STAMP `state.behaviors` into the emitted `%NPCClonedFromBlueprint{behaviors: state.behaviors}` event (full-copy at clone time per FR-005 and feature 008 posture). Depends on T004, T008, T010, T011.
- [X] T015 Extend `lib/agenticrealms/world/projections/world_projector.ex` — modify three `handle/2` clauses to carry behaviors through to the read model: (a) `%RoomCreated{behaviors: behaviors}` → `Repo.insert!(%Room{..., behaviors: behaviors})`; (b) `%NPCBlueprintCreated{behaviors: behaviors}` → `Repo.insert!(%NPCBlueprint{..., behaviors: behaviors})`; (c) `%NPCClonedFromBlueprint{behaviors: behaviors}` → `Repo.insert!(%NPCClone{..., behaviors: behaviors})`. The legacy `NPCSpawnedInRoom` handler is UNCHANGED — it doesn't have behaviors, and the schema's default `[]` applies. Depends on T004, T005, T006, T009, T010, T011.
- [X] T016 Extend `lib/agenticrealms/world/queries.ex` per `contracts/queries.md` — add `get_room_behaviors/1` (returns `{:ok, [map()]} | {:error, :no_such_room}`) and `list_npc_clones_in_room_with_behaviors/1` (returns list of `%{id, name, serial, behaviors}` ordered by `serial`). Use the existing `Room` and `NPCClone` schema aliases.
- [X] T017 Create `lib/agenticrealms/world/behaviors/action_executor.ex` defining `AgenticRealms.World.Behaviors.ActionExecutor` per `contracts/ui_events.md` — `execute/4` takes `speaker_ctx ∈ [{:room, room_id}, {:npc_clone, %{name: ...}}]`, an action map, room_id, and triggering_player_id. For `%{"type" => "say", "text" => text}`: builds a `%BehaviorUtterance{}` with `:npc_speech` or `:room_speech` kind based on speaker_ctx, computes recipient set per the rules in `contracts/ui_events.md` (`:room_speech` to triggering player only; `:npc_speech` to triggering player + other occupants from `Queries.other_occupants_of/2`), broadcasts on each recipient's player_topic. Fallback clauses (unknown action type, malformed map) log and skip. Depends on T012.
- [X] T018 Create `lib/agenticrealms/world/behaviors/interpreter.ex` defining `AgenticRealms.World.Behaviors.Interpreter` Commanded event handler per `contracts/interpreter.md` — `use Commanded.Event.Handler` with `application: AgenticRealms.World.Application`, `name: __MODULE__`, `start_from: :current`, `consistency: :strong`. Two `handle/2` clauses: `%PlayerSpawned{}` (fires `player_entered` in `room_id`) and `%PlayerMoved{}` (fires `player_left` in `from_room_id`, then `player_entered` in `to_room_id`). Private `fire_room_then_npcs/3` walks the room behaviors first, then the NPC clones ordered by serial, and calls `ActionExecutor.execute/4` for each matching action. Depends on T016, T017.
- [X] T019 Register the `Behaviors.Interpreter` as a Commanded event handler in the application supervision tree. Inspect `lib/agenticrealms/world/application.ex` or `lib/agenticrealms/application.ex` to find where `WorldProjector` and `UIEventBroadcaster` are registered; add `Behaviors.Interpreter` to the same supervisor child list. The handler starts during application boot and subscribes from `start_from: :current` (replay-safe per FR-016a). Depends on T018.
- [X] T020 Extend `lib/agenticrealms_web/live/game_live.ex` per `contracts/ui_events.md` — add `BehaviorUtterance` to the existing `alias AgenticRealms.World.UIEvents.{...}` block; add two new `handle_info/2` clauses for `%BehaviorUtterance{kind: :npc_speech}` and `%BehaviorUtterance{kind: :room_speech}` that append the appropriate log entry to `socket.assigns.log`. Place alongside the existing `RoomUtterance` handlers for visual symmetry. Depends on T012.
- [X] T021 Extend `lib/agenticrealms_web/components/game_components.ex` per `contracts/render.md` — add two new `log_entry/1` clauses: one for `kind: :npc_speech` (renders `<div class="log-entry speech speech-npc"><span class="who">{@entry.actor_name}</span> says, &ldquo;{@entry.text}&rdquo;</div>`) and one for `kind: :room_speech` (renders `<div class="log-entry narrate narrate-room">{@entry.text}</div>` — NO attribution). Place alongside the existing `:speech` and `:narrate` clauses.
- [X] T022 Extend `lib/agenticrealms/world/seed.ex` per `contracts/seed.md` — (a) add `alias AgenticRealms.World.Behaviors.Validator`; (b) define `garrick_behaviors` and `atrium_behaviors` module attributes (or local variables in `do_seed/0`) containing the seeded behavior lists; (c) call `Behaviors.Validator.validate/1` on each before dispatch (raise on `{:error, _}`); (d) extend the `CreateRoom` dispatch for the Stone Atrium with `behaviors: @atrium_behaviors`; (e) extend the `CreateNPCBlueprint` dispatch for Garrick with `behaviors: @garrick_behaviors`. All other CreateRoom dispatches (Corridor, Library) are unchanged. Depends on T003, T007, T008.
- [X] T023 [P] Write unit tests in `test/agenticrealms/world/behaviors/validator_test.exs` covering each validation rule from `contracts/validator.md` — happy paths (empty list, single behavior, multi-behavior), unknown trigger, unknown action type, empty/nil text, over-cap text, missing actions key, actions not a list, empty actions, malformed action map, non-list input. Depends on T003.
- [X] T024 [P] Extend `test/agenticrealms/world/room_test.exs` with one new test in a new `describe "behaviors (feature 009)"` block: dispatch a `%CreateRoom{room_id, name, description, behaviors: [...]}` against an uninitialized Room aggregate and assert the emitted `%RoomCreated{}` carries the behaviors; apply the event and assert `state.behaviors == [...]`. Depends on T013.
- [X] T025 [P] Extend `test/agenticrealms/world/npc_blueprint_test.exs` with two new tests in a new `describe "behaviors (feature 009)"` block: (a) `CreateNPCBlueprint` with behaviors propagates them through to the emitted event and into aggregate state; (b) `SpawnNPCClone` on a blueprint with behaviors stamps `state.behaviors` into the emitted `%NPCClonedFromBlueprint{}` event payload (full-copy verification — change `state.behaviors` to a known list, dispatch SpawnNPCClone, assert event.behaviors == the list). Depends on T014.
- [X] T026 [P] Extend `test/agenticrealms/world/projections/world_projector_npc_replay_test.exs` with new tests verifying the `behaviors` field is populated correctly: (a) `handle(%RoomCreated{behaviors: behaviors})` inserts a `world_rooms` row with `behaviors: behaviors`; (b) `handle(%NPCBlueprintCreated{behaviors: behaviors})` inserts a blueprint row with the behaviors; (c) `handle(%NPCClonedFromBlueprint{behaviors: behaviors})` inserts a clone row with the behaviors; (d) `handle(%NPCSpawnedInRoom{})` (the legacy event) inserts with `behaviors: []` defaulted. Depends on T015.
- [X] T027 [P] Write unit tests in `test/agenticrealms/world/behaviors/interpreter_test.exs` per `contracts/interpreter.md` "Test surface" section — direct `Interpreter.handle/2` invocation tests covering: (a) empty behaviors in room + empty NPC behaviors → no broadcasts; (b) room-only `player_entered` behavior → single `:room_speech` to triggering player only (verified by subscribing to test-player's player_topic AND another player's player_topic, assert only the triggering player receives it); (c) NPC-only behavior → `:npc_speech` to triggering player + other room occupants; (d) room + NPC both with `player_entered` behaviors → room speech BEFORE NPC speech (FR-008a); (e) multi-behavior list on same trigger → all fire in order; (f) multi-action behavior → all actions in order; (g) `player_left` in source room → leaving player explicitly receives `:npc_speech` farewell; (h) non-matching trigger → no firing; (i) multiple NPC clones with different serials → fire in serial order. Setup: insert rooms/clones via `Repo.insert!` to bypass Commanded; subscribe to player_topics via `Phoenix.PubSub.subscribe`; use `assert_receive` for delivery assertions. Depends on T018.

**Checkpoint**: At the end of Phase 2, `mix event_store.reset && mix ecto.reset` produces a world where Garrick greets/farewells and the Stone Atrium murmurs. All unit tests pass. The substrate is shippable; the user-story phases verify specific player-facing properties.

---

## Phase 3: User Story 1 - NPC greets a player who enters its room (Priority: P1) 🎯 MVP

**Goal**: A fresh player who logs in and arrives in the Stone Atrium sees Garrick's greeting (`Garrick the Innkeeper says, "Welcome to the Stone Atrium."`) appear in their narrative log within 200ms of arrival.

**Independent Test**: From a fresh `mix event_store.reset && mix ecto.reset`, log in via the LiveView and verify the rendered HTML contains the `:npc_speech` log entry with Garrick's display name and the seeded text.

- [X] T028 [US1] Create `test/agenticrealms_web/live/game_live_behaviors_test.exs` as a new integration test file. Pattern follows `game_live_npc_test.exs`: `use AgenticRealmsWeb.ConnCase, async: false`; `@moduletag :integration`; `setup` block dispatches `Seed.run/0` (try/rescue MatchError → :already_seeded), registers Alice + Bob players, spawns both into the starting room. The single test function (`"behaviors — US1, US2, US3, US4, US5 in sequence"`) asserts Story 1 first: after Alice mounts the LiveView, the rendered HTML contains `class="log-entry speech speech-npc"` AND `<span class="who">Garrick the Innkeeper</span>` AND the text `Welcome to the Stone Atrium.` AND NO occurrence of `Garrick the Innkeeper#\d+` (FR-011 leak check). Depends on T020, T021, T022.

**Checkpoint**: US1 is complete. Garrick greets fresh players on arrival.

---

## Phase 4: User Story 2 - NPC says goodbye when a player leaves its room (Priority: P1)

**Goal**: When a player leaves a room containing an NPC with a `player_left → say` behavior, the player's log includes the NPC's farewell speech entry. Players staying in the source room also see the entry (NPC speech follows feature 004 say semantics).

**Independent Test**: With Alice in the Stone Atrium, submit `go north`. Alice's log MUST include `Garrick the Innkeeper says, "Farewell, traveler."` Bob (still in the Atrium) MUST also see the farewell.

- [X] T029 [US2] Extend the integration test in `test/agenticrealms_web/live/game_live_behaviors_test.exs` with Story 2 assertions: have Alice submit `go north`; flush; assert Alice's rendered HTML now contains a `:npc_speech` entry with Garrick's farewell text. Bob's rendered HTML (in the same browser session, mounted separately in setup) MUST also contain Garrick's farewell entry — verifying the leaving player AND the stayer both receive `:npc_speech`. Depends on T028.

**Checkpoint**: US2 is complete. The full-copy behavior set on Garrick's clone fires for both arrival and departure.

---

## Phase 5: User Story 3 - Room emits atmospheric narration on player arrival (Priority: P2)

**Goal**: The Stone Atrium's `player_entered → say "The cool air carries the scent of rain."` behavior fires for the arriving player ONLY (no other players in the room see the room narration). The rendered entry has NO speaker attribution — just the line, italicized as ambient narration.

**Independent Test**: When a fresh player arrives in the Stone Atrium, the rendered HTML contains `class="log-entry narrate narrate-room"` with the atmospheric text and NO `<span class="who">`. When a SECOND player arrives later, the first player does NOT see the new narration (anti-spam).

- [X] T030 [US3] Extend the integration test with Story 3 assertions: (a) Alice's initial mount renders a `:room_speech` log entry with the seeded text and `class="log-entry narrate narrate-room"`; (b) the rendered entry does NOT contain `<span class="who">` (no attribution); (c) the entry does NOT contain `says,` or `&ldquo;` (no speech framing); (d) when Bob arrives in the same room (after Alice is already there), Bob's log gets the narration but Alice's log does NOT — assertion that the `:room_speech` count in Alice's rendered HTML stays at 1, not 2. Depends on T029.
- [X] T031 [US3] Verify the room-then-NPC ordering (FR-008a): inspect Alice's initial mount log and assert the `:room_speech` entry appears strictly BEFORE the `:npc_speech` entry in the HTML (e.g., the `narrate-room` substring's position is less than the `speech-npc` substring's position). Depends on T030.

**Checkpoint**: US3 is complete. Room narration fires for the triggering player only, in the correct order relative to NPC speech.

---

## Phase 6: User Story 4 - Multiple behaviors compose on the same trigger (Priority: P2)

**Goal**: When an entity has MULTIPLE behaviors on the same trigger (e.g., two separate `player_entered` behaviors on the same NPC clone), all fire in authored order when the trigger event occurs.

**Independent Test**: Directly mutate Garrick's clone row to add a second `player_entered` behavior. Trigger an arrival. Verify both speech entries appear in the player's log in authored order.

- [X] T032 [US4] Extend the integration test with Story 4 setup + assertions: (a) move Alice OUT of the Atrium (to the Corridor) to clear her session of greeting entries; (b) directly `Repo.update_all` Garrick's clone row to set behaviors to a list with TWO `player_entered` behaviors (`Welcome to the Stone Atrium.` and `Mind the loose flagstone by the door.`) plus the existing `player_left`; (c) move Alice back into the Atrium; (d) assert her log now contains BOTH greeting lines from Garrick in authored order. Depends on T029.

**Checkpoint**: US4 is complete. Multi-behavior composition validated.

---

## Phase 7: User Story 5 - Multiple actions inside one behavior compose in order (Priority: P3)

**Goal**: Within a single behavior, an action list with multiple `:say` actions fires all of them in order.

**Independent Test**: Directly mutate Garrick's clone row to set a `player_entered` behavior with a multi-action action list. Trigger an arrival. Verify all action outputs appear in authored order.

- [X] T033 [US5] Extend the integration test with Story 5 setup + assertions: (a) move Alice OUT again; (b) `Repo.update_all` Garrick's clone to have a single `player_entered` behavior with action list `[say "First line.", say "Second line."]`; (c) move Alice back in; (d) assert both lines appear in her log in authored order. Depends on T032.

**Checkpoint**: US5 is complete. Multi-action composition validated.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Final formatting, full test suite, manual quickstart walkthrough, FR-016 audit.

- [X] T034 Run `mix format` to normalize whitespace across every file touched by this feature.
- [X] T035 Run `mix test` and verify the full unit suite passes (244+ tests after feature 008, plus this feature's new tests). Pay attention to any flakes caused by the new `consistency: :strong` interpreter handler interacting with parallel-session tests.
- [X] T036 Run `mix test --include integration` per file individually (the project's parallel-integration-test sandbox issue from feature 007 remains; run each integration test file alone): the new `game_live_behaviors_test.exs`, plus the existing `game_live_npc_test.exs`, `game_live_examine_test.exs`, `game_live_communication_test.exs`, `game_live_intent_parser_test.exs`. All MUST pass.
- [X] T037 Run `mix event_store.reset && mix ecto.reset` and walk through `specs/009-npc-behaviors/quickstart.md` end-to-end manually — verify Stories 1–5 (Garrick greets, Garrick farewells, room narration with anti-spam, multi-behavior via IEx mutation, multi-action via IEx mutation), plus the negative tests (no `Behavior` substring in event-store event types, validator rejects malformed seed data).
- [X] T038 [P] FR-016 audit: from IEx with the running application, query the event store for any event whose type contains the substring `Behavior` — there MUST be zero. `EventStore.stream_all_forward() |> Enum.take(1000) |> Enum.map(& &1.event_type) |> Enum.filter(&String.contains?(&1, "Behavior")) |> assert_equal []`. This verifies the non-event-sourced posture from FR-016 holds in practice.

---

## Dependencies & Execution Order

### Phase dependencies

- **Phase 1 (Setup)** — T001 — no upstream dependencies.
- **Phase 2 (Foundational)** — T002–T027 — depends on T001. **Blocks all user-story phases.**
- **Phase 3 (US1)** — T028 — depends on Phase 2 complete (specifically the test setup needs the seed + integration test stack).
- **Phase 4 (US2)** — T029 — depends on T028.
- **Phase 5 (US3)** — T030, T031 — depend on T029.
- **Phase 6 (US4)** — T032 — depends on T029.
- **Phase 7 (US5)** — T033 — depends on T032.
- **Phase 8 (Polish)** — T034–T038 — depends on Phases 1–7.

### Within-phase dependencies

- **Foundational**: T002–T012 are all parallel (different files). T013 depends on T006, T007, T009. T014 depends on T004, T008, T010, T011. T015 depends on T004, T005, T006, T009, T010, T011. T016 depends on T004, T005, T006. T017 depends on T012. T018 depends on T016, T017. T019 depends on T018. T020 depends on T012. T021 standalone. T022 depends on T003, T007, T008. T023 depends on T003. T024 depends on T013. T025 depends on T014. T026 depends on T015. T027 depends on T018.
- **US phases**: each US task extends the same integration test file in sequence. T028 → T029 → T030 → T031 → T032 → T033 are strictly sequential within that file.

### Critical-path callout

The longest dependency chain is: T001 → T002 → T013 → T014 → T015 → T018 → T019 → T020 → T022 → T028 → T029 → T030 → T031 → T032 → T033 → T035 → T037. Most of Phase 2's parallel files short-circuit off this main spine.

### Parallel opportunities

- **Eleven parallel-safe edits/creations in Phase 2** (T002 migration, T003 validator, T004/T005/T006 schemas, T007/T008 commands, T009/T010/T011 events, T012 UIEvent struct). All distinct files; a team or eight parallel agents could ship them simultaneously.
- **Tests T023, T024, T025, T026, T027** are five parallel-safe test files in Phase 2 — different files, different scopes.

---

## Parallel Example: Foundational phase (Phase 2)

```bash
# Eleven workers in parallel after T001:
Task T002: Write migration body
Task T003: Create Behaviors.Validator
Task T004: Extend Schemas.NPCBlueprint with :behaviors field
Task T005: Extend Schemas.NPCClone with :behaviors field
Task T006: Extend Schemas.Room with :behaviors field
Task T007: Extend Commands.CreateRoom defstruct
Task T008: Extend Commands.CreateNPCBlueprint defstruct
Task T009: Extend Events.RoomCreated defstruct
Task T010: Extend Events.NPCBlueprintCreated defstruct
Task T011: Extend Events.NPCClonedFromBlueprint defstruct
Task T012: Add UIEvents.BehaviorUtterance struct

# Then T013–T022 land in dependency order (mostly serial).

# Five parallel tests at the end of Phase 2:
Task T023: Validator unit tests
Task T024: Room aggregate behavior tests
Task T025: NPCBlueprint aggregate behavior tests
Task T026: Projector behavior tests
Task T027: Interpreter unit tests
```

---

## Implementation Strategy

### MVP first (US1 only)

For a substrate-heavy refactor, the "MVP" is **the full Phase 2 + Phase 3** — the substrate plus the headline player-facing assertion (Garrick greets).

1. Phase 1: T001 (migration scaffold).
2. Phase 2: T002–T027 (the whole substrate).
3. Phase 3: T028 (Story 1 — Garrick greets fresh players).
4. **STOP and VALIDATE**: `mix event_store.reset && mix ecto.reset` + fresh login in browser → Garrick says welcome. The MVP demonstrates the entire trigger → action → broadcast → render pipeline.
5. Deploy / demo if ready.

Phases 4–7 add additional acceptance scenarios to the same integration test, exercising US2 (farewells), US3 (room narration + anti-spam), US4 (multi-behavior), US5 (multi-action). Each story's task extends the test file in sequence — they don't introduce new code paths.

### Incremental delivery

1. Phase 1 + Phase 2 → substrate ready (no observable player change yet — Garrick exists with behaviors but the integration test hasn't asserted them).
2. + Phase 3 (US1) → fresh login produces Garrick's greeting. Demo-worthy.
3. + Phase 4 (US2) → movement out produces Garrick's farewell.
4. + Phase 5 (US3) → room narration validated, anti-spam verified.
5. + Phase 6 (US4) → multi-behavior composition validated.
6. + Phase 7 (US5) → multi-action composition validated.
7. + Phase 8 → formatting, manual walkthrough, FR-016 audit.

### Parallel team strategy

With multiple developers, Phase 2 parallelizes broadly. After T001:
- One developer takes T002–T012 (mechanical extensions in parallel).
- Another takes T013–T015 (aggregate + projector wiring, sequential).
- Another takes T017–T019 (action executor, interpreter, supervisor registration, sequential).
- A fourth takes T016 + T020–T022 (queries, GameLive, render, seed).
- A fifth writes the test files T023–T027 in parallel.

Phase 3 onward is sequential (one integration test file, extended scenario by scenario).

---

## Notes

- **[P] markers** flag distinct-file, no-incomplete-dep parallelism. Where two tasks touch the same file but different functions, only the first is [P]; the second has implicit ordering by file share.
- **No new top-level module** at the project level — `World.Behaviors.*` lives under the existing `World` namespace.
- **Three extended events** carry behavior data through the event store. No new event types. Backward-compatible with feature 003/008 events via the `behaviors: []` default.
- **No new commands** — `CreateRoom` and `CreateNPCBlueprint` are extended with optional `:behaviors` fields.
- **`start_from: :current` on the interpreter** is the critical replay-safety knob. T018 must include this config explicitly; don't change it later.
- **Validator-at-seed-time** (T022) catches authoring bugs before they reach the event store. The interpreter trusts validated data at runtime.
- **Commit cadence**: after Phase 2 completes (the substrate lands), after each user-story phase completes, and after Phase 8. The git extension's `after_*` hooks surface auto-commit opportunities at each `/speckit-implement` boundary.
- **Deployment posture**: developers pulling this feature run `mix event_store.reset && mix ecto.reset` to rebuild the world with the new behavior-carrying events. Same workflow as feature 008. Documented in quickstart.md.
