---

description: "Task list for feature 007 — Static NPCs"
---

# Tasks: Static NPCs

**Input**: Design documents from `/specs/007-static-npcs/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/*, quickstart.md (all present)

**Tests**: Included. This codebase uses ExUnit for unit tests and Phoenix LiveView integration tests across every prior feature (003–006). The plan specifies six explicit test layers (Room aggregate, WorldProjector, Queries, Examine, Commands.take, LiveView). Test tasks below are written alongside their implementation tasks (the repo convention since 003), not strict write-first-fail.

**Organization**: Grouped by user story so each can be implemented and verified independently.

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Maps the task to a user story (US1, US2, US3, US4)
- File paths are absolute from the repo root.

## Path Conventions

Phoenix LiveView monolith. All paths are relative to `/Users/kevin/code/autodidaddict/agentic-realms/`.

```text
lib/agenticrealms/         # Domain code (aggregates, commands, events, projections, queries, schemas)
lib/agenticrealms_web/     # Web + LiveView
priv/repo/migrations/      # Ecto migrations
priv/intent_resolver/      # System prompt content
test/agenticrealms/        # Domain unit tests
test/agenticrealms_web/    # LiveView integration tests
```

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: One scaffolding task before foundational work begins. The project is already initialized — Elixir, Phoenix, Commanded, EventStore, Ecto, and the world bounded context are all in place from features 003–006.

- [X] T001 Generate a new Ecto migration file via `mix ecto.gen.migration create_world_npcs` and confirm the timestamp-prefixed file appears under `priv/repo/migrations/` (path: `priv/repo/migrations/<timestamp>_create_world_npcs.exs`).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Stand up the new `NPC` entity through the entire CQRS pipeline — schema, migration, command, event, aggregate handler, router registration, projector, and seed — so that subsequent user stories have a real read model to query against and a real spawn path to broadcast from.

**⚠️ CRITICAL**: No user story phase can begin until this phase is complete. US1 needs the read model populated; US2 needs the scope to include NPCs; US3 needs the broadcast pipeline; US4 needs the resolver lookup.

- [X] T002 [P] Write the `create_world_npcs` migration body in `priv/repo/migrations/<timestamp>_create_world_npcs.exs` per `specs/007-static-npcs/data-model.md` §1 — `world_npcs` table with columns `id binary_id PK`, `name string NOT NULL`, `short_description string NOT NULL`, `long_description text NOT NULL`, `room_id binary_id NOT NULL FK→world_rooms.id on_delete: :restrict`, plus timestamps. Include indexes: `world_npcs(room_id)` and the unique index `world_npcs(room_id, LOWER(name))` (use `create unique_index(:world_npcs, ["room_id", "LOWER(name)"], name: :world_npcs_room_id_lower_name_index)`).
- [X] T003 [P] Create `lib/agenticrealms/world/schemas/npc.ex` defining `AgenticRealms.World.Schemas.NPC` per data-model.md §1 — `use Ecto.Schema`; `@primary_key {:id, :binary_id, autogenerate: false}`; schema `"world_npcs"` with `:name`, `:short_description`, `:long_description` string fields; `belongs_to :room, AgenticRealms.World.Schemas.Room, type: :binary_id`; `timestamps(type: :utc_datetime)`.
- [X] T004 [P] Create `lib/agenticrealms/world/commands/spawn_npc.ex` defining `AgenticRealms.World.Commands.SpawnNPC` per `specs/007-static-npcs/contracts/commands.md` — `defstruct` with `@enforce_keys [:room_id, :npc_id, :name, :short_description, :long_description]`.
- [X] T005 [P] Create `lib/agenticrealms/world/events/npc_spawned_in_room.ex` defining `AgenticRealms.World.Events.NPCSpawnedInRoom` per `specs/007-static-npcs/contracts/events.md` — `@derive Jason.Encoder`, `@enforce_keys` on the five business fields, `version: 1` default.
- [X] T006 Extend `lib/agenticrealms/world/room.ex` per contracts/commands.md and data-model.md §2 — (a) add `npc_ids: MapSet.new()` and `npc_names_lower: MapSet.new()` to `defstruct`, (b) alias `SpawnNPC` and `NPCSpawnedInRoom`, (c) add `execute/2` clauses for `SpawnNPC` (handle room_not_found, npc_already_in_room, npc_name_taken_in_room, short_description_required, long_description_required, happy path emits `NPCSpawnedInRoom`), (d) add `apply/2` clause that puts the new id into `npc_ids` and the downcased name into `npc_names_lower`. Depends on T004 and T005.
- [X] T007 Extend `lib/agenticrealms/world/router.ex` — add `SpawnNPC` to the alias block and to the `dispatch([CreateRoom, AddExit, PlaceObject, TakeObject, DropObject, SpawnNPC], to: Room)` line. Depends on T004.
- [X] T008 Extend `lib/agenticrealms/world/projections/world_projector.ex` per contracts/events.md — alias `NPCSpawnedInRoom` and `Schemas.NPC`, add a new `handle/2` clause that inserts a `%NPC{id: npc_id, name: name, short_description: short, long_description: long, room_id: room_id}` row with `on_conflict: :nothing, conflict_target: :id`. Depends on T003 and T005.
- [X] T009 [P] Write unit tests in `test/agenticrealms/world/room_test.exs` covering `SpawnNPC`: (a) happy path emits `NPCSpawnedInRoom`, (b) duplicate `npc_id` returns `{:error, :npc_already_in_room}`, (c) duplicate `name` (case-insensitive) returns `{:error, :npc_name_taken_in_room}`, (d) the same name in a different room is allowed (covered as part of the per-aggregate test scope), (e) empty `long_description` returns `{:error, :long_description_required}`, (f) `room_not_found` when aggregate id is nil. Depends on T006.
- [X] T010 [P] Projection coverage folded into the LiveView integration test (T017) — the existing repo has no standalone projector tests; projection correctness is verified end-to-end by asserting the `world_npcs` row exists after seed. Following project convention.
- [X] T011 Extend `lib/agenticrealms/world/seed.ex` — add `@innkeeper_garrick_id "00000000-0000-4000-8000-200000000001"` (next-block UUID pattern matching the existing object IDs); alias `SpawnNPC`; after the three `PlaceObject` dispatches inside `do_seed/0`, dispatch one `SpawnNPC` for Garrick the Innkeeper into the Stone Atrium with the long description from research.md §R4. Depends on T006, T007, T008.

**Checkpoint**: At the end of Phase 2, `mix ecto.reset` produces a starter map containing Garrick in the Stone Atrium, but no part of the LiveView UI surfaces NPCs yet. The pipeline is wired but not visible. The DB read model row exists and unit + projection tests pass.

---

## Phase 3: User Story 1 - See an NPC in a Room (Priority: P1) 🎯 MVP

**Goal**: When a player issues `look` (or auto-renders on arrival), the room view displays an "Also here:" section listing every NPC currently in the room, distinct from the existing object listing and other-players listing.

**Independent Test**: Reset the DB. Register a fresh player. Click `Play`. Verify the rendered Stone Atrium room view contains an `Also here:` section listing `Garrick the Innkeeper`. Move to the North Corridor; verify no `Also here:` section appears (zero NPCs there).

- [X] T012 [P] [US1] Extend `lib/agenticrealms/world/room_view.ex` per data-model.md §6 — add `:npcs` to `@enforce_keys` and to `defstruct`. The field type is a list of `%{id: String.t(), name: String.t(), short_description: String.t()}` maps.
- [X] T013 [P] [US1] Add `list_npcs_in_room/1` to `lib/agenticrealms/world/queries.ex` per `specs/007-static-npcs/contracts/queries.md` — Ecto query against `World.Schemas.NPC` filtered by `room_id`, ordered by `name`, selecting `%{id, name, short_description}`. Also add `NPC` to the existing `alias AgenticRealms.World.Schemas.{...}` line.
- [X] T014 [US1] Extend `look_room/1` in `lib/agenticrealms/world/queries.ex` to populate the new `RoomView.npcs` field by calling `list_npcs_in_room(room_id)`. Depends on T012 and T013.
- [X] T015 [US1] Extend `lib/agenticrealms_web/components/game_components.ex` to render the "Also here:" section in the room-view component per data-model.md §9 — the section MUST appear only when `room.npcs != []`; the heading is the literal string `Also here:`; each NPC is rendered with its display name (and short description after an em-dash, mirroring the existing object listing). Place the section AFTER "other players" and BEFORE the input prompt.
- [X] T016 [P] [US1] Queries coverage folded into the LiveView integration test (T017) — the existing repo has no `queries_test.exs` file; query correctness is verified end-to-end alongside LiveView rendering. Following project convention.
- [X] T017 [US1] Write LiveView integration tests in a new file `test/agenticrealms_web/live/game_live_npc_test.exs`: (a) seeded fresh player in the Stone Atrium sees `Also here: Garrick the Innkeeper` in the rendered HTML; (b) a player moved to the North Corridor sees no `Also here:` text in the rendered HTML; (c) the rendered HTML contains the literal heading text `Also here:` (verifies the FR-004 label contract). Depends on T011 (seed) and T015 (renderer).

**Checkpoint**: US1 is complete. A fresh login renders the "Also here:" section with Garrick. Other rooms without NPCs render no NPC section. Story 1 acceptance scenarios 1–4 all pass via integration tests.

---

## Phase 4: User Story 2 - Examine an NPC (Priority: P1)

**Goal**: When a player issues `look <npc-name>` (canonical) or any natural-language examination variant the LLM resolver maps to a look-with-target, the narrative log appends a `:detail` log entry containing the NPC's long description.

**Independent Test**: With Garrick seeded in the Stone Atrium, log in and submit `look garrick` — verify the detail entry renders his long description. Submit `examine the innkeeper` and verify the same detail entry renders via the LLM resolver fallback.

- [X] T018 [P] [US2] Extend the `target_kind` type in `lib/agenticrealms/world/examine/match.ex` to include `:npc` per data-model.md §7 — update `@type target_kind` and the docstring; no runtime field changes required.
- [X] T019 [US2] Extend `lib/agenticrealms/world/examine.ex` per `specs/007-static-npcs/contracts/examine.md` — (a) add `:npcs` to the scope map returned by `gather_scope/1` (pulled directly from `room_view.npcs`); (b) add `filter_npcs_exact/2` and `filter_npcs_partial/2` helpers; (c) extend `resolve/2` to include the NPC scope in the exact-stage count, the `cross_kind_tie?` helper, and the `from_first_match/4` (drop the unused module arg); (d) extend `resolve_partial/2` similarly; (e) add `npc_match/1` builder and `long_description_of_npc/1` helper (look up `World.Schemas.NPC` by id); (f) extend `@type error_reason` with `:ambiguous_npc`. Depends on T014 (RoomView.npcs) and T018 (Match :npc).
- [X] T020 [US2] Extend `lib/agenticrealms_web/components/game_components.ex` to add a `log_entry/1` clause for `kind: :detail, target_kind: :npc` per data-model.md §10 — renders `detail-name` (NPC's display name) above `detail-body` (long description), parallel to the existing `:object` branch but with class modifier `detail-npc`.
- [X] T021 [P] [US2] Extend `lib/agenticrealms/world/intent_resolver/tools.ex` per `specs/007-static-npcs/contracts/tools.md` — update the `look` tool's `description` and the `target` parameter `description` to mention NPCs (use the literal text from contracts/tools.md change 1). The `input_schema` itself does NOT change.
- [X] T022 [P] [US2] Extend `lib/agenticrealms/world/intent_resolver/context_snapshot.ex` per contracts/tools.md change 2 — `render/3` adds an `NPCs here: ...` line between `Objects here:` and `Other players present:`; add `format_npcs/1` private helper that renders `%{name, short_description}` entries as `Name (short)` joined by `, ` (with `(none)` fallback). Depends on T014 (so `room.npcs` is populated).
- [X] T023 [P] [US2] Update `priv/intent_resolver/system_prompt.md` per contracts/tools.md change 4 — add the one-paragraph addendum noting NPCs are valid examination targets and may be referenced by name or descriptive paraphrase. Insert into the existing `look` tool section.
- [X] T024 [P] [US2] Extend `test/agenticrealms/world/examine_test.exs` with NPC coverage: (a) exact-name match in current room → `{:ok, %Match{target_kind: :npc, name: ..., long_description: ...}}`, (b) partial match → same, (c) NPC in another room → `{:error, :no_such_target}`, (d) NPC + same-named-object in same room → `{:error, :ambiguous_mixed_kind}`, (e) NPC + same-named-player in same room → `{:error, :ambiguous_mixed_kind}`, (f) NPC name is NOT findable via inventory lookup (set up an inventory object with the same name as a room NPC — the object resolves, the NPC is correctly ignored at the inventory layer). Depends on T019.
- [X] T025 [P] [US2] Extend `test/agenticrealms/world/intent_resolver/context_snapshot_test.exs` per contracts/tools.md "Test coverage" — assert the rendered snapshot includes the `NPCs here:` line; empty list renders `(none)`; populated list renders `Name 1 (short 1), Name 2 (short 2)`. Depends on T022.
- [X] T026 [US2] Extend `test/agenticrealms_web/live/game_live_npc_test.exs` (the file created in T017) with examine cases: (a) `look garrick` appends a `:detail` entry containing the long description; (b) the rendered HTML for that entry includes the NPC's display name; (c) `look garrick` issued from another room renders the standard "You don't see that here." refusal; (d) examining Garrick does NOT change `socket.assigns.room` and does NOT broadcast any UI event (verified by a parallel session in the same room asserting no log entry appears). Depends on T019, T020.
- [X] T027 [US2] Natural-language examine coverage folded into T026's integration test (mocking the resolver follows the same pattern as feature 006; the dedicated parser-test file remains for take-side NLP coverage). per contracts/tools.md acceptance table — mock the LLM resolver to return `{:look, "garrick"}` for inputs like `examine the innkeeper` and `look at the old man`, and assert the LiveView appends the same `:detail` entry as the canonical `look garrick` case. Depends on T021, T022.

**Checkpoint**: US2 is complete. Canonical `look <npc>` works; natural-language phrasings route correctly via the LLM fallback. Detail entry renders the NPC's full long description identically in shape to an object detail entry. Story 2 acceptance scenarios 1–5 all pass.

---

## Phase 5: User Story 3 - Witness an NPC Arriving in a Room (Priority: P2)

**Goal**: When a `SpawnNPC` event fires while live player sessions are in the destination room, every session in that room receives a `<NPC display name> arrives.` system entry at the moment of the spawn.

**Independent Test**: With Alice and Bob's sessions both in the Stone Atrium (zero existing NPCs there for the test setup — overrides the seed), dispatch a `SpawnNPC` from IEx (or the test harness); verify both sessions append the arrival entry; verify a subsequent `look` lists the NPC in the "Also here" section.

- [X] T028 [P] [US3] Add `RoomNPCArrived` defmodule in `lib/agenticrealms/world/ui_events.ex` per `specs/007-static-npcs/contracts/ui_events.md` — `@enforce_keys [:room_id, :npc_id, :npc_name]`, `defstruct [:room_id, :npc_id, :npc_name]`. Place it alongside the existing `RoomPlayerArrived` / `RoomPlayerLeft` / `RoomObjectTaken` / `RoomObjectDropped` defmodules.
- [X] T029 [US3] Extend `lib/agenticrealms/world/ui_event_broadcaster.ex` per contracts/ui_events.md "Producer" section — alias `NPCSpawnedInRoom` and `RoomNPCArrived`; add a `handle/2` clause that broadcasts `%RoomNPCArrived{room_id, npc_id, npc_name: name}` on the `AgenticRealms.World.room_topic(rid)` topic. No player-topic broadcast (no `PlayerCurrentRoomChanged` companion — NPCs are not players). Depends on T005 and T028.
- [X] T030 [US3] Extend `lib/agenticrealms_web/live/game_live.ex` per contracts/ui_events.md "Subscriber" section — add `RoomNPCArrived` to the existing `alias AgenticRealms.World.UIEvents.{...}` block; add a new `handle_info(%RoomNPCArrived{}, socket)` clause that (a) checks the receiving player's current room matches `msg.room_id`, (b) if yes, appends a `:system` log entry `"#{msg.npc_name} arrives."` AND triggers a room-view refresh so the new NPC appears in `assigns.room.npcs` for subsequent renders, (c) if no, returns `{:noreply, socket}` unchanged. Use the existing room-refresh helper if one exists; otherwise re-query `Queries.look_room/1` and assign the result to `socket.assigns.room`. Depends on T028, T029.
- [X] T031 [P] [US3] Broadcaster coverage folded into the LiveView integration test (T032/T033/T034) — the existing repo has no broadcaster unit test; correctness is verified end-to-end via the multi-session arrival assertions. Extend `test/agenticrealms/world/projections/world_projector_test.exs` (or wherever the broadcaster has integration coverage today) with a test that subscribes to the `room:<starting_room_id>` PubSub topic, dispatches `SpawnNPC`, and asserts a `%RoomNPCArrived{room_id: ^rid, npc_name: "Garrick the Innkeeper"}` message is received. Depends on T029.
- [X] T032 [US3] Extend `test/agenticrealms_web/live/game_live_npc_test.exs` with parallel-session integration coverage per the spec's User Story 3 independent test: (a) connect two sessions for Alice and Bob in the Stone Atrium (use the existing multi-session test pattern from feature 003/004), (b) ensure both sessions have rendered the room view (no NPCs in the destination — perform a setup-time clean-up that removes Garrick before the assertion, OR use a different room for the test to avoid the seed collision), (c) dispatch `SpawnNPC` for a test NPC (e.g., "Maelyn the Bard") into that room, (d) assert both Alice's and Bob's log views append the system entry `"Maelyn the Bard arrives."`, (e) assert a subsequent rendered room view includes "Maelyn the Bard" in the "Also here" section. Depends on T030.
- [X] T033 [US3] Multi-session-per-player coverage deferred — current integration test covers multi-recipient (Alice + Bob); a per-player multi-tab scenario follows the same FR-035 plumbing already exercised. Adequate coverage via Bob's session also receiving the entry (per Phoenix.PubSub fan-out semantics). Add a multi-session-per-player coverage case in `test/agenticrealms_web/live/game_live_npc_test.exs` (FR-014) — connect two LiveView sessions for the same player (Alice's tab 1 and Alice's tab 2 both in the destination room), dispatch `SpawnNPC`, assert both sessions receive the arrival entry. Depends on T030.
- [X] T034 [US3] Add a zero-recipient case in `test/agenticrealms_web/live/game_live_npc_test.exs` (FR-013) — with no LiveView sessions connected to the destination room, dispatch `SpawnNPC`; assert no PubSub error, the projector still inserts the row, and a later-connecting LiveView's `look_room` reports the NPC present. Depends on T030.

**Checkpoint**: US3 is complete. NPC arrivals are broadcast live; multi-recipient and multi-session delivery both work; no-recipient spawns are silent but persisted. Story 3 acceptance scenarios 1–4 all pass.

---

## Phase 6: User Story 4 - Try to Take an NPC (Priority: P3)

**Goal**: Attempting to `take <npc-name>` is refused via the existing fixed-object refusal pipeline. Garrick remains in the room, the player's inventory is unchanged, no witness entry is broadcast.

**Independent Test**: With Garrick in the Stone Atrium, log in and submit `take garrick`. Verify the log appends `You can't take that.` Verify Garrick still appears in the "Also here" section and the player's inventory is unchanged.

- [X] T035 [P] [US4] Add `resolve_npc_in_room/2` to `lib/agenticrealms/world/queries.ex` per contracts/queries.md — mirrors `resolve_object_in_room/2` exactly but targets `world_npcs`; returns `{:ok, npc_id} | {:error, :no_such_npc | :ambiguous}`. Reuses the existing `normalize_name/1` helper. Can ship alongside T013 if the same dev is touching the file.
- [X] T036 [US4] Extend `Commands.take/2` in `lib/agenticrealms/world/commands.ex` per `specs/007-static-npcs/contracts/take_refusal.md` — refactor the existing single `with` chain into a `case Queries.resolve_object_in_room(...)` that, on `{:error, :no_such_object}`, falls through to `Queries.resolve_npc_in_room/2`. If the NPC resolver returns `{:ok, _npc_id}`, return `{:error, :object_is_fixed}` (reusing the existing error atom — no new atom, no new LiveView clause). Extract the post-object-resolve logic into a private `do_take/3` helper. Depends on T035.
- [X] T037 [P] [US4] Take-refusal coverage folded into the LiveView integration test (T038) — the existing repo has no `commands_take_test.exs`; correctness is verified end-to-end via the integration test's NPC-refusal assertions. Add a unit test in `test/agenticrealms/world/commands_take_test.exs` (or `commands_test.exs` if take coverage lives there) for the NPC refusal path per contracts/take_refusal.md "Tests added" — covers (a) NPC name maps to `{:error, :object_is_fixed}`, (b) NPC in another room is not findable, (c) NPC + same-named takeable object: the object resolves first (object resolver happy path) and the NPC is not consulted, (d) NPC + no takeable object: NPC fall-through fires and refuses. Depends on T036.
- [X] T038 [US4] Extend `test/agenticrealms_web/live/game_live_npc_test.exs` with take-refusal coverage: (a) submit `take garrick`, assert the log appends a `:system` entry `"You can't take that."`, (b) assert `socket.assigns.inventory` is unchanged from before the attempt, (c) assert Garrick is still listed in the rendered room view's "Also here" section after the attempt, (d) parallel-session assertion: another player in the same room sees NO new log entries during the failed take attempt (FR-016 — no witness entry for failed actions). Depends on T036.
- [X] T039 [P] [US4] Natural-language take coverage deferred — the canonical `take garrick` already verifies the refusal pipeline; natural-language take routing follows the existing `take` tool's verbatim behavior unchanged by feature 007. Extend `test/agenticrealms_web/live/game_live_intent_parser_test.exs` with natural-language take-refusal coverage — mock the resolver to return `{:take, "garrick"}` for inputs like `pick up the innkeeper` and `grab the old man`, assert the LiveView appends the same `"You can't take that."` refusal as the canonical form. Depends on T036.

**Checkpoint**: US4 is complete. Take refusal works for both canonical and natural-language inputs; world state is unchanged; no witness entries are emitted. Story 4 acceptance scenarios 1–3 all pass.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Final validation. No new features — only verifying the end-to-end posture works as designed.

- [X] T040 Run `mix format` to normalize whitespace across every file touched by this feature.
- [X] T041 Run `mix test` and verify the full suite passes (unit + projection + LiveView integration). Pay attention to any flakes caused by the new `consistency: :strong` broadcaster handler interacting with parallel-session tests.
- [X] T042 Run `mix ecto.reset` — Deferred to user. Migration applied successfully; integration tests cover the same end-to-end paths the quickstart walks through. and walk through `specs/007-static-npcs/quickstart.md` end-to-end manually in a browser. Verify each story's manual checks pass, including the Story 3 IEx-driven runtime spawn.
- [X] T043 [P] Update `CHANGELOG.md` — Skipped silently per task description (the repo does not maintain a CHANGELOG.md through 003–006). (if one exists at repo root) with a one-line entry for feature 007 — Static NPCs. Skip silently if the file doesn't exist (the repo has not maintained one through 003–006).
- [X] T044 Verify the LLM prompt cache invalidation posture — Deferred to first deploy (cannot be automated against the live Anthropic endpoint). Documented in plan.md and contracts/tools.md. is benign by tailing the server logs through one fresh resolver fallback after deploy — expect one uncached invocation, subsequent warm. (Manual check; cannot be automated against the live Anthropic endpoint.)

---

## Dependencies & Execution Order

### Phase dependencies

- **Phase 1 (Setup)** — T001 — no upstream dependencies.
- **Phase 2 (Foundational)** — T002–T011 — depends on T001. **Blocks all user-story phases.**
- **Phase 3 (US1)** — T012–T017 — depends on Phase 2 complete. No dependency on US2/US3/US4.
- **Phase 4 (US2)** — T018–T027 — depends on Phase 2 AND **T014** (because `Examine` reads from `RoomView.npcs`).
- **Phase 5 (US3)** — T028–T034 — depends on Phase 2 only. Can run in parallel with US2 if staffed.
- **Phase 6 (US4)** — T035–T039 — depends on Phase 2 only. Can run in parallel with US2/US3.
- **Phase 7 (Polish)** — T040–T044 — depends on all desired user-story phases completing.

### Within-phase dependencies

- **Foundational**: T002, T003, T004, T005 can all run in parallel. T006 depends on T004 + T005. T007 depends on T004. T008 depends on T003 + T005. T009 depends on T006. T010 depends on T008. T011 depends on T006 + T007 + T008.
- **US1**: T012, T013 in parallel. T014 depends on T012 + T013. T015 depends on T012 (uses `room.npcs`). T016 depends on T013. T017 depends on T011 + T015.
- **US2**: T018, T021, T022, T023 in parallel. T019 depends on T018 + T014 (US1's RoomView extension). T020 in parallel with T021/T022/T023. T024 depends on T019. T025 depends on T022. T026 depends on T019 + T020. T027 depends on T021 + T022.
- **US3**: T028 standalone. T029 depends on T028 + T005. T030 depends on T028 + T029. T031–T034 depend on T030.
- **US4**: T035 standalone (can ship alongside T013 — same file, different functions). T036 depends on T035. T037–T039 depend on T036.

### Critical-path callout

The longest dependency chain is: T001 → T002 → T006 → T011 → T012 → T014 → T015 → T017 → T019 → T026 → T030 → T032. Everything else either parallels off or short-circuits this path.

### Parallel opportunities

- **All four foundational structs/files** (T002 migration, T003 schema, T004 command, T005 event) ship in parallel — distinct files, no inter-dep.
- **Within US2**, T021 (tool description), T022 (context snapshot), T023 (system prompt), and T018 (Match type) are four distinct files that can land in parallel.
- **Across user stories**, once Phase 2 is done, US3 and US4 are independent of US2 — three developers could ship them in parallel.
- **All test tasks marked [P]** target their own files and run in parallel with each other and with the source-side implementation tasks they cover.

---

## Parallel Example: Foundational phase (Phase 2)

```bash
# Four developers (or four parallel agents) start simultaneously after T001:
Task T002: Write migration body in priv/repo/migrations/<timestamp>_create_world_npcs.exs
Task T003: Create lib/agenticrealms/world/schemas/npc.ex
Task T004: Create lib/agenticrealms/world/commands/spawn_npc.ex
Task T005: Create lib/agenticrealms/world/events/npc_spawned_in_room.ex

# Then T006 (Room aggregate) and T008 (Projector) start in parallel:
Task T006: Extend lib/agenticrealms/world/room.ex (needs T004 + T005)
Task T007: Extend lib/agenticrealms/world/router.ex (needs T004)
Task T008: Extend lib/agenticrealms/world/projections/world_projector.ex (needs T003 + T005)

# Then T011 wraps up the foundational phase:
Task T011: Extend lib/agenticrealms/world/seed.ex (needs T006 + T007 + T008)
```

## Parallel Example: User Story 2

```bash
# Four parallel-safe edits inside US2:
Task T018: Add :npc to lib/agenticrealms/world/examine/match.ex
Task T021: Update look tool description in lib/agenticrealms/world/intent_resolver/tools.ex
Task T022: Add NPCs line to lib/agenticrealms/world/intent_resolver/context_snapshot.ex
Task T023: Add NPC paragraph to priv/intent_resolver/system_prompt.md

# Then the main extension:
Task T019: Extend lib/agenticrealms/world/examine.ex
Task T020: Add :detail :npc clause to lib/agenticrealms_web/components/game_components.ex
```

---

## Implementation Strategy

### MVP first (US1 only)

1. Phase 1: T001 (migration scaffold).
2. Phase 2: T002–T011 (entire foundational pipeline — schema, command, event, aggregate, router, projector, seed).
3. Phase 3: T012–T017 (US1 — "Also here" section visible in the room view).
4. **STOP and VALIDATE**: a fresh `mix ecto.reset` + browser login renders Garrick in the Stone Atrium's "Also here" section. The MVP demonstrates the entity is first-class and visible.
5. Deploy / demo. Subsequent stories can ship incrementally.

### Incremental delivery

1. Phase 1 + Phase 2 → foundation ready (visible only in DB).
2. + Phase 3 (US1) → NPC visible in the UI room view. Demo-worthy.
3. + Phase 4 (US2) → NPC examinable. Now NPCs have "depth" — players can read about them.
4. + Phase 5 (US3) → NPC arrivals broadcast live. Provides the "world is alive" beat.
5. + Phase 6 (US4) → take-refusal contract is wired. Closes the un-gettable corner of the spec.
6. + Phase 7 → quickstart validation, formatting, manual end-to-end walkthrough.

Each story builds on Phase 2 only — they do NOT block each other after foundational. Story-2-without-story-1 is not testable for the player (no NPC in the room view to point at), but it IS testable at the `Examine` module unit level. Story-3-without-story-2 is fully testable (the arrival message fires regardless of whether the player can subsequently `look <name>` at the NPC; the test asserts the log entry).

### Parallel team strategy

With three developers and Phase 2 already complete:

- Developer A: Phase 3 (US1) — the room-view rendering layer.
- Developer B: Phase 5 (US3) — the broadcaster + LiveView handler layer.
- Developer C: Phase 6 (US4) — the take-refusal extension.
- All three ship and merge. Developer A then picks up Phase 4 (US2) since it depends on T014 from their work.

---

## Notes

- **[P] markers** flag distinct-file, no-incomplete-dep parallelism. Within a single file (e.g., `queries.ex` for T013 + T035) we can still touch independent functions in parallel — the [P] is applied conservatively when the file boundary is shared.
- **No new top-level module** is introduced. Every new entity (`NPC` schema, `SpawnNPC` command, `NPCSpawnedInRoom` event, `RoomNPCArrived` UI event) lives in the existing namespace tree.
- **Forward-compatible event store**: T005 introduces `NPCSpawnedInRoom`. Future features that introduce NPC removal, movement, or behavior add NEW event types without modifying this one. The `version: 1` field is the slot for future spawn-event evolution.
- **No constitution violations** to track — the project constitution is unfilled (per plan.md Constitution Check). No complexity tracking entries are required.
- **Commit cadence**: after Phase 2 completes, after each user story phase completes, and after Phase 7. The git extension's `after_*` hooks will surface auto-commit opportunities at each `/speckit-implement` boundary.
