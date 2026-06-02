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
- [ ] T006 Add private `ensure_wizard/1` helper to `lib/agenticrealms/world/commands.ex` per `contracts/commands.md` (synchronous `is_wizard` read; returns `:ok` / `{:error, :not_a_wizard}` / `{:error, :unknown_player}`). **Deferred to T031** — the helper triggers `--warnings-as-errors` on the unused-private-function check until the first wrapper consumes it; landing them together avoids a transient broken-compile state.
- [X] T007 [P] Unit tests in `test/agentic_realms/accounts_test.exs`: `promote_to_wizard/1` happy path, idempotency, `{:error, :not_found}` on unknown id.

### Object Blueprint substrate (FR-007, FR-007a, FR-007b, FR-008, FR-009)

- [X] T008 Create migration `priv/repo/migrations/<ts>_create_object_blueprints.exs` per `data-model.md` §1.2 (slug PK with regex CHECK, `kind` CHECK = `'object'`, `revision` CHECK > 0, index on `kind`).
- [X] T009 [P] Create `lib/agenticrealms/world/schemas/object_blueprint.ex` Ecto schema per `data-model.md` §1.2.
- [X] T010 [P] Create `lib/agenticrealms/world/object_blueprint.ex` aggregate struct (fields per `data-model.md` §2.1) — handlers come in later phases.
- [X] T011 Add aggregate identification to `lib/agenticrealms/world/router.ex`: `identify(ObjectBlueprint, by: :blueprint_id, prefix: "object-blueprint-")`. Register dispatch (handler list initially empty; commands added per phase). *(identify only; dispatch list deferred to T030.)*
- [ ] T012 [P] Create `lib/agenticrealms/world/projections/object_blueprint_projector.ex` skeleton (Commanded.Event.Handler module) registered in `lib/agenticrealms/world/application.ex` per plan.md Source Code section. Handler bodies are empty until added in user-story phases. **Deferred to T032** — a projector with zero `handle/2` clauses provokes a compile-time Commanded warning; landing the skeleton with its first handler avoids a transient broken state.
- [X] T013 [P] Slug derivation helper module `lib/agenticrealms/world/object_blueprint/slug.ex` exposing `derive/1` (lowercase + non-alphanumeric → `_` + trim leading/trailing `_`) and `valid?/1` (regex match per FR-007a). Used by both the Commands wrapper and the LiveView form.
- [X] T014 [P] Unit tests in `test/agentic_realms/world/object_blueprint/slug_test.exs`: `derive/1` for common cases including names with punctuation, accents (out of scope — should reject), and length boundaries; `valid?/1` accepts the regex and rejects everything else including UUID-shaped strings.

### Intent resolver context extension (FR-022, FR-023)

- [ ] T015 Extend `lib/agenticrealms/world/intent_resolver/context_snapshot.ex` with the three new fields per `contracts/intent_tools.md`: `authoring_mode`, `focused_object_id`, `focused_blueprint_id` (all default `nil`). Update callers that construct snapshots to default-pass these. **Deferred to US1 T034** — ContextSnapshot is currently a pure string-builder; extending it requires the wizard-mode tool-selection rework, which is US1.

### Mode toggle + trance broadcast infrastructure (FR-001 through FR-006, FR-WIZ-3, FR-WIZ-4)

- [X] T016 [P] ~~Create `lib/agenticrealms/world/events/wizard_entered_trance.ex` per `contracts/events.md` (fields: `wizard_id`, `room_id`, `at`).~~ **Redesigned as a UI event, not a domain event.** Added `RoomTranceEntered` to `lib/agenticrealms/world/ui_events.ex`. Rationale: trance is a UI signal with no world-state implication; routing it through Commanded would require an aggregate just to emit a transient broadcast. See research.md R3 for the original intent and the updated rationale.
- [X] T017 [P] ~~Create `lib/agenticrealms/world/events/wizard_exited_trance.ex` (same shape).~~ Replaced by `RoomTranceExited` UI event in `lib/agenticrealms/world/ui_events.ex`, same rationale as T016.
- [X] T018 Create `lib/agenticrealms/world/wizard_trance.ex` helper module exposing `enter/3` and `exit/3` per `contracts/events.md` "transient — non-aggregate" notes. **Adjusted**: helper calls `Phoenix.PubSub.broadcast/3` directly with the `RoomTranceEntered` / `RoomTranceExited` UI event structs, matching the existing player-arrival broadcast pattern from feature 003.
- [X] T019 [P] ~~Extend `lib/agenticrealms/world/ui_event_broadcaster.ex` with handlers for `WizardEnteredTrance` and `WizardExitedTrance`.~~ **Dropped** — the trance signal is broadcast directly by `WizardTrance` per T018, so the `UIEventBroadcaster` (which subscribes only to persisted domain events) does not need to be involved. The FR-004 suppression is implicit (no broadcast subscribers ⇒ no log entries reach any session); self-suppression (FR-002 "every *other* player session") is enforced by the LiveView `handle_info` self-filter pattern matching the existing `RoomPlayerArrived` flow.
- [X] T020 Extend `lib/agenticrealms_web/live/game_live.ex` mount with: read `Accounts.get_player(player_id).is_wizard`, store as `:is_wizard` assign, initialize `:authoring_mode` to `:world` for wizards (no assign for non-wizards), set up `:focused_object_id` and `:focused_blueprint_id` to `nil`.
- [X] T021 Add LiveView event handler `handle_event("toggle_authoring_mode", _, socket)` to `lib/agenticrealms_web/live/game_live.ex`. Entry-guard `:is_wizard`; flip `:authoring_mode`; on each transition, call `WizardTrance.enter/3` or `.exit/3`. On `:blueprints` → `:world`, clear `:focused_blueprint_id`.
- [X] T022 Extend layout to gate the Wizard/Player top-bar switch on `is_wizard` (FR-WIZ-3). Implementation: `is_wizard` attr added to `Layouts.app`, switch hidden when false. The wizard-view mode toggle button (within the chrome itself) lands alongside the wizard chrome wiring in US1.

### Foundational tests

- [ ] T023 [P] Authorization tests in `test/agentic_realms/world/commands/wizard_authz_test.exs`: `ensure_wizard/1` accepts wizards, refuses non-wizards, refuses unknown player ids. **Deferred to T031** alongside the helper itself.
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

- [ ] T033 [P] [US1] Add the `draft_object_blueprint` tool schema to the tool registry exposed by `lib/agenticrealms/world/intent_resolver.ex` per `contracts/intent_tools.md`. **Deferred to a follow-up session.** Requires extending the existing player-only IntentResolver with a wizard-mode tool dispatcher — substantial refactor not in this implementation run.
- [ ] T034 [US1] Extend `IntentResolver`'s per-mode tool selection. **Deferred** alongside T033.

### LiveView wiring (FR-019 dual-role Interpreted Data card; FR-026 minimal registry)

- [ ] T035 [US1] Extend `lib/agenticrealms_web/components/game_components.ex` with the Interpreted Data card component bound to a `:focused_blueprint_draft` assign. **Deferred** — requires the LLM-driven draft flow from T033/T034 to make the progressive-reveal behavior meaningful.
- [ ] T036 [US1] Add LiveView event handler `handle_event("submit_wizard_prompt", ...)`. **Deferred** alongside T033/T034.
- [ ] T037 [US1] Add LiveView event handler `handle_event("commit_blueprint_draft", _, socket)` (CREATE path). **Deferred** — the form-driven Commit path needs T035's binding to exist.
- [ ] T038 [US1] Add LiveView event handler `handle_event("discard_blueprint_draft", _, socket)`. **Deferred** alongside T037.
- [ ] T039 [P] [US1] Extend `lib/agenticrealms_web/components/game_components.ex` with a minimal Blueprints registry tab. **Deferred** — currently the existing spec 001 mockup chrome still renders mock data; wiring it to `Queries.list_object_blueprints/0` is part of the same UI refactor.
- [X] T040 [P] [US1] Add `list_object_blueprints/0` to `lib/agenticrealms/world/queries.ex` returning `[%ObjectBlueprint{} | _]` ordered by name. Also added `get_object_blueprint/1` for the wrapper's pre-check + future US5 edit-load path.

### Tests for US1

- [X] T041 [P] [US1] Aggregate test in `test/agentic_realms/world/object_blueprint_test.exs`: `CreateObjectBlueprint` against `id: nil` emits `ObjectBlueprintCreated`; against initialized state returns `{:error, :already_exists}`. Apply/2 sets revision = 1.
- [X] T042 [P] [US1] Wrapper test in `test/agentic_realms/world/commands/create_object_blueprint_wrapper_test.exs`: non-wizard refused; invalid slug refused; collision detected via pre-check; happy path dispatches.
- [X] T043 [P] [US1] Projector test in `test/agentic_realms/world/projections/object_blueprint_projector_test.exs`: `ObjectBlueprintCreated` inserts a row; idempotent replay.
- [ ] T044 [P] [US1] Intent resolver test (mocked LLM). **Deferred** alongside T033/T034.
- [ ] T045 [US1] LiveView integration test in `test/agentic_realms_web/live/wizard_authoring_test.exs` (full loop). **Deferred** alongside T033–T038.

**Checkpoint**: User Story 1 is functionally complete. The wizard can author a blueprint end-to-end. This is the MVP.

---

## Phase 4: User Story 2 - Wizard Spawns an Object from a Blueprint into a Room (Priority: P1)

**Goal**: A wizard in World mode can click "Spawn here" on a blueprint registry row and instantiate a copy of it in their current room.

**Independent Test**: Per Story 2 — author a blueprint via US1, walk to a specific room, click Spawn here on the row, verify the Object appears in the co-located player's room view and on their next `look`.

### Commands & events (FR-010, FR-029)

- [ ] T046 [P] [US2] Create `lib/agenticrealms/world/commands/spawn_object_from_blueprint.ex` command struct per `contracts/commands.md`.
- [ ] T047 [P] [US2] Create `lib/agenticrealms/world/events/object_spawned.ex` event struct per `contracts/events.md`. **The event MUST NOT have a `blueprint_id` field** — verify via the `@enforce_keys` list and the `defstruct` shape (FR-013, FR-029).

### Room aggregate extension (FR-010)

- [ ] T048 [US2] Add `Room.execute/2` clause for `SpawnObjectFromBlueprint` in `lib/agenticrealms/world/room.ex`: validate destination is the room the aggregate represents, emit `ObjectSpawned{object_id, room_id, name, short_description, long_description, fixed}`.
- [ ] T049 [US2] Add `Room.apply/2` for `ObjectSpawned` updating in-aggregate object presence state (consistent with the existing object-placement pattern from spec 007).
- [ ] T050 [US2] Register `SpawnObjectFromBlueprint` in the dispatch list for `Room` in `lib/agenticrealms/world/router.ex`.

### Command wrapper (FR-WIZ-5, blueprint-payload stamping)

- [ ] T051 [US2] Implement `Commands.spawn_object_from_blueprint/3` in `lib/agenticrealms/world/commands.ex` per `contracts/commands.md`: authz, resolve `blueprint_id` against read model, stamp the current blueprint payload into the command, generate `object_id`, dispatch.

### Projector & UI broadcast (FR-014)

- [ ] T052 [P] [US2] Extend `lib/agenticrealms/world/projections/world_projector.ex` with a handler for `ObjectSpawned` that inserts a `world_objects` row with the denormalized payload. **Verify the inserted row has NO `blueprint_id` column** (the schema doesn't have one per FR-013).
- [ ] T053 [US2] Extend `lib/agenticrealms/world/ui_event_broadcaster.ex` with an `ObjectSpawned` handler that broadcasts `RoomObjectArrived` on `room:<room_id>` per `contracts/ui_events.md`. The body matches the existing object-arrival pattern from prior features.

### LiveView wiring

- [ ] T054 [US2] Extend the Blueprints registry component in `lib/agenticrealms_web/components/game_components.ex` to render a "Spawn here" button on each row WHEN `:authoring_mode == :world`.
- [ ] T055 [US2] Add LiveView event handler `handle_event("spawn_here", %{"blueprint_id" => bp_id}, socket)` in `lib/agenticrealms_web/live/game_live.ex`: entry-guard wizard + world-mode, dispatch `Commands.spawn_object_from_blueprint/3` with current `room_id`. On `{:ok, _}` push a brief toast.
- [ ] T056 [US2] Add a corresponding handle_info clause for `RoomObjectArrived` in `lib/agenticrealms_web/live/game_live.ex` to keep the wizard's own room view in sync with their spawn (consistent with the existing room-update flow).

### Tests for US2

- [ ] T057 [P] [US2] Aggregate test in `test/agentic_realms/world/room_test.exs`: `SpawnObjectFromBlueprint` emits `ObjectSpawned` with the denormalized payload supplied by the dispatcher; the aggregate does NOT read the blueprint.
- [ ] T058 [P] [US2] Wrapper test in `test/agentic_realms/world/commands/spawn_object_from_blueprint_test.exs`: non-wizard refused; unknown blueprint refused with `:unknown_blueprint`; happy path reads blueprint, stamps, dispatches.
- [ ] T059 [P] [US2] Projector test in `test/agentic_realms/world/projections/world_projector_test.exs`: `ObjectSpawned` → `world_objects` row inserted with payload fields. Assert via row-shape inspection that no `blueprint_id` column exists.
- [ ] T060 [US2] LiveView integration test in `test/agentic_realms_web/live/wizard_authoring_test.exs` (extends US1's test file): after authoring a blueprint, click Spawn here → assert co-located player's log gains the arrival entry and `look` shows the new object → verify the spawned Object's row has no `blueprint_id` (via direct Repo query) per SC-008.

**Checkpoint**: User Stories 1 + 2 together deliver the headline loop — author a blueprint and put copies of it in the world.

---

## Phase 5: User Story 3 - Wizard Creates an Object Freeform in the World (Priority: P2)

**Goal**: A wizard in World mode can prompt an object into being directly in their current room, with no blueprint involvement. The Object is observationally identical to one spawned from a blueprint.

**Independent Test**: Per Story 3 — submit a freeform prompt, click Commit, verify the Object exists in the wizard's current room and the blueprint registry's row count is unchanged.

### Commands (FR-011, FR-012)

- [ ] T061 [P] [US3] Create `lib/agenticrealms/world/commands/spawn_object_freeform.ex` command struct per `contracts/commands.md`.

### Room aggregate extension

- [ ] T062 [US3] Add `Room.execute/2` clause for `SpawnObjectFreeform` in `lib/agenticrealms/world/room.ex` emitting `ObjectSpawned` with the wizard-supplied payload — **identical event shape to the blueprint path** (FR-012).
- [ ] T063 [US3] Register `SpawnObjectFreeform` in the dispatch list for `Room` in `lib/agenticrealms/world/router.ex`.

### Command wrapper

- [ ] T064 [US3] Implement `Commands.spawn_object_freeform/3` in `lib/agenticrealms/world/commands.ex`: authz, generate `object_id`, dispatch. **No blueprint involvement** — confirms no synthetic-blueprint scaffolding per the clarification in Q-freeform.

### LLM intent tool

- [ ] T065 [P] [US3] Add the `manifest_object_freeform` tool schema to the tool registry in `lib/agenticrealms/world/intent_resolver.ex` per `contracts/intent_tools.md`.
- [ ] T066 [US3] Extend the per-mode tool selection in `lib/agenticrealms/world/intent_resolver.ex`: when actor is a wizard AND `authoring_mode == :world`, the tool set includes BOTH `manifest_object_freeform` AND `spawn_object_from_blueprint` alongside the existing player tools. The resolver chooses between freeform vs blueprint-spawn based on whether the LLM matches a known blueprint by name (the prompt-vs-registry resolution).

### LiveView wiring

- [ ] T067 [US3] Wire the world-mode prompt textarea in `lib/agenticrealms_web/components/game_components.ex` (wizard view, World mode) to route through `IntentResolver` with `authoring_mode: :world` context.
- [ ] T068 [US3] In `lib/agenticrealms_web/live/game_live.ex`, extend `handle_event("submit_wizard_prompt", ...)` to handle the world-mode branch: a `manifest_object_freeform` tool call populates `:focused_object_draft`; a `spawn_object_from_blueprint` tool call dispatches immediately (no intermediate draft form — the registry-row Spawn-here path is for explicit, the prompt is the convenience path).
- [ ] T069 [US3] Add LiveView event handler `handle_event("commit_object_creation", _, socket)` dispatching `Commands.spawn_object_freeform/3` with the draft's fields + current room_id. On `{:ok, _}` clear the draft.

### Tests for US3

- [ ] T070 [P] [US3] Aggregate test in `test/agentic_realms/world/room_test.exs` (extends US2's tests): `SpawnObjectFreeform` emits `ObjectSpawned` with the wizard-supplied payload — verify shape matches the blueprint path's event byte-for-byte except for the payload values.
- [ ] T071 [P] [US3] Wrapper test in `test/agentic_realms/world/commands/spawn_object_freeform_test.exs`: non-wizard refused; happy path dispatches with no blueprint involvement.
- [ ] T072 [P] [US3] Intent resolver test in `test/agentic_realms/world/intent_resolver/wizard_tools_test.exs` (extends US1's file): world-mode + wizard + prompt describing an object → routes to `manifest_object_freeform`; world-mode + wizard + prompt naming an existing blueprint → routes to `spawn_object_from_blueprint`. World-mode + non-wizard → existing player tools only (no `manifest_object_freeform`).
- [ ] T073 [US3] LiveView integration test in `test/agentic_realms_web/live/wizard_authoring_test.exs` (extends prior US tests): from World mode, submit a freeform prompt → click Commit → assert Object exists in the room AND assert `object_blueprints` row count is unchanged (per Story 3 Acc 1).

**Checkpoint**: US3 demonstrates the equivalence-by-design — Objects from blueprints and Objects from freeform are observationally indistinguishable.

---

## Phase 6: User Story 4 - Wizard Extracts Essence from a World Object into a New Blueprint (Priority: P2)

**Goal**: A wizard can click Extract essence on a focused world Object; the wizard is flipped into Sanctum with a draft Blueprint pre-populated wholesale from the source object's fields; Commit creates the Blueprint; the source Object is unmodified.

**Independent Test**: Per Story 4 — create a freeform Object, focus it, Extract essence, verify the wizard mode flipped, the draft fields match the source, Commit produces a Blueprint, and the source Object's fields are byte-identical to before.

### Extract action (FR-015 through FR-018)

- [ ] T074 [US4] Implement `Commands.extract_object_essence/3` wrapper in `lib/agenticrealms/world/commands.ex` per `contracts/commands.md`: authz, read source object, validate proposed slug, dispatch `CreateObjectBlueprint` with wholesale-copied payload. Returns `{:ok, blueprint_id}` on success.

### LiveView wiring

- [ ] T075 [US4] Add `handle_event("focus_object", %{"object_id" => oid}, socket)` in `lib/agenticrealms_web/live/game_live.ex`: entry-guard wizard + world-mode; set `:focused_object_id`; load the object's payload into `:focused_object` for the focused-object panel.
- [ ] T076 [US4] Extend `lib/agenticrealms_web/components/game_components.ex` with a focused-object panel rendered in wizard World mode showing the editable fields and an **Extract essence** button (FR-015). The form-edit pieces here are placeholders; full editing wires up in US5.
- [ ] T077 [US4] Add `handle_event("extract_essence", _, socket)` in `lib/agenticrealms_web/live/game_live.ex`: derive proposed slug from the focused object's name via the helper from T013; dispatch `Commands.extract_object_essence/3`. On `{:ok, blueprint_id}`: flip `:authoring_mode` to `:blueprints` via `WizardTrance.enter/2`, load the new blueprint into `:focused_blueprint`, render the form pre-populated with the source object's fields.

### Tests for US4

- [ ] T078 [P] [US4] Wrapper test in `test/agentic_realms/world/commands/extract_object_essence_test.exs`: non-wizard refused; unknown object refused with `:unknown_object`; invalid slug refused with `:invalid_slug`; collision refused with `:slug_already_exists`; happy path dispatches `CreateObjectBlueprint` with the source object's fields; assert source object's row is unchanged after the call.
- [ ] T079 [US4] LiveView integration test in `test/agentic_realms_web/live/wizard_authoring_test.exs` (extends prior US tests): create a freeform Object → click Extract essence → assert wizard flipped to Sanctum + trance entry fired + form pre-populated with source fields → Commit → assert new Blueprint exists at revision 1 + source object's fields byte-identical to before.

**Checkpoint**: US4 closes the manifest → recognize-as-archetype → reuse loop. Wizards can mint blueprints from anything they've already made.

---

## Phase 7: User Story 5 - Wizard Edits an Existing Blueprint or Object via the Form Editor (Priority: P2)

**Goal**: Wizards can edit Blueprints and Objects directly via the Interpreted Data form, with optimistic locking on Blueprints; edits to Blueprints do not affect previously spawned Objects.

**Independent Test**: Per Story 5 — author a Blueprint, focus it from the registry, change one field via the form, click Commit. Verify (a) revision bumps to 2, (b) any previously spawned Objects keep their original field values, (c) the form can edit again to revision 3.

### Commands & events (FR-020, FR-020a, FR-031, FR-032)

- [ ] T080 [P] [US5] Create `lib/agenticrealms/world/commands/edit_object_blueprint.ex` command struct per `contracts/commands.md` (carries `expected_revision`).
- [ ] T081 [P] [US5] Create `lib/agenticrealms/world/events/object_blueprint_edited.ex` event struct per `contracts/events.md`.
- [ ] T082 [P] [US5] Create `lib/agenticrealms/world/commands/edit_object.ex` command struct per `contracts/commands.md`.
- [ ] T083 [P] [US5] Create `lib/agenticrealms/world/events/object_edited.ex` event struct per `contracts/events.md`.

### Aggregate handlers (optimistic lock at aggregate boundary — FR-020a, FR-020b)

- [ ] T084 [US5] Implement `ObjectBlueprint.execute/2` clause for `EditObjectBlueprint` in `lib/agenticrealms/world/object_blueprint.ex` per `data-model.md` §2.1: (1) if `expected_revision != revision`, return `{:error, :stale_revision, current_revision: revision}`; (2) if `fields_changed` is empty or every field equals current state, return `:ok` (no event); (3) otherwise emit `ObjectBlueprintEdited` with `revision: revision + 1`.
- [ ] T085 [US5] Implement `ObjectBlueprint.apply/2` for `ObjectBlueprintEdited` applying the `fields_changed` diff and setting `revision = new_revision`.
- [ ] T086 [US5] Register `EditObjectBlueprint` in the dispatch list for `ObjectBlueprint` in `lib/agenticrealms/world/router.ex`.
- [ ] T087 [US5] Add `Room.execute/2` clause for `EditObject` in `lib/agenticrealms/world/room.ex`: validate the object is currently in this room (lookup against `world_objects.room_id`); validate `fields_changed` keys; emit `ObjectEdited{object_id, fields_changed}`. No-op diff returns `:ok`.
- [ ] T088 [US5] Register `EditObject` in the dispatch list for `Room` in `lib/agenticrealms/world/router.ex`.

### Command wrappers

- [ ] T089 [US5] Implement `Commands.edit_object_blueprint/3` in `lib/agenticrealms/world/commands.ex` per `contracts/commands.md`: authz, existence check, validate `fields_changed` allowed keys, dispatch.
- [ ] T090 [US5] Implement `Commands.edit_object/3` in `lib/agenticrealms/world/commands.ex` per `contracts/commands.md`: authz, resolve object's room, validate co-location with wizard's current room, validate keys, dispatch.

### Projector handlers

- [ ] T091 [P] [US5] Extend `lib/agenticrealms/world/projections/object_blueprint_projector.ex` with `ObjectBlueprintEdited` handler: `UPDATE WHERE id = $1 AND revision < $2` applying the diff (idempotent replay).
- [ ] T092 [P] [US5] Extend `lib/agenticrealms/world/projections/world_projector.ex` with `ObjectEdited` handler applying the diff to the matching `world_objects` row.
- [ ] T093 [US5] Extend `lib/agenticrealms/world/ui_event_broadcaster.ex` with an `ObjectEdited` handler broadcasting `RoomObjectEdited` on `room:<room_id>` per `contracts/ui_events.md` ("RoomObjectEdited" entry — quiet, no log entry, just refreshes the entity list).

### LiveView wiring (form edit paths + stale-revision recovery)

- [ ] T094 [US5] Extend `handle_event("commit_blueprint_draft", _, socket)` in `lib/agenticrealms_web/live/game_live.ex` to add the EDIT path: when `:focused_blueprint_id` is set on the assigns, dispatch `Commands.edit_object_blueprint/3` with the captured `expected_revision`. On `{:error, :stale_revision, current_revision: N}`, re-read the blueprint at the new revision, re-render the form with the latest values, surface a banner explaining the stale-write and asking the wizard to reapply over the newer state.
- [ ] T095 [US5] Add `handle_event("focus_blueprint", %{"blueprint_id" => bp_id}, socket)` in `lib/agenticrealms_web/live/game_live.ex`: entry-guard wizard; if `:authoring_mode != :blueprints`, flip via `WizardTrance.enter/2`; load the blueprint into `:focused_blueprint` with the current `revision` captured for the optimistic lock.
- [ ] T096 [US5] Add `handle_event("commit_object_edit", _, socket)` in `lib/agenticrealms_web/live/game_live.ex` dispatching `Commands.edit_object/3` with the focused-object form's diff.

### Tests for US5

- [ ] T097 [P] [US5] Aggregate test in `test/agentic_realms/world/object_blueprint_test.exs` (extends US1's file): `EditObjectBlueprint` with matching revision + non-empty diff emits `ObjectBlueprintEdited` at revision N+1; with no-op diff returns `:ok`; with mismatched revision returns `:stale_revision`.
- [ ] T098 [P] [US5] Aggregate test in `test/agentic_realms/world/room_test.exs` (extends US2's file): `EditObject` against a room containing the object emits `ObjectEdited` with the diff; against a room NOT containing the object returns `:object_not_in_room`; no-op diff returns `:ok`.
- [ ] T099 [P] [US5] Wrapper test in `test/agentic_realms/world/commands/edit_object_blueprint_test.exs`: non-wizard refused; unknown blueprint refused; happy path dispatches.
- [ ] T100 [P] [US5] Wrapper test in `test/agentic_realms/world/commands/edit_object_wrapper_test.exs`: non-wizard refused; object in a different room refused with `:object_not_editable_here`; object in the wizard's current room dispatches.
- [ ] T101 [P] [US5] Projector test in `test/agentic_realms/world/projections/object_blueprint_projector_test.exs` (extends US1's file): `ObjectBlueprintEdited` updates the row and bumps revision; idempotent replay guarded by `revision < $2`.
- [ ] T102 [P] [US5] Projector test in `test/agentic_realms/world/projections/world_projector_test.exs` (extends US2's file): `ObjectEdited` updates `world_objects` row in place.
- [ ] T103 [US5] LiveView integration test in `test/agentic_realms_web/live/wizard_authoring_test.exs` (extends prior US tests): edit a Blueprint via the form → registry shows revision 2; spawn an Object from it (revision 2 values); edit the Blueprint again to revision 3; assert the existing Objects from revision 1 / revision 2 are UNCHANGED.
- [ ] T104 [US5] LiveView integration test in `test/agentic_realms_web/live/wizard_authoring_test.exs`: focus a world Object, edit via form, Commit; assert the co-located player's next examine shows the new long_description.
- [ ] T105 [US5] Concurrent-edit LiveView integration test in `test/agentic_realms_web/live/blueprint_optimistic_lock_test.exs`: two LiveView clients both focus the same Blueprint at revision N; first commits (→ N+1); second's commit returns stale-revision; second's form reloads with revision N+1 + the first wizard's changes; second reapplies and commits successfully to revision N+2.

**Checkpoint**: US5 makes the substrate authoring-complete. Wizards can iterate on Blueprints with safe concurrent semantics; Objects in the world are editable in place without aliasing.

---

## Phase 8: User Story 6 - Wizard Browses the Blueprint Registry from Either Mode (Priority: P3)

**Goal**: Wizards have a live-updating Blueprints registry visible in both modes; rows update in place when other wizards create or edit blueprints.

**Independent Test**: Per Story 6 — author three blueprints; from a second wizard's open registry, verify all three appear; in the second wizard's open registry, when the first wizard commits a fourth blueprint, the new row appears in place without a manual reload.

### UI events & topic (FR-026 through FR-028)

- [ ] T106 [P] [US6] Create `lib/agenticrealms_web/ui_events/wizard_blueprint_registry_changed.ex` UI event struct per `contracts/ui_events.md`.
- [ ] T107 [P] [US6] Add `blueprints_topic/0` helper to `lib/agenticrealms_web/topics.ex` returning the string `"blueprints"`.
- [ ] T108 [US6] Extend `lib/agenticrealms/world/ui_event_broadcaster.ex` with handlers for `ObjectBlueprintCreated` (`event: :created`) and `ObjectBlueprintEdited` (`event: :edited`) broadcasting `WizardBlueprintRegistryChanged` on the `blueprints` topic.

### LiveView wiring

- [ ] T109 [US6] In `lib/agenticrealms_web/live/game_live.ex` mount, for wizards subscribe to `AgenticRealmsWeb.Topics.blueprints_topic()`. (Non-wizards do not subscribe.)
- [ ] T110 [US6] Add `handle_info/2` for `%WizardBlueprintRegistryChanged{}` in `lib/agenticrealms_web/live/game_live.ex`: patch the `:object_blueprints` assign in place — insert for `:created`, update-row for `:edited`. No full reload.
- [ ] T111 [US6] Extend the Blueprints registry component in `lib/agenticrealms_web/components/game_components.ex` to render via the assigns reactively so the LiveView's handle_info patch is reflected without explicit re-fetch.

### Tests for US6

- [ ] T112 [P] [US6] UIEventBroadcaster test in `test/agentic_realms/world/ui_event_broadcaster_test.exs`: `ObjectBlueprintCreated` triggers a `WizardBlueprintRegistryChanged{event: :created}` PubSub publish on the `blueprints` topic with the expected payload. `ObjectBlueprintEdited` triggers `event: :edited` with the new revision.
- [ ] T113 [US6] LiveView integration test in `test/agentic_realms_web/live/wizard_registry_live_update_test.exs`: two wizard LiveView clients open the registry; wizard A commits a new blueprint; wizard B's assigns reflect the new row within the live-witness latency budget without a manual reload.

**Checkpoint**: All six user stories are functional. The wizard authoring loop is complete and collaborative.

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Verification, documentation, performance check.

- [ ] T114 Execute the entire `specs/014-item-blueprints/quickstart.md` against a fresh dev seed — all 18 steps must pass.
- [ ] T115 [P] Performance smoke check: measure end-to-end latency for the three SC-budget paths in a manual run (`SC-001` ≤ 90 s for blueprint authoring, `SC-002` ≤ 2 s for spawn-arrival, `SC-003` ≤ 500 ms for trance entries). Log the measurements in `specs/014-item-blueprints/perf-notes.md` (new) for future regression reference.
- [ ] T116 [P] Run `mix format --check-formatted` and address any drift in this branch.
- [ ] T117 [P] Run `mix credo` (if configured) on the new modules; address any new findings introduced by this branch.
- [ ] T118 Run the full `mix test` suite and confirm green; investigate any test ordering / DB-state issues that the new aggregates may have surfaced.
- [ ] T119 Verify `CLAUDE.md` SPECKIT block points to `specs/014-item-blueprints/plan.md` (already updated during planning; this is a re-check).

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
