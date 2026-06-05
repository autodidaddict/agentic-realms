---
description: "Task list for feature 015 — wizard-created NPC blueprints (milestone 2)"
---

# Tasks: Wizard-Created NPC Blueprints (Milestone 2)

**Input**: Design documents from `/specs/015-npc-blueprints/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md (all present)

**Tests**: Included throughout — the spec enumerates a release-blocking test surface (non-regression
of features 007–010 + 016, plus the new authoring behavior).

**Built on the merged substrate**: spec 016 (clone/move/containment) is shipped — spawning an NPC is
`clone_into(:npc, …)`, in-place clone edit is `EditEntity`, and the feature-008 fold-in is done. This
milestone is **pure NPC authoring** mirroring the feature-014 object-blueprint pipeline.

**Organization**: by user story (US1–US8 from spec.md). Setup/Foundational/Polish carry no story label.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: parallelizable (different files, no incomplete deps)
- Paths repo-root-relative; existing single Phoenix layout.

## Path conventions
- Code: `lib/agenticrealms/world/...`, `lib/agenticrealms_web/...` · Tests: `test/agenticrealms/...`
- Migrations: `priv/repo/migrations/`

---

## Phase 1: Setup

- [X] T001 Confirm clean baseline on `015-npc-blueprints` (rebased on merged 016): `mix deps.get`, `mix compile --warnings-as-errors`, `mix test` all green before changes.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: schema + toolset substrate that every story needs. ⚠️ No user story starts until done.

- [X] T002 [P] Migration `priv/repo/migrations/<ts>_extend_npc_blueprints_authoring.exs`: add `kind` (string NOT NULL DEFAULT `'npc'`, CHECK `= 'npc'`), `fixed` (bool NOT NULL DEFAULT false), `toolsets` (`{:array,:string}` NOT NULL DEFAULT `[]`), `revision` (int NOT NULL DEFAULT 1, CHECK `> 0`); slug-shape CHECK on `id`; index on `kind`. (data-model §1.1)
- [X] T003 [P] Migration `priv/repo/migrations/<ts>_extend_npc_clones_authoring.exs`: add `fixed` (bool NOT NULL DEFAULT false), `toolsets` (`{:array,:string}` DEFAULT `[]`), `direct_behaviors` (`{:array,:map}` DEFAULT `[]`). (data-model §1.2)
- [X] T004 [P] Migration `priv/repo/migrations/<ts>_create_toolsets.exs`: `toolsets` table — `name` (string PK, slug CHECK), `description` (string NULL), `behaviors` (`{:array,:map}` NOT NULL DEFAULT `[]`), `applies_to` (`{:array,:string}` NOT NULL DEFAULT `['npc']`, CHECK each ∈ {item,npc,room}), timestamps. (data-model §1.3)
- [X] T005 [P] Update `lib/agenticrealms/world/schemas/npc_blueprint.ex` — add `kind`, `fixed`, `toolsets`, `revision`.
- [X] T006 [P] Update `lib/agenticrealms/world/schemas/npc_clone.ex` — add `fixed`, `toolsets`, `direct_behaviors`.
- [X] T007 [P] Create `lib/agenticrealms/world/schemas/toolset.ex` Ecto schema (data-model §1.3).
- [X] T008 Create `lib/agenticrealms/world/toolsets.ex` service — `list/0`, `list_for/1`, `resolve/1` (`{:error, {:unknown_toolset, name}}` per FR-018), `compose/2` (additive, attachment-ordered, lossless — R4), `validate_behaviors/1` (feature-009 vocabulary, FR-014).
- [X] T009 [P] Unit tests `test/agenticrealms/world/toolsets_test.exs` — resolve unknown→error; compose union of two toolsets ++ direct in order, no dupes dropped; behavior-vocabulary rejection; `applies_to` accepts `item`/`room` values (cross-entity model, FR-019).
- [X] T010 Create `lib/agenticrealms/world/projections/npc_blueprint_projector.ex` (`:strong`) with the `NPCBlueprintCreated` handler (insert `npc_blueprints` incl. kind/fixed/toolsets/revision, `on_conflict: :nothing`); `NPCBlueprintEdited` handler added in US7. Supervise in `application.ex` + `data_case.ex`. (data-model §5)
- [X] T011 Extend `EntityProjector` `:npc` `EntityCloned` insert (`lib/agenticrealms/world/projections/entity_projector.ex`) to carry `fixed`, `toolsets`, `direct_behaviors` from the cloned `fields`.
- [X] T012 Seed ≥2 named toolsets (e.g. `orc`, `shopkeeper`) in `lib/agenticrealms/world/seed.ex` so US4 is demonstrable from a fresh world (FR-014a).
- [X] T013 [P] Confirm `mix world.reset` seeds cleanly (toolsets present, existing NPCs unaffected).

**Checkpoint**: schema + toolset substrate ready; suite green.

---

## Phase 3: User Story 1 — Author an NPC Blueprint in Trance (Priority: P1) 🎯 MVP

**Goal**: author an NPC blueprint (name/short/long/lore/behaviors/toolsets) via trance prompt, commit at revision 1.
**Independent Test**: promote→trance→describe a character→card populates (incl. lore + proposed toolsets)→Commit→`npc`-kind blueprint at `revision: 1`.

- [X] T014 [P] [US1] Alter `lib/agenticrealms/world/commands/create_npc_blueprint.ex` — add `wizard_id, kind, fixed, toolsets`.
- [X] T015 [P] [US1] Alter `lib/agenticrealms/world/events/npc_blueprint_created.ex` — add `kind, fixed, toolsets, revision`.
- [X] T016 [US1] `NPCBlueprint.execute/2` for `CreateNPCBlueprint` (`lib/agenticrealms/world/npc_blueprint.ex`): emit `NPCBlueprintCreated` with `kind: "npc"`, `fixed`, `toolsets`, `revision: 1`; `apply/2` sets them.
- [X] T017 [US1] `Commands.create_npc_blueprint/2` (`lib/agenticrealms/world/commands.ex`): `ensure_wizard`; slug regex + uniqueness **across object + npc** blueprints (FR-004); `Toolsets.validate_behaviors` + toolset-existence checks; dispatch `:strong`.
- [X] T018 [P] [US1] Add `draft_npc_blueprint` + `list_toolsets` tool schemas to `lib/agenticrealms/world/intent_resolver/wizard_tools.ex`; the LLM chooses npc-vs-object by whether the prompt describes a character.
- [X] T019 [US1] `IntentResolver` (`lib/agenticrealms/world/intent_resolver.ex`): extend `:blueprints`-mode resolve to return `{:ok, {:draft_npc_blueprint, fields}}` (name/short/long/lore/fixed/behaviors/toolsets); ground toolset proposals via `list_toolsets`.
- [ ] T020 [US1] `GameLive` (`lib/agenticrealms_web/live/game_live.ex` + `game_live/wizard.ex`): draft assign gains `:kind`; `submit_wizard_prompt` npc path; `commit_blueprint_draft` branches `create_object_blueprint` vs `create_npc_blueprint`; auto-derive slug.
- [ ] T021 [US1] `GameComponents` wizard view (`lib/agenticrealms_web/components/game/wizard_authoring.ex`): NPC draft form — lore textarea, direct-behaviors editor, **toolset picker** pre-selected from the LLM proposal, editable before commit (FR-020/FR-020a).
- [X] T022 [US1] `UIEventBroadcaster`: `NPCBlueprintCreated` → `WizardBlueprintRegistryChanged` on the `blueprints` topic (reuse feature 014).
- [X] T023 [P] [US1] Aggregate tests `test/agenticrealms/world/npc_blueprint_test.exs` — create emits `NPCBlueprintCreated` kind/fixed/toolsets/revision 1; already-exists refusal.
- [X] T024 [P] [US1] Projector tests — `NPCBlueprintCreated` row insert (kind/fixed/toolsets/revision), replay idempotent.
- [X] T025 [P] [US1] Wrapper tests — slug uniqueness **spans object + npc** tables; non-wizard refusal; unknown-toolset + bad-behavior refusal.
- [ ] T026 [US1] LiveView test `test/agenticrealms_web/live/wizard_npc_authoring_test.exs` (mocked LLM) — draft populates incl. toolsets; commit → registry shows the npc blueprint.

**Checkpoint**: MVP — a wizard can author an NPC blueprint.

---

## Phase 4: User Story 2 — Spawn an NPC from a Blueprint into a Room (Priority: P1)

**Goal**: spawn a clone from a blueprint via clone/move; co-present players witness arrival; behaviors/lore inherited.
**Independent Test**: "Spawn here" on a registry row → clone in room; arrival witnessed; `look` shows long desc; greeting fires; `chat` replies in character.

- [ ] T027 [US2] `Commands.spawn_npc_from_blueprint/3` (`commands.ex`): generalize the 016 `spawn_npc_clone/3` — read blueprint, `Toolsets.compose(toolsets, direct_behaviors)` → effective behaviors, `clone_into(:npc, %{… behaviors: effective, toolsets, direct_behaviors, lore, fixed, blueprint_id}, room, :spawned)`; pre-check room + per-room name collision (FR-013). **Update the seed call site** (`seed.ex` calls `spawn_npc_clone/3`) — either rename to `spawn_npc_from_blueprint/3` (seeded NPCs have no toolsets, so `compose([], behaviors)` is unchanged) or keep `spawn_npc_clone/3` as a thin shim — so `mix world.reset` stays green.
- [ ] T028 [US2] `GameLive`: "Spawn here" action on an NPC registry row → `spawn_npc_from_blueprint`.
- [ ] T029 [P] [US2] Wrapper/integration tests — spawn places a clone in the room (effective behaviors = composed); per-room name-collision refusal.
- [ ] T030 [US2] Integration test — co-present player sees `RoomNPCArrived`; `look <npc>` long description; greeting behavior fires (009); `chat <npc>` in-character reply grounded in lore (010).
- [ ] T031 [P] [US2] Full-copy test (standalone — does not depend on US7's edit command): spawn a clone, snapshot its fields, then mutate the source `npc_blueprints` row directly via Ecto, and assert the spawned clone's row is unchanged (FR-009/SC-003). (US7's T051 additionally exercises this through the real `EditNPCBlueprint` path.)

---

## Phase 5: User Story 3 — Existing NPCs Survive the Fold-In (Priority: P1, ✅ delivered by 016)

**Goal**: the 015 changes do not regress any feature-007–010 NPC behavior. (The fold-in itself shipped in spec 016.)
**Independent Test**: fresh world — seeded NPCs render/examine/ungettable/greet/converse unchanged; 007–010 suites pass.

- [ ] T032 [US3] Run features 007/008/009/010 suites + the 016 NPC tests after the Phase 2–4 changes; confirm green (mechanical updates only).
- [ ] T033 [US3] Fresh-world `mix world.reset` walkthrough — Garrick appears, examines, is ungettable, greets on entry, and `chat` replies in character.

---

## Phase 6: User Story 4 — Compose Toolsets onto an NPC Blueprint (Priority: P2)

**Goal**: attach ≥1 toolset + direct behaviors; effective set = union; "orc shopkeeper" by stacking.
**Independent Test**: attach two seeded toolsets + a direct behavior → effective = union (no dupes dropped); spawned clone exhibits all.

- [ ] T034 [US4] Verify the authoring card supports **toolsets AND direct behaviors together** (FR-015/FR-015a) — picker + direct-behavior editor both committable; refuse unknown toolset names (FR-018).
- [ ] T035 [P] [US4] Composition tests — blueprint with two toolsets → effective = union; toolset + direct combined; same-trigger behaviors all retained (FR-016); spawned clone exhibits both toolsets' behaviors.
- [ ] T036 [P] [US4] No-retro-propagation test — editing a toolset (seed-level) after a clone spawned leaves the clone's frozen effective behaviors unchanged (FR-017).

---

## Phase 7: User Story 5 — Freeform One-Off NPC (Priority: P2)

**Goal**: describe an NPC directly into the room with no blueprint.
**Independent Test**: `:world`-mode freeform prompt → NPC in room; no blueprint row added.

- [ ] T037 [P] [US5] Add `manifest_npc_freeform` tool to `wizard_tools.ex`; `:world` resolve returns `{:ok, {:freeform_npc, fields}}`.
- [ ] T038 [US5] `Commands.spawn_npc_freeform/3` (`commands.ex`): `ensure_wizard`; `clone_into(:npc, attrs, room, :spawned)` (no `blueprint_id`).
- [ ] T039 [US5] `GameLive` `:world` npc-freeform commit path.
- [ ] T040 [P] [US5] Tests — freeform NPC appears in room; no `npc_blueprints` row added; observationally identical to a blueprint-spawned clone.

---

## Phase 8: User Story 6 — Extract a Blueprint from an In-World NPC (Priority: P2)

**Goal**: distill a new NPC blueprint from a world clone; source untouched.
**Independent Test**: "Extract essence" on a clone → trance card pre-fills (incl. toolsets/behaviors/lore) → commit → new blueprint at revision 1; source clone unchanged.

- [ ] T041 [US6] `Commands.extract_npc_essence/3` (`commands.ex`): `ensure_wizard`; read clone (`name/short/long/lore/fixed/toolsets/direct_behaviors`); `create_npc_blueprint` at revision 1; source clone untouched.
- [ ] T042 [US6] `GameLive` "Extract essence" action on an in-world NPC → flip to trance, pre-populate the npc draft.
- [ ] T043 [P] [US6] Tests — extracted draft fields == source clone (incl. toolset composition); commit → new blueprint revision 1; source clone byte-for-byte unchanged (FR-012/SC-005).

---

## Phase 9: User Story 7 — Edit an NPC Blueprint or In-World NPC (Priority: P2)

**Goal**: revision-tracked, optimistically-locked blueprint edits; in-place clone edits; no retro-propagation.
**Independent Test**: edit blueprint lore → revision N→N+1; concurrent stale edit refused; edit a clone field → only that clone changes.

- [ ] T044 [P] [US7] Create `lib/agenticrealms/world/commands/edit_npc_blueprint.ex` (`blueprint_id, wizard_id, expected_revision, fields_changed`) + event `events/npc_blueprint_edited.ex`.
- [ ] T045 [US7] `NPCBlueprint.execute/2` `EditNPCBlueprint` clause — optimistic lock (`:stale_revision`), editable-field allowlist (`:invalid_field`), no-op skip, `revision: N+1`; `apply/2` merge. (mirror `ObjectBlueprint`)
- [ ] T046 [US7] `NPCBlueprintProjector` `NPCBlueprintEdited` handler — sparse merge + revision, replay-guard.
- [ ] T047 [US7] `Commands.edit_npc_blueprint/3` wrapper (authz; surfaces stale revision).
- [ ] T048 [US7] Wire `EntityProjector` `:npc` `EntityEdited` branch (currently no-op) to apply the sparse diff to `npc_clones`; add `Commands.edit_npc/3` (`ensure_wizard` + co-location → `EditEntity`).
- [ ] T049 [US7] `GameLive`: focus/edit an NPC blueprint (form) + edit an in-world NPC clone in place.
- [ ] T050 [P] [US7] Aggregate edit tests `test/agenticrealms/world/npc_blueprint_edit_test.exs` — revision bump on change, no-op `:ok`, `:stale_revision`, `:invalid_field`.
- [ ] T051 [P] [US7] Integration tests — concurrent blueprint edit (second gets stale-revision); in-place clone edit changes only that clone; blueprint edit does not alter previously-spawned clones (FR-009/FR-017).

---

## Phase 10: User Story 8 — Unified Blueprint Registry (Priority: P3)

**Goal**: registry lists object + npc blueprints, kind-filterable; affordances per kind.
**Independent Test**: with both kinds present, registry shows both with kind; filter `npc` shows only NPC; "Spawn here" on an npc row spawns an NPC.

- [X] T052 [US8] `Queries.list_blueprints/0` + `list_blueprints(kind)` (`queries.ex`): UNION over `object_blueprints` + `npc_blueprints` projecting `(id, kind, name, short_description, revision)` (FR-024/FR-025).
- [ ] T053 [US8] `GameComponents` registry: show each row's kind, a kind filter, and kind-appropriate spawn/edit affordances (FR-026).
- [ ] T054 [P] [US8] Tests — union lists both kinds; kind filter; npc row "Spawn here" yields an NPC clone (not an object).

---

## Phase 11: Polish & Cross-Cutting

- [ ] T055 Full non-regression gate: `mix test` green incl. 006/007/008/009/010/013/014/016 + the new 015 suites; `mix compile --warnings-as-errors` clean.
- [ ] T056 Execute `specs/015-npc-blueprints/quickstart.md` (sections A–E) against a fresh `mix world.reset` dev seed; record results.
- [ ] T057 [P] `mix format`; tidy any docstrings referencing pre-substrate NPC spawn.

---

## Dependencies & Execution Order

- **Setup (P1)** → **Foundational (P2)** block everything.
- **US1 (Phase 3)** is the MVP (author a blueprint); **US2 (Phase 4)** depends on US1 + foundational compose.
- **US3 (Phase 5)** is non-regression verification (fold-in shipped in 016) — re-run after each phase.
- **US4–US7 (Phases 6–9)** depend on US1/US2; **US7 edit** is referenced by US2's full-copy test.
- **US8 (Phase 10)** depends on both blueprint kinds existing.
- **Polish (Phase 11)** last.

## Parallel Execution Examples
- **Foundational**: T002–T007 (migrations + schemas, distinct files) run `[P]`; then T008 (service) → T009 tests.
- **US1**: T014/T015/T018 `[P]` (command/event/tools); T023–T026 tests `[P]` once targets exist.

## Implementation Strategy
- **MVP = Phases 1–4**: foundational + author (US1) + spawn (US2) — a wizard authors and places an NPC.
- **Increment 2 = Phases 5–9**: non-regression + toolsets + freeform + extract + edit.
- **Increment 3 = Phase 10**: unified registry.
- **Gate = Phase 11**. Keep `mix test` green at each checkpoint.
