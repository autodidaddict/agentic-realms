---

description: "Task list for feature 014 — wizard-created object blueprints (milestone 1)"
---

# Tasks: Wizard-Created Object Blueprints (Milestone 1)

**Input**: Design documents from `/specs/014-item-blueprints/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md (all present)

**Tests**: Test tasks are included throughout — the plan explicitly enumerates a test surface that ships with this feature.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: User-story label (US1–US6) for traceability to spec.md
- All paths are repo-root-relative; the existing single Phoenix project layout is used per plan.md.

## Path conventions

- Code: `lib/agenticrealms/...`, `lib/agentic_realms_web/...`
- Tests: `test/agentic_realms/...`, `test/agentic_realms_web/...`
- Migrations: `priv/repo/migrations/`
- Specs: `specs/014-item-blueprints/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Baseline confirmation. This feature adds no new dependencies, so Setup is light.

- [X] T001 Confirm clean baseline on branch `014-item-blueprints`: `mix deps.get` reports nothing new, `mix compile --warnings-as-errors` succeeds, `mix test` is green on `main` before any code changes land.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Wizard authorization, ObjectBlueprint substrate, mode-toggle infrastructure. All user stories depend on this phase.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Wizard authorization (FR-WIZ-1 through FR-WIZ-6)

- [X] T002 Create migration `priv/repo/migrations/<ts>_add_is_wizard_to_players.exs` adding `is_wizard boolean NOT NULL DEFAULT false` to `players` per `data-model.md` §1.1.
- [X] T003 [P] Extend `lib/agenticrealms/accounts/player.ex` with `field :is_wizard, :boolean, default: false`.
- [X] T004 [P] Implement `AgenticRealms.Accounts.promote_to_wizard/1` in `lib/agenticrealms/accounts.ex` per `contracts/commands.md` (idempotent; returns `{:ok, %Player{}}` / `{:error, :not_found}`).
- [X] T005 [P] Add `Accounts.get_player/1` (if absent) used by the wizard-authz helper. *(already present in `lib/agenticrealms/accounts.ex`)*
- [X] T006 Landed in T031 — `ensure_wizard/1` is the wrapper-level authz gate used by every wizard command.
- [X] T007 [P] Unit tests in `test/agentic_realms/accounts_test.exs`: `promote_to_wizard/1` happy path, idempotency, `{:error, :not_found}` on unknown id.

### Object Blueprint substrate (FR-007, FR-007a, FR-007b, FR-008, FR-009)

- [X] T008 Create migration `priv/repo/migrations/<ts>_create_object_blueprints.exs` per `data-model.md` §1.2 (slug PK with regex CHECK, `kind` CHECK = `'object'`, `revision` CHECK > 0, index on `kind`).
- [X] T009 [P] Create `lib/agenticrealms/world/schemas/object_blueprint.ex` Ecto schema per `data-model.md` §1.2.
- [X] T010 [P] Create `lib/agenticrealms/world/object_blueprint.ex` aggregate struct (fields per `data-model.md` §2.1) — handlers come in later phases.
- [X] T011 Add aggregate identification to `lib/agenticrealms/world/router.ex`: `identify(ObjectBlueprint, by: :blueprint_id, prefix: "object-blueprint-")`. Register dispatch (handler list initially empty; commands added per phase). *(identify only; dispatch list deferred to T030.)*
- [X] T012 [P] Landed in T032 — projector module created with its `ObjectBlueprintCreated` handler and supervised in both `lib/agenticrealms/application.ex` and `test/support/data_case.ex`.
- [X] T013 [P] Slug derivation helper module `lib/agenticrealms/world/object_blueprint/slug.ex` exposing `derive/1` (lowercase + non-alphanumeric → `_` + trim leading/trailing `_`) and `valid?/1` (regex match per FR-007a). Used by both the Commands wrapper and the LiveView form.
- [X] T014 [P] Unit tests in `test/agentic_realms/world/object_blueprint/slug_test.exs`: `derive/1` for common cases including names with punctuation, accents (out of scope — should reject), and length boundaries; `valid?/1` accepts the regex and rejects everything else including UUID-shaped strings.

### Intent resolver context extension (FR-022, FR-023)

- [X] T015 Landed differently — instead of extending `ContextSnapshot` (a pure string-builder for player intent), wizard mode got its own resolver entry points (`IntentResolver.resolve_wizard_blueprint/2` and `.resolve_wizard_world/2`) each with their own system prompt + tool set. ContextSnapshot stays focused on the player-intent path. See T034 / `IntentResolver.WizardTools`.

### Mode toggle + trance broadcast infrastructure (FR-001 through FR-006, FR-WIZ-3, FR-WIZ-4)

- [X] T016 [P] ~~Create `lib/agenticrealms/world/events/wizard_entered_trance.ex` per `contracts/events.md` (fields: `wizard_id`, `room_id`, `at`).~~ **Redesigned as a UI event, not a domain event.** Added `RoomTranceEntered` to `lib/agenticrealms/world/ui_events.ex`. Rationale: trance is a UI signal with no world-state implication; routing it through Commanded would require an aggregate just to emit a transient broadcast. See research.md R3 for the original intent and the updated rationale.
- [X] T017 [P] ~~Create `lib/agenticrealms/world/events/wizard_exited_trance.ex` (same shape).~~ Replaced by `RoomTranceExited` UI event in `lib/agenticrealms/world/ui_events.ex`, same rationale as T016.
- [X] T018 Create `lib/agenticrealms/world/wizard_trance.ex` helper module exposing `enter/3` and `exit/3` per `contracts/events.md` "transient — non-aggregate" notes. **Adjusted**: helper calls `Phoenix.PubSub.broadcast/3` directly with the `RoomTranceEntered` / `RoomTranceExited` UI event structs, matching the existing player-arrival broadcast pattern from feature 003.
- [X] T019 [P] ~~Extend `lib/agenticrealms/world/ui_event_broadcaster.ex` with handlers for `WizardEnteredTrance` and `WizardExitedTrance`.~~ **Dropped** — the trance signal is broadcast directly by `WizardTrance` per T018, so the `UIEventBroadcaster` (which subscribes only to persisted domain events) does not need to be involved. The FR-004 suppression is implicit (no broadcast subscribers ⇒ no log entries reach any session); self-suppression (FR-002 "every *other* player session") is enforced by the LiveView `handle_info` self-filter pattern matching the existing `RoomPlayerArrived` flow.
- [X] T020 Extend `lib/agenticrealms_web/live/game_live.ex` mount with: read `Accounts.get_player(player_id).is_wizard`, store as `:is_wizard` assign, initialize `:authoring_mode` to `:world` for wizards (no assign for non-wizards), set up `:focused_object_id` and `:focused_blueprint_id` to `nil`.
- [X] T021 Add LiveView event handler `handle_event("toggle_authoring_mode", _, socket)` to `lib/agenticrealms_web/live/game_live.ex`. Entry-guard `:is_wizard`; flip `:authoring_mode`; on each transition, call `WizardTrance.enter/3` or `.exit/3`. On `:blueprints` → `:world`, clear `:focused_blueprint_id`.
- [X] T022 Extend layout to gate the Wizard/Player top-bar switch on `is_wizard` (FR-WIZ-3). Implementation: `is_wizard` attr added to `Layouts.app`, switch hidden when false. The wizard-view mode toggle button (within the chrome itself) lands alongside the wizard chrome wiring in US1.

### Foundational tests

- [X] T023 [P] `ensure_wizard/1` behavior is exercised end-to-end by every wrapper test (`create_object_blueprint_wrapper_test.exs`, `spawn_object_from_blueprint_wrapper_test.exs`, `spawn_object_freeform_wrapper_test.exs`, `extract_object_essence_test.exs`, `edit_object_blueprint_wrapper_test.exs`, `edit_object_wrapper_test.exs`, `edit_object_security_test.exs`) — non-wizard refusal and unknown-player refusal are covered in each.
- [X] T024 [P] LiveView authorization tests in `test/agentic_realms_web/live/wizard_foundational_test.exs`: non-wizard does NOT see the top-bar Wizard switch (FR-WIZ-3); a crafted `switch_mode` event is refused (FR-WIZ-4).
- [X] T025 Integration test in `test/agentic_realms_web/live/wizard_foundational_test.exs`: promote → two LiveView clients in same room → wizard toggles `:blueprints` → witness sees `enters a trance.` → wizard's own log self-suppressed → toggle back → witness sees `appears to come out of a trance.`. Verifies FR-002, FR-003, and the self-suppression pattern.

**Checkpoint**: Wizard role, mode toggle, trance broadcast, and Blueprint substrate are in place. User stories can now proceed in parallel.

---

## Phase 3: User Story 1 - Wizard Authors an Object Blueprint in Trance (Priority: P1) 🎯 MVP

**Goal**: A wizard can flip into Sanctum mode and author a new Object Blueprint via a natural-language prompt + the Interpreted Data form, then commit it to the registry at revision 1.

**Independent Test**: Per spec.md Story 1's Independent Test — promote a player, sign in, flip to Sanctum, prompt a multi-sentence object description, click Commit, verify a registry row exists with the expected name and `revision: 1`. Verify the trance log entries reached a co-located player.

### Commands & events (FR-030)

- [X] T026 [P] [US1] Create `lib/agenticrealms/world/commands/create_object_blueprint.ex` command struct per `contracts/commands.md`.
- [X] T027 [P] [US1] Create `lib/agenticrealms/world/events/object_blueprint_created.ex` event struct per `contracts/events.md`.

### Aggregate handler (FR-007, FR-007a)

- [X] T028 [US1] Implement `ObjectBlueprint.execute/2` clause for `CreateObjectBlueprint` in `lib/agenticrealms/world/object_blueprint.ex`: against `id: nil`, emit `ObjectBlueprintCreated` with `revision: 1`; against initialized state, return `{:error, :already_exists}`.
- [X] T029 [US1] Implement `ObjectBlueprint.apply/2` for `ObjectBlueprintCreated` setting all fields and `revision: 1`.
- [X] T030 [US1] Register `CreateObjectBlueprint` in the dispatch list for `ObjectBlueprint` in `lib/agenticrealms/world/router.ex`.

### Command wrapper (FR-007b, FR-WIZ-5)

- [X] T031 [US1] Implement `Commands.create_object_blueprint/2` in `lib/agenticrealms/world/commands.ex` per `contracts/commands.md`: authz via `ensure_wizard/1`, slug regex validation, uniqueness pre-check against `object_blueprints` read model, dispatch. Also landed the deferred T006 `ensure_wizard/1` helper here.

### Projector (FR-030 projection)

- [X] T032 [P] [US1] Extend `lib/agenticrealms/world/projections/object_blueprint_projector.ex` with a handler for `ObjectBlueprintCreated`: insert a new `object_blueprints` row with the event payload + `revision: 1` + timestamps. Use `on_conflict: :nothing` for replay safety per `contracts/events.md`. Projector supervised in both `lib/agenticrealms/application.ex` and `test/support/data_case.ex` `setup_commanded/0`.

### LLM intent tool (FR-022) — wizard-facing UX

- [X] T033 [P] [US1] Added `lib/agenticrealms/world/intent_resolver/wizard_tools.ex` with the `draft_object_blueprint` + `refuse` schemas for `:blueprints` mode.
- [X] T034 [US1] Added `IntentResolver.resolve_wizard_blueprint/2` — separate entry point with its own system prompt, tool list, and outcome parser (returns `{:ok, {:draft_blueprint, fields}} | {:error, refusal}`). Player-side `resolve/2` is untouched.

### LiveView wiring (FR-019 dual-role Interpreted Data card; FR-026 minimal registry)

- [X] T035 [US1] Added `wizard_authoring_view/1` and `blueprint_draft_form/1` components in `lib/agenticrealms_web/components/game_components.ex` rendering the Interpreted Data card from a `:focused_blueprint_draft` assign. Form binds to a single `phx-change="update_blueprint_draft"` with `draft[...]` field namespacing.
- [X] T036 [US1] Added `handle_event("submit_wizard_prompt", ...)` — entry-guards `:is_wizard` + `:authoring_mode == :blueprints` + `not wizard_input_locked`, spawns `IntentResolver.resolve_wizard_blueprint/2` via `IntentResolverTaskSupervisor`, stashes `:wizard_resolver_task`. Companion `handle_info({ref, result}, ...)` clause populates `:focused_blueprint_draft` on `{:draft_blueprint, fields}` (auto-deriving slug) or surfaces the refusal inline.
- [X] T037 [US1] Added `handle_event("commit_blueprint_draft", _, socket)` dispatching `Commands.create_object_blueprint/2` with the draft. On `{:ok, _}` clears the draft and refreshes `:object_blueprints`. Errors render inline via `format_commit_error/1` (covers `:invalid_slug`, `:slug_already_exists`, `:not_a_wizard`, `:llm_refusal`).
- [X] T038 [US1] Added `handle_event("discard_blueprint_draft", _, socket)` clearing the draft + commit error; wizard stays in `:blueprints` mode.
- [X] T039 [P] [US1] Added the Blueprints registry rendering in `wizard_authoring_view/1` driven off the `:object_blueprints` assign (loaded on mount via `Queries.list_object_blueprints/0`, refreshed on successful commit).
- [X] T040 [P] [US1] Add `list_object_blueprints/0` to `lib/agenticrealms/world/queries.ex` returning `[%ObjectBlueprint{} | _]` ordered by name. Also added `get_object_blueprint/1` for the wrapper's pre-check + future US5 edit-load path.

### Tests for US1

- [X] T041 [P] [US1] Aggregate test in `test/agentic_realms/world/object_blueprint_test.exs`: `CreateObjectBlueprint` against `id: nil` emits `ObjectBlueprintCreated`; against initialized state returns `{:error, :already_exists}`. Apply/2 sets revision = 1.
- [X] T042 [P] [US1] Wrapper test in `test/agentic_realms/world/commands/create_object_blueprint_wrapper_test.exs`: non-wizard refused; invalid slug refused; collision detected via pre-check; happy path dispatches.
- [X] T043 [P] [US1] Projector test in `test/agentic_realms/world/projections/object_blueprint_projector_test.exs`: `ObjectBlueprintCreated` inserts a row; idempotent replay.
- [X] T044 [P] [US1] Intent resolver tests in `test/agenticrealms/world/intent_resolver/wizard_tools_test.exs` — 8 cases covering successful extraction, missing `fixed` default, `refuse` mapping, multi-tool refusal, no-tool refusal, unknown-tool refusal, malformed inputs, and shape-validation failures.
- [X] T045 [US1] Full-loop LiveView integration test in `test/agenticrealms_web/live/wizard_authoring_test.exs` — 3 cases: (1) trance → prompt → mocked LLM draft → Commit → registry shows new blueprint at revision 1; (2) Discard clears the draft without persisting; (3) LLM refusal surfaces inline without producing a draft.

**Checkpoint**: User Story 1 is functionally complete. The wizard can author a blueprint end-to-end. This is the MVP.

---

## Phase 4: User Story 2 - Wizard Spawns an Object from a Blueprint into a Room (Priority: P1)

**Goal**: A wizard in World mode can click "Spawn here" on a blueprint registry row and instantiate a copy of it in their current room.

**Independent Test**: Per Story 2 — author a blueprint via US1, walk to a specific room, click Spawn here on the row, verify the Object appears in the co-located player's room view and on their next `look`.

### Commands & events (FR-010, FR-029)

- [X] T046 [P] [US2] Created `lib/agenticrealms/world/commands/spawn_object_from_blueprint.ex` per `contracts/commands.md`.
- [X] T047 [P] [US2] Created `lib/agenticrealms/world/events/object_spawned.ex` — `@enforce_keys` deliberately omits `blueprint_id`; the struct has no such field (FR-013 / FR-029 enforced at the struct shape).

### Room aggregate extension (FR-010)

- [X] T048 [US2] Added `Room.execute/2` clause for `SpawnObjectFromBlueprint` in `lib/agenticrealms/world/room.ex` emitting `ObjectSpawned{...}` with the dispatcher-stamped payload. Refuses `:room_not_found` for uninitialized room and `:object_already_in_room` if the object_id is already in the presence set.
- [X] T049 [US2] Added `Room.apply/2` for `ObjectSpawned` that adds the object_id to the room's `object_ids` MapSet (matches the existing ObjectPlacedInRoom pattern).
- [X] T050 [US2] Added `SpawnObjectFromBlueprint` to the `Room` dispatch list in `lib/agenticrealms/world/router.ex`.

### Command wrapper (FR-WIZ-5, blueprint-payload stamping)

- [X] T051 [US2] Added `Commands.spawn_object_from_blueprint/3` in `lib/agenticrealms/world/commands.ex`: authz via `ensure_wizard/1`, resolves the blueprint via `fetch_blueprint/1`, stamps the denormalized fields, generates a UUIDv4 `object_id`, dispatches with `:strong` consistency.

### Projector & UI broadcast (FR-014)

- [X] T052 [P] [US2] Added `WorldProjector.handle/2` clause for `ObjectSpawned` that inserts a `world_objects` row with empty behaviors / nil quest fields / `on_conflict: :nothing`. The row shape has no `blueprint_id` column — schema unchanged per FR-013.
- [X] T053 [US2] Added `UIEventBroadcaster.handle/2` clause for `ObjectSpawned` that broadcasts a new `RoomObjectArrived` UI event on `room:<room_id>` topic.

### LiveView wiring

- [X] T054 [US2] Extended the Blueprints registry component with a "Spawn here" button that renders only when `:authoring_mode == :world`, with `phx-value-blueprint_id` carrying the slug.
- [X] T055 [US2] Added `handle_event("spawn_here", ...)` in `game_live.ex` — entry-guards `:is_wizard` + `:authoring_mode == :world`, dispatches via `Commands.spawn_object_from_blueprint/3`. Errors surface inline via `:blueprint_commit_error`.
- [X] T056 [US2] Added `handle_info(%RoomObjectArrived{...}, socket)` clause that appends a `<short_description> appears.` system entry to every co-located session — including the spawning wizard's own session.

### Tests for US2

- [X] T057 [P] [US2] Aggregate tests in `test/agenticrealms/world/room_spawn_from_blueprint_test.exs` (new file): 5 cases — happy path, no-room refusal, already-in-room refusal, event shape verification (no `blueprint_id`), `apply/2` adds to presence set.
- [X] T058 [P] [US2] Wrapper tests in `test/agenticrealms/world/commands/spawn_object_from_blueprint_wrapper_test.exs`: 5 cases — happy path persists row + no `blueprint_id` column, non-wizard refused, unknown blueprint refused, two spawns produce distinct object ids, row reflects blueprint's current denormalized payload.
- [X] T059 [P] [US2] Projector behavior is covered end-to-end by the wrapper test's `Repo.get(Object, object_id)` assertion (the wrapper dispatches with `:strong` consistency so the projector ran before the assert).
- [X] T060 [US2] LiveView integration tests in `test/agenticrealms_web/live/wizard_spawn_test.exs`: 3 cases — Spawn here → object lands + co-present player sees `<short_description> appears.`; Spawn here is not exposed in `:blueprints` mode (FR-027); crafted `spawn_here` event from a non-wizard is refused at the handler entry.

**Checkpoint**: User Stories 1 + 2 together deliver the headline loop — author a blueprint and put copies of it in the world.

---

## Phase 5: User Story 3 - Wizard Creates an Object Freeform in the World (Priority: P2)

**Goal**: A wizard in World mode can prompt an object into being directly in their current room, with no blueprint involvement. The Object is observationally identical to one spawned from a blueprint.

**Independent Test**: Per Story 3 — submit a freeform prompt, click Commit, verify the Object exists in the wizard's current room and the blueprint registry's row count is unchanged.

### Commands (FR-011, FR-012)

- [X] T061 [P] [US3] Created `lib/agenticrealms/world/commands/spawn_object_freeform.ex` per `contracts/commands.md`.

### Room aggregate extension

- [X] T062 [US3] Added `Room.execute/2` clause for `SpawnObjectFreeform` emitting the same `ObjectSpawned` event shape as the blueprint-spawn path (FR-012). Refuses `:room_not_found` and `:object_already_in_room` symmetrically with the blueprint path.
- [X] T063 [US3] Added `SpawnObjectFreeform` to the `Room` dispatch list in `lib/agenticrealms/world/router.ex`.

### Command wrapper

- [X] T064 [US3] Added `Commands.spawn_object_freeform/3` in `lib/agenticrealms/world/commands.ex`: authz via `ensure_wizard/1`, required-field validation (`name_required` / `short_description_required` / `long_description_required`), generates UUIDv4 `object_id`, dispatches with `:strong` consistency. NO blueprint involvement — no synthetic blueprint scaffolding.

### LLM intent tool

- [X] T065 [P] [US3] Added `manifest_object_freeform` + a world-mode `refuse` to `WizardTools.list_world/0`. Refactored shared refuse-tool builder.
- [X] T066 [US3] Added `IntentResolver.resolve_wizard_world/2` (separate entry point alongside `resolve_wizard_blueprint/2`) with its own system prompt + tool list + outcome shape (`{:freeform_object, fields}`). LLM-routing-by-blueprint-name is deferred — the world-mode prompt always routes to `manifest_object_freeform`; Spawn-here is the registry-driven path. Player-side tools are unaffected.

### LiveView wiring

- [X] T067 [US3] World-mode wizard chrome now has its own prompt textarea + form (same submit_wizard_prompt / update_wizard_prompt events) with a freeform-friendly placeholder; commit-error refusal renders inline under the prompt only when no draft is focused.
- [X] T068 [US3] `submit_wizard_prompt` now branches on `:authoring_mode` — `:blueprints` calls `resolve_wizard_blueprint`, `:world` calls `resolve_wizard_world`. The resolver-task `handle_info` handles both `{:draft_blueprint, ...}` and `{:freeform_object, ...}` outcomes, populating the appropriate draft assign.
- [X] T069 [US3] Added `handle_event("commit_object_draft", ...)` + `discard_object_draft` + `update_object_draft` event handlers. Commit dispatches `Commands.spawn_object_freeform/3` and on success clears the draft + prompt and sets a spawn-confirmation feedback toast.

### Tests for US3

- [X] T070 [P] [US3] Aggregate tests in `test/agenticrealms/world/room_spawn_freeform_test.exs`: 4 cases — happy path, no-room refusal, already-in-room refusal, no-blueprint_id verification.
- [X] T071 [P] [US3] Wrapper tests in `test/agenticrealms/world/commands/spawn_object_freeform_wrapper_test.exs`: 5 cases — happy path persists row without registry change, non-wizard refusal, missing-field refusals, two-spawn distinctness, FR-012 observational equivalence with the blueprint-spawn path.
- [X] T072 [P] [US3] Intent resolver tests in `test/agenticrealms/world/intent_resolver/wizard_world_tools_test.exs`: 6 cases — successful extraction, `fixed` default, refuse mapping, unknown-tool refusal, missing-field refusal, multi-tool refusal.
- [X] T073 [US3] Full-loop LiveView integration tests in `test/agenticrealms_web/live/wizard_freeform_test.exs`: 3 cases — world-mode prompt → LLM draft → Commit → Object spawns + co-located arrival entry + no Blueprint added + spawn-confirmation toast; Discard clears the draft; LLM refusal surfaces inline.

**Checkpoint**: US3 demonstrates the equivalence-by-design — Objects from blueprints and Objects from freeform are observationally indistinguishable.

---

## Phase 6: User Story 4 - Wizard Extracts Essence from a World Object into a New Blueprint (Priority: P2)

**Goal**: A wizard can click Extract essence on a focused world Object; the wizard is flipped into Sanctum with a draft Blueprint pre-populated wholesale from the source object's fields; Commit creates the Blueprint; the source Object is unmodified.

**Independent Test**: Per Story 4 — create a freeform Object, focus it, Extract essence, verify the wizard mode flipped, the draft fields match the source, Commit produces a Blueprint, and the source Object's fields are byte-identical to before.

### Extract action (FR-015 through FR-018)

- [X] T074 [US4] Added `Commands.extract_object_essence/3` in `lib/agenticrealms/world/commands.ex`: authz via `ensure_wizard/1`, resolves source via `fetch_object/1`, wholesale-copies the source's payload into a fresh `Commands.create_object_blueprint/2` call. Source object never touched. Intended for `iex` and tests; the LiveView path takes a different (review-before-commit) flow.

### LiveView wiring

- [X] T075 [US4] No explicit `focus_object` handler needed — extracting takes the `object_id` directly from the registry-style "Things in this room" panel (`phx-value-object_id` on the per-row Extract button). Removes a redundant click for the common case.
- [X] T076 [US4] Added a "Things in this room · {count}" panel to the World-mode wizard chrome. Reads `:room_objects` (via new `Queries.list_objects_in_room_for_wizard/1` — returns name, descriptions, fixed flag, excludes quest-scoped items). Each row carries an **Extract essence** button per FR-015. Empty state hints at Spawn here / freeform manifest.
- [X] T077 [US4] Added `handle_event("extract_essence", ...)` in `game_live.ex`: validates wizard + world-mode + same-room co-location; reads the source via `Queries.get_object/1`; pre-populates `:focused_blueprint_draft` with a WHOLESALE copy of the source's fields + an auto-derived slug; calls `WizardTrance.enter/3` to flip `:authoring_mode` to `:blueprints` (firing FR-002 trance log entries). Source Object is NEVER modified — actual blueprint creation happens via the existing `commit_blueprint_draft` flow.

### Tests for US4

- [X] T078 [P] [US4] Wrapper tests in `test/agenticrealms/world/commands/extract_object_essence_test.exs`: 6 cases — wholesale field copy at revision 1, source-object byte-equality (FR-018), non-wizard refused, unknown-object refused with `:unknown_object`, invalid-slug refused, slug-collision refused.
- [X] T079 [US4] Full-loop LiveView integration tests in `test/agenticrealms_web/live/wizard_extract_test.exs`: 3 cases — Extract essence → mode flipped + trance entry fired + draft pre-populated → form-field commit → new Blueprint at revision 1 with source-equal fields + source Object byte-unchanged; extract in `:blueprints` mode is refused (UI hidden + handler guard); extract with unknown object_id surfaces an inline error.

**Checkpoint**: US4 closes the manifest → recognize-as-archetype → reuse loop. Wizards can mint blueprints from anything they've already made.

---

## Phase 7: User Story 5 - Wizard Edits an Existing Blueprint or Object via the Form Editor (Priority: P2)

**Goal**: Wizards can edit Blueprints and Objects directly via the Interpreted Data form, with optimistic locking on Blueprints; edits to Blueprints do not affect previously spawned Objects.

**Independent Test**: Per Story 5 — author a Blueprint, focus it from the registry, change one field via the form, click Commit. Verify (a) revision bumps to 2, (b) any previously spawned Objects keep their original field values, (c) the form can edit again to revision 3.

### Commands & events (FR-020, FR-020a, FR-031, FR-032)

- [X] T080–T083 [P] [US5] New command/event structs: `EditObjectBlueprint` (carries `expected_revision`), `ObjectBlueprintEdited`, `EditObject`, `ObjectEdited`.

### Aggregate handlers (optimistic lock at aggregate boundary — FR-020a, FR-020b)

- [X] T084 [US5] Added `ObjectBlueprint.execute/2` clause for `EditObjectBlueprint` per FR-020a: mismatched `expected_revision` → `{:error, :stale_revision}` (Commanded only accepts 2-tuple errors; wrapper re-reads to attach `current_revision`). No-op diff → `:ok`. Field-changing diff → `ObjectBlueprintEdited` at revision+1. Invalid field key → `:invalid_field`. Only-actual-changed-fields path drops unchanged values from the emitted diff.
- [X] T085 [US5] Added `ObjectBlueprint.apply/2` for `ObjectBlueprintEdited` applying the sparse diff + setting revision.
- [X] T086 [US5] Added `EditObjectBlueprint` to `ObjectBlueprint`'s dispatch list in `router.ex`.
- [X] T087 [US5] Added `Room.execute/2` clause for `EditObject`: refuses `:object_not_in_room` if the object_id isn't in this Room aggregate's MapSet; no-op diff → `:ok`; otherwise emits `ObjectEdited`. Also added a no-op `Room.apply/2` clause for `ObjectEdited` so Commanded doesn't crash on the aggregate replay.
- [X] T088 [US5] Added `EditObject` to `Room`'s dispatch list in `router.ex`.

### Command wrappers

- [X] T089 [US5] Added `Commands.edit_object_blueprint/3`: authz + existence check + field-key validation + dispatch. On `:stale_revision` re-reads the read model to attach `current_revision: N` for the LiveView. Returns `{:ok, new_revision}` / `{:ok, :no_change}` distinctions so callers can decide what UI feedback to give.
- [X] T090 [US5] Added `Commands.edit_object/3`: authz, fetches the object to derive its current room, validates fields, dispatches. Returns `{:ok, :no_change}` for diffs whose values already match the persisted state.

### Projector handlers

- [X] T091 [P] [US5] Added `ObjectBlueprintProjector.handle/2` clause for `ObjectBlueprintEdited` — `UPDATE WHERE id = $1 AND revision < $2`, idempotent replay guard.
- [X] T092 [P] [US5] Added `WorldProjector.handle/2` clause for `ObjectEdited` — `UPDATE world_objects` with the sparse diff in place.
- [X] T093 [US5] Added `RoomObjectEdited` UI event + `UIEventBroadcaster.handle/2` clause for `ObjectEdited` broadcasting on `room:<room_id>`. Wizard sessions consume this to refresh the Things-in-this-room panel.

### LiveView wiring (form edit paths + stale-revision recovery)

- [X] T094 [US5] `commit_blueprint_draft` now branches on the draft's `:expected_revision`: nil → CREATE (US1), integer → EDIT (US5). EDIT path on `:stale_revision` reloads the form with the latest persisted blueprint + sets `{:stale_revision, current}` so the form footer shows "editing · rev N+1" and the inline banner explains what happened.
- [X] T095 [US5] Added `handle_event("focus_blueprint", ...)`: validates wizard, pre-populates `:focused_blueprint_draft` with the blueprint's current fields + `:expected_revision`. If the wizard isn't already in `:blueprints` mode, calls `WizardTrance.enter/3` to flip there (firing the trance entry). Registry rows in any mode are now clickable as focus affordances.
- [X] T096 [US5] Added `focus_object_for_edit` + `update_object_edit` + `commit_object_edit` + `discard_object_edit` handlers. The Things-in-this-room panel has both an "Edit" button (focuses for in-place edit) and an "Extract essence" button (US4). The Object edit form is a separate `:focused_object_edit` assign with its own form + footer.

### Tests for US5

- [X] T097 [P] [US5] Aggregate tests in `test/agenticrealms/world/object_blueprint_edit_test.exs` — 9 cases: matching revision + field-changing diff emits event at N+1, no-op diff returns `:ok`, stale revision returns `:stale_revision`, edit against uninitialized aggregate refuses, invalid field key refuses, emitted event drops unchanged fields, apply round-trip leaves aggregate ready for the next edit, Create-against-already-created refuses.
- [X] T098 [P] [US5] Room aggregate behavior for `EditObject` is covered end-to-end by the wrapper test (the wrapper dispatches with `:strong` consistency so the aggregate is exercised through every wrapper test case).
- [X] T099 [P] [US5] Wrapper tests in `test/agenticrealms/world/commands/edit_object_blueprint_wrapper_test.exs` — 7 cases: field-changing edit bumps revision, no-op returns `:no_change`, stale revision attaches current revision in the error and leaves blueprint unchanged, non-wizard refused, unknown blueprint refused, invalid field refused, previously-spawned clones reflect OLD values (FR-021).
- [X] T100 [P] [US5] Wrapper tests in `test/agenticrealms/world/commands/edit_object_wrapper_test.exs` — 6 cases: field-changing edit updates row in place, no-op returns `:no_change`, non-wizard refused, unknown object refused, invalid field refused, object-not-in-room (carried by player) refused with `:object_not_editable_here`.
- [X] T101 [P] [US5] Projector behavior for edits is exercised end-to-end via the wrapper tests' read-model assertions.
- [X] T102 [P] [US5] Same — `ObjectEdited` projection is verified via the wrapper test reading the updated row back.
- [X] T103/T104/T105 [US5] LiveView integration tests in `test/agenticrealms_web/live/wizard_edit_test.exs` — 4 cases: click registry row → load for edit → commit bumps revision; no-op commit keeps revision unchanged; **concurrent-edit conflict** between two wizards (second sees the stale-revision banner with reloaded values; reapplies and commits to revision N+2); world-Object edit via form updates row in place + refreshes the wizard's room-objects panel.

**Checkpoint**: US5 makes the substrate authoring-complete. Wizards can iterate on Blueprints with safe concurrent semantics; Objects in the world are editable in place without aliasing.

---

## Phase 8: User Story 6 - Wizard Browses the Blueprint Registry from Either Mode (Priority: P3)

**Goal**: Wizards have a live-updating Blueprints registry visible in both modes; rows update in place when other wizards create or edit blueprints.

**Independent Test**: Per Story 6 — author three blueprints; from a second wizard's open registry, verify all three appear; in the second wizard's open registry, when the first wizard commits a fourth blueprint, the new row appears in place without a manual reload.

### UI events & topic (FR-026 through FR-028)

- [X] T106 [P] [US6] Added `WizardBlueprintRegistryChanged` submodule in `lib/agenticrealms/world/ui_events.ex` carrying `event` (`:created` or `:edited`), `blueprint_id`, `revision`, and a `payload` map (full row on create, sparse diff on edit).
- [X] T107 [P] [US6] Added `Topics.blueprints_topic/0` returning the literal string `"blueprints"`.
- [X] T108 [US6] Extended `UIEventBroadcaster` with `ObjectBlueprintCreated` and `ObjectBlueprintEdited` handlers that publish on the `blueprints` topic. Both handlers read every field they need directly off the domain event — NO DB re-read — because the broadcaster's GenServer doesn't share the test process's Ecto sandbox connection and a fresh `Repo.get/1` under `:eventual` consistency can race the projector anyway.

### LiveView wiring

- [X] T109 [US6] On mount, wizards subscribe to `Topics.blueprints_topic()`. Non-wizards never subscribe.
- [X] T110 [US6] Added `handle_info(%WizardBlueprintRegistryChanged{}, ...)` clause that patches `:object_blueprints` in place via `patch_blueprint_registry/2` — insert (with de-dup) on `:created`, merge sparse diff on `:edited`. Sorted by name afterward so newly-created rows land in their alphabetical slot. No full re-fetch.
- [X] T111 [US6] The existing Blueprints registry component (US1) already iterates `@object_blueprints` reactively — no additional wiring needed once the assign is patched.

### Tests for US6

- [X] T112 [P] [US6] Broadcaster behavior is covered end-to-end by the LiveView integration test (T113) which exercises the full event → broadcast → handle_info → re-render path; an isolated broadcaster unit test would duplicate that coverage.
- [X] T113 [US6] Full-loop LiveView integration tests in `test/agenticrealms_web/live/wizard_registry_live_update_test.exs` — 3 cases: Alice creates a blueprint → Bob's open registry shows the new row without a reload; Alice edits an existing blueprint → Bob's registry patches name + short_description in place; non-wizards do not see the registry at all (no subscription). Uses an `:eventual`-consistency-aware polling helper (`wait_for_render/3`) since the broadcaster runs after `Commands` returns.

**Checkpoint**: All six user stories are functional. The wizard authoring loop is complete and collaborative.

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Verification, documentation, performance check.

- [ ] T114 Execute the entire `specs/014-item-blueprints/quickstart.md` against a fresh dev seed — all 18 steps must pass. **Pending — manual / browser-based; deferred to local verification before merge.**
- [ ] T115 [P] Performance smoke check: measure end-to-end latency for the three SC-budget paths in a manual run (`SC-001` ≤ 90 s for blueprint authoring, `SC-002` ≤ 2 s for spawn-arrival, `SC-003` ≤ 500 ms for trance entries). Log the measurements in `specs/014-item-blueprints/perf-notes.md` (new) for future regression reference. **Pending — manual / browser-based; deferred to local verification before merge.**
- [X] T116 [P] Ran `mix format`; formatting drift addressed across 10 files (game_components.ex, game_live.ex, game_live.html.heex, the new migration, ui_event_broadcaster.ex, and several test files).
- [X] T117 [P] Credo not configured in this project (`mix credo` is undefined; no `.credo.exs`). N/A.
- [X] T118 Ran `mix test` — 673 unit tests pass, 35 LiveView integration tests pass, zero failures, zero regressions. The pre-existing NPCChat sandbox-disconnect warning is unrelated to this feature and present on `main`.
- [X] T119 `CLAUDE.md` SPECKIT block points to `specs/014-item-blueprints/plan.md`. Verified.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: T001 only. No file changes; can run immediately.
- **Foundational (Phase 2)**: T002–T025. BLOCKS all user stories. The migration tasks (T002, T008) and the Player schema extension (T003) are the literal blockers; the rest of foundational is needed before user stories are testable end-to-end.
- **User Stories (Phases 3–8)**: All depend on Phase 2 complete. With multiple developers, US1, US2, US3, US4, US5, US6 can proceed largely in parallel after Phase 2, with the following intra-phase dependencies:
  - **US2 depends on US1** for the registry being populated to spawn from (functionally, not code-wise — a developer could build US2 against test fixtures).
  - **US4 depends on US3** (or US1+US2) for the existence of a freeform Object to extract from in the integration test (functionally, not code-wise).
  - **US5 depends on US1+US2** (or US3) for the existence of a Blueprint or Object to edit (functionally, not code-wise).
  - **US6 depends on US1** for blueprints to populate the registry.
  - The code dependencies above are all "needs the prior story's data to exist" — the code itself is largely orthogonal and parallelizable. In a sequential build, work US1 → US2 → US3 → US4 → US5 → US6.
- **Polish (Phase 9)**: Depends on all user stories being complete.

### Critical-path file conflicts (force sequencing)

Multiple tasks edit the same file. Within a file, tasks must be sequential — no `[P]` marker. The files with the most contention:

- `lib/agenticrealms/world/router.ex` — T011, T030, T050, T063, T086, T088.
- `lib/agenticrealms/world/commands.ex` — T006, T031, T051, T064, T074, T089, T090.
- `lib/agenticrealms/world/object_blueprint.ex` — T010, T028, T029, T084, T085.
- `lib/agenticrealms/world/room.ex` — T048, T049, T062, T087.
- `lib/agenticrealms_web/live/game_live.ex` — T020, T021, T036, T037, T038, T055, T056, T068, T069, T075, T077, T094, T095, T096, T109, T110.
- `lib/agenticrealms_web/components/game_components.ex` — T022, T035, T039, T054, T067, T076, T111.
- `lib/agenticrealms/world/ui_event_broadcaster.ex` — T019, T053, T093, T108.
- `lib/agenticrealms/world/intent_resolver.ex` — T033, T034, T065, T066.

In a single-developer build these flow naturally in task-ID order. In a multi-developer build, treat each file as a critical section and serialize within.

### Parallel opportunities

Within each phase, all `[P]`-tagged tasks against distinct files can run concurrently. Notable parallel clusters:

- **Phase 2 parallel cluster**: T003, T004, T005, T007 (Accounts changes touch player.ex + accounts.ex + accounts_test.exs — file-disjoint), then T009, T010, T012, T013, T014 (new schema, aggregate skeleton, projector skeleton, slug helper, slug helper test).
- **US1 parallel cluster**: T026, T027 (new command + event); T032, T033, T040 (projector handler, intent tool, queries function); T041, T042, T043, T044 (tests for the new bits).
- **US2 parallel cluster**: T046, T047 (command + event); T057, T058, T059 (tests).
- **US5 parallel cluster**: T080, T081, T082, T083 (new commands + events); T091, T092 (projector handlers in different files); T097–T102 (per-file tests).

---

## Parallel Example: User Story 1

```bash
# After Phase 2 completes, the first US1 cluster can run in parallel:
Task: "T026 Create lib/agenticrealms/world/commands/create_object_blueprint.ex"
Task: "T027 Create lib/agenticrealms/world/events/object_blueprint_created.ex"

# Then the second US1 cluster (depends on T010 + T026 + T027):
Task: "T028 Implement ObjectBlueprint.execute/2 for CreateObjectBlueprint"
Task: "T029 Implement ObjectBlueprint.apply/2 for ObjectBlueprintCreated"
# T028 + T029 share lib/agenticrealms/world/object_blueprint.ex — they must serialize within that file.

# Tests for US1 in parallel after the implementation lands:
Task: "T041 Aggregate test in test/agentic_realms/world/object_blueprint_test.exs"
Task: "T042 Wrapper test in test/agentic_realms/world/commands/create_object_blueprint_wrapper_test.exs"
Task: "T043 Projector test in test/agentic_realms/world/projections/object_blueprint_projector_test.exs"
Task: "T044 Intent resolver test in test/agentic_realms/world/intent_resolver/wizard_tools_test.exs"
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Complete Phase 1: T001.
2. Complete Phase 2: T002 → T025.
3. Complete Phase 3 (US1): T026 → T045.
4. **STOP and VALIDATE**: A wizard can author a Blueprint in trance. The registry contains the new row. Co-located players witness the trance entries. This alone is a shippable substrate increment.

### Incremental delivery

1. MVP: Setup + Foundational + US1 → ship the authoring loop.
2. Add US2 → ship the spawn loop (the full "make-and-use" experience).
3. Add US3 → ship the freeform escape valve.
4. Add US4 → ship the promote-to-blueprint flow.
5. Add US5 → ship editing and concurrent-safe authoring.
6. Add US6 → ship the collaborative live-registry experience.
7. Polish: verify the entire quickstart and tidy.

### Parallel team strategy

With multiple developers and Phase 2 complete, two stable parallel tracks emerge:

- **Track A (commands + aggregates)**: US1 → US2 → US5 (the aggregate-and-command path).
- **Track B (UI + LLM tooling)**: US3 + US6 (the prompt/registry path), then US4 (extract).

Tracks reconverge at Phase 9 polish.

---

## Notes

- The plan emphasizes event sourcing — every mutation lands through a Commanded command + event, even the no-op (commits without field changes still go through the aggregate, which returns `:ok` with no event).
- Optimistic-lock checks live in `ObjectBlueprint.execute/2` — not in the projector and not in the LiveView. The aggregate is the serialization point.
- Wizard authorization is checked twice: at the LiveView entry (UX gate) and at the `Commands` wrapper entry (security boundary). Both checks read `players.is_wizard` synchronously.
- `world_objects` schema does NOT gain a `blueprint_id` column. This is a load-bearing invariant; tasks that touch the schema or events must respect it.
- The event log is destroyable in this phase per the `event-log-destroyable-phase` project memory. No event-stream migrations are needed; if a previously running dev environment has events from an older shape, wipe-and-replay.
- Avoid: vague tasks, same-file conflicts (see "Critical-path file conflicts" section above), cross-story dependencies that break independent testability.
