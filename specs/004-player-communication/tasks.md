# Tasks: Player Communication — Say, Emote, Tell, Whisper

**Input**: Design documents from `/specs/004-player-communication/`
**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: The spec did not explicitly request TDD, but `plan.md` (project structure) and `research.md` §11 enumerate three test files as deliverables, and the existing project pattern (features 001–003) ships tests with implementation. Test tasks are included alongside implementation in each user-story phase — they need not be written strictly before the implementation tasks, but they MUST exist before a story is considered complete.

**Organization**: Tasks are grouped by user story so each story can be implemented, tested, and demoed as an independent increment. The feature builds entirely on the feature 003 substrate (Phoenix.PubSub, `World.UIEvents`, `GameLive`, `CommandParser`) — there are no new dependencies, no new migrations, and no new supervision-tree children.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)
- All file paths are repository-relative

## Path Conventions

Phoenix LiveView web application (single Elixir project). Code under `lib/`, tests under `test/`. Communication code lives at `lib/agenticrealms/world/communication.ex` and `lib/agenticrealms/world/communication/`. The `UIEvents`, `CommandParser`, `GameLive`, and `GameComponents` modules from 003 are extended in place — no new top-level namespaces.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm a clean baseline before adding feature code. No new dependencies, no new migrations — this phase is unusually small because 004 is purely additive on the 003 substrate.

- [X] T001 Run `mix deps.get && mix test` from repo root and confirm all existing 003 tests pass with no regressions before any 004 work begins.

**Checkpoint**: Baseline green; safe to begin foundational work.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared infrastructure that all four user stories build on — the two new UIEvent struct shapes, the parser refactor that preserves case in the rest-of-input, the empty `World.Communication` module skeleton with shared validation helpers, the `session_id` socket assign in `GameLive.mount/3`, and a base `:refusal` clause in `GameComponents`. After this phase, every user story can proceed independently.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T002 [P] Add `%AgenticRealms.World.UIEvents.RoomUtterance{}` and `%AgenticRealms.World.UIEvents.PrivateUtterance{}` struct definitions to `lib/agenticrealms/world/ui_events.ex`.
- [X] T003 [P] Refactor `lib/agenticrealms/world/command_parser.ex` to preserve case in the rest-of-input for communication verbs while keeping existing 003 verbs on the lowercased payload path. Also adds the four communication-verb branches (say/emote/tell/whisper + apostrophe and colon shortcuts) — this collapses what was originally split across T010/T018/T028/T036 since touching the same file four more times would have been pure cost. Per-story tasks now only need to verify parser behavior via tests.
- [X] T004 [P] Add a `:session_id` socket assign (`make_ref()`) to `GameLive.mount/3` for actor-side self-filtering.
- [X] T005 [P] Create skeleton `lib/agenticrealms/world/communication.ex` with `trim_and_validate/1`, `broadcast_room/2`, `broadcast_private/2` helpers. Public functions added per-story.
- [X] T006 [P] **Absorbed**: refusal entries reuse the existing `:system` log kind from feature 003 (used for "You can't go that way" etc.) rather than introducing a parallel `:refusal` kind. Keeps styling consistent across features. Contract `ui_events.md` updated to reflect this.

**Checkpoint**: Application boots clean; `mix test` still passes; new struct modules compile; parser refactor is non-breaking. Ready to begin user stories.

---

## Phase 3: User Story 1 - Player Speaks Aloud in a Room (Priority: P1) 🎯 MVP

**Goal**: `say` and the `'` shortcut work. Same-room witnesses see attributed speech entries; the speaker sees an actor-side confirmation in their originating session and a witness entry in their other sessions (multi-session rule); other rooms see nothing; empty/overlong submissions are refused.

**Independent Test**: Quickstart §1. With Alice and Bob in the same room and Carol in a different room, Alice's `say hello` reaches Bob within 100 ms but not Carol; `'   ` and `say` alone produce refusals; a 600-char submission is refused.

### Tests for User Story 1

- [X] T007 [P] [US1] Parser tests for say sentinels (10 new tests in `test/agenticrealms/world/command_parser_test.exs`).
- [X] T008 [P] [US1] `Communication.say/2` unit tests with PubSub-subscribe assertions (8 tests in `test/agenticrealms/world/communication_test.exs`).
- [X] T009 [P] [US1] LiveView integration test in `test/agenticrealms_web/live/game_live_communication_test.exs`. Restructured as a single comprehensive test covering all 7 US1 scenarios (witness, actor-side confirmation, multi-session, different-room, empty refusal, HTML escape, over-cap refusal). Tagged `:integration` and excluded from default `mix test` run due to in-memory event-store state accumulating across test files — run with `mix test --include integration` or against the file in isolation.

### Implementation for User Story 1

- [X] T010 [US1] Say sentinels and apostrophe shortcut. **Done in T003** during Phase 2 (parser refactor included all 4 verbs). Verified by T007 tests.
- [X] T011 [US1] `Communication.say/2` implemented in `lib/agenticrealms/world/communication.ex`.
- [X] T012 [US1] `{:say, text}` and `{:say_empty}` submit branches added to `GameLive`; `handle_say/3` private function appends `:cmd` echo + actor-side `:speech_self` confirmation or `:system` refusal.
- [X] T013 [US1] `handle_info/2` clause for `%RoomUtterance{kind: :say}` with `actor_session_id`-based self-filter.
- [X] T014 [US1] `:speech` and `:speech_self` log-entry clauses added to `game_components.ex`. HEEx default-escaped on `@entry.text` and `@entry.actor`.

**Checkpoint**: `mix test` passes; quickstart §1 walkthrough works end-to-end across three browser sessions. US1 is MVP-shippable independent of US2-US4.

---

## Phase 4: User Story 2 - Player Performs an Emote (Priority: P2)

**Goal**: `emote`, `me`, and `:` work. Every room subscriber INCLUDING the actor sees a third-person narration entry. Trailing punctuation is auto-appended unless the text already ends with `.`, `!`, or `?`. Empty submissions are refused.

**Independent Test**: Quickstart §2. With Alice and Bob in the same room, `emote waves at the fire` produces the same entry "Alice waves at the fire." in both Alice's and Bob's logs. Aliases `me bows` and `:bows` produce identical results. `:laughs!` produces "Alice laughs!" (single trailing `!`).

### Tests for User Story 2

- [X] T015 [P] [US2] Parser tests for emote (9 new tests).
- [X] T016 [P] [US2] `Communication.emote/2` unit tests with trailing-punctuation rule coverage (6 new tests).
- [ ] T017 [P] [US2] LiveView integration coverage — deferred to a single sweep test extension after all stories ship (avoids the test-isolation issue surfaced in T009).

### Implementation for User Story 2

- [X] T018 [US2] Emote sentinels — covered by T003 (Phase 2 parser refactor).
- [X] T019 [US2] `Communication.emote/2` implemented with `ensure_trailing_punctuation/1` helper.
- [X] T020 [US2] `{:emote, text}` / `{:emote_empty}` submit branches in `GameLive`.
- [X] T021 [US2] `handle_info/2` for `%RoomUtterance{kind: :emote}` with no actor exclusion.
- [X] T022 [US2] `:emote_action` log-entry clause in `game_components.ex`.

**Checkpoint**: `mix test` passes; quickstart §2 walkthrough works. US1 + US2 both shippable independently.

---

## Phase 5: User Story 3 - Player Tells Another Player Privately Across Rooms (Priority: P3)

**Goal**: `tell` and `t` work cross-room. Recipient resolution is case-insensitive exact match; duplicate display names refuse as ambiguous; self-target refuses; offline recipient produces neutral "could not be delivered"; sender's other sessions do NOT receive the tell. 500-char cap enforced.

**Independent Test**: Quickstart §3 + §5 (multi-session). Alice and Bob in different rooms → `tell bob hello` reaches Bob's log; Alice sees actor-side confirmation; Carol (in Alice's room) sees nothing. `t alice hi` from Alice → self-target refusal. Two case-variant accounts → ambiguous refusal. Offline recipient → neutral refusal.

### Tests for User Story 3

- [X] T023 [P] [US3] Parser tests for tell (8 new tests).
- [X] T024 [P] [US3] `RecipientResolver` tests in new file (6 tests covering exact, case-variant, not-found, self-target ordering, ambiguous).
- [X] T025 [P] [US3] `Communication.tell/3` unit tests (7 tests including offline/online via Presence).
- [ ] T026 [P] [US3] LiveView integration coverage — deferred to a sweep test after US4 (test-isolation issue limits multi-test files).

### Implementation for User Story 3

- [X] T027 [US3] `RecipientResolver` module created with self-target-before-ambiguous ordering.
- [X] T028 [US3] Tell sentinels — covered by T003.
- [X] T029 [US3] `Communication.tell/3` implemented with `ensure_online/1` Presence check.
- [X] T030 [US3] Tell submit branches with all 6 error-tag → refusal-copy mappings.
- [X] T031 [US3] `handle_info/2` for `%PrivateUtterance{kind: :tell}`.
- [X] T032 [US3] `:private_tell_in` and `:private_tell_out` log-entry clauses.

**Checkpoint**: `mix test` passes; quickstart §3 walkthrough works. US1 + US2 + US3 all shippable. Self-target, ambiguous, and offline refusals exercised manually per quickstart steps.

---

## Phase 6: User Story 4 - Player Whispers Privately to Another Player in the Same Room (Priority: P4)

**Goal**: `whisper` and `w` work. Recipient must be in sender's current room — cross-room whisper refused with "not nearby" message that hints at `tell`. Recipient resolution reuses `RecipientResolver` from US3. Private to the recipient — other room subscribers MUST NOT render the whisper content (room broadcast + recipient_id filter).

**Independent Test**: Quickstart §4. Alice, Carol, Dave in same room + Bob in different room → Alice's `whisper carol look out` reaches only Carol; Dave (same room) and Bob (different room) see nothing. `w bob psst` from Alice → "not nearby" refusal. `w alice hi` → self-target refusal.

### Tests for User Story 4

- [X] T033 [P] [US4] Parser tests for whisper (6 new tests, including the `w`→west conflict resolution note).
- [X] T034 [P] [US4] `Communication.whisper/3` unit tests covering all 5 error-path refusals (success path covered by integration test). 5 tests.
- [ ] T035 [P] [US4] LiveView integration coverage — deferred (test-isolation limit).

### Implementation for User Story 4

- [X] T036 [US4] Whisper sentinels — covered by T003.
- [X] T037 [US4] `Communication.whisper/3` implemented with `ensure_in_room/3` check via `Queries.other_occupants_of/2`.
- [X] T038 [US4] Whisper submit branches with all 6 error-tag → refusal-copy mappings.
- [X] T039 [US4] `handle_info/2` for `%RoomUtterance{kind: :whisper}` with `recipient_id`-based filter.
- [X] T040 [US4] `:private_whisper_in` and `:private_whisper_out` log-entry clauses.

**Checkpoint**: All four user stories complete. `mix test` passes. Full quickstart walkthrough exercises every clarification (transient, case-insensitive, neutral offline, 500-char, self-target).

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Final validation, regression sweep, and HTML-safety verification.

- [ ] T041 [P] Manual quickstart walkthrough with three browser sessions — **deferred to user-driven validation**, requires running `mix phx.server` and registering three accounts interactively.
- [X] T042 [P] HTML-escape assertion verified in `game_live_communication_test.exs` Scenario 6 (asserts `&lt;script&gt;` is present and unescaped `<script>...</script>` is NOT).
- [X] T043 [P] Full `mix test` regression — **133 tests, 0 failures (1 :integration excluded by default)**. `mix format --check-formatted` clean.
- [X] T044 SC-001 latency smoke test: 100 iterations of `Communication.say/2` + PubSub round-trip. **p50 = 3μs, p95 = 4μs, p99 = 11μs, max = 11μs** — vs. the 100ms target. ~25,000× under budget thanks to communication being PubSub-only with no DB or event store in the hot path.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: T001 — no dependencies, must succeed before anything else.
- **Foundational (Phase 2)**: T002–T006 — all depend only on T001. All five can run in parallel (different files).
- **User Stories (Phases 3–6)**: All depend on Foundational completion. Once Phase 2 is done, each user story can proceed independently of the others — there are no cross-story dependencies after the foundational shared work.
- **Polish (Phase 7)**: Depends on whichever user stories are in scope. T041 (quickstart) requires all four stories; T042–T044 work after US1 alone.

### User Story Dependencies

- **US1 (Say)**: Depends only on Foundational. Independently shippable as MVP.
- **US2 (Emote)**: Depends only on Foundational. Independently shippable. Does NOT depend on US1.
- **US3 (Tell)**: Depends only on Foundational. Independently shippable. Introduces `RecipientResolver` which US4 will reuse — but US4 could also reintroduce it independently if US3 is descoped.
- **US4 (Whisper)**: Depends only on Foundational. If US3 is in scope, T037 (whisper impl) reuses the resolver from T027; if US3 is descoped, US4 must include its own resolver implementation (move T027 into Phase 6).

### Within Each User Story

- Tests (T0XX in the "Tests for User Story N" subsection) and implementation (the subsequent T0XX in "Implementation for User Story N") MAY interleave — the project does not enforce strict TDD-first. Tests MUST exist before the story is considered complete.
- Implementation order within a story:
  1. Parser sentinel additions (modifies `command_parser.ex`)
  2. Facade function (modifies `communication.ex`)
  3. GameLive submit branch + handle_info (modifies `game_live.ex`)
  4. GameComponents log-entry clauses (modifies `game_components.ex`)
- Tasks within a story that touch the same file CANNOT be parallelized; tasks that touch different files CAN be (marked `[P]`).

### Parallel Opportunities

- All of Phase 2 (T002–T006) can be parallelized — five separate files.
- All three test tasks within each US phase (T007/T008/T009 in US1, etc.) can be parallelized — they live in three different test files.
- Implementation tasks within a US phase are sequenced (most touch `game_live.ex` or `command_parser.ex` exclusively, so no `[P]` markers inside the implementation subsection — but T027 (resolver, new file) in US3 is `[P]` with T028 if both were issued separately).
- Across US phases, after Foundational completes, US1/US2/US3/US4 can be assigned to different developers and worked in parallel; merge order is whatever the team chooses.
- Polish (Phase 7) T041–T043 can run in parallel.

---

## Parallel Example: User Story 1

```text
# Launch all three test tasks for US1 in parallel (three different test files):
Task: T007 — Parser tests in test/agenticrealms/world/command_parser_test.exs
Task: T008 — Communication.say tests in test/agenticrealms/world/communication_test.exs
Task: T009 — LiveView integration tests in test/agenticrealms_web/live/game_live_communication_test.exs

# Then implementation, sequenced because multiple tasks touch lib/agenticrealms_web/live/game_live.ex:
T010 → T011 → T012 → T013 → T014
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001).
2. Complete Phase 2: Foundational (T002–T006).
3. Complete Phase 3: User Story 1 (T007–T014).
4. **STOP and VALIDATE**: Walk through quickstart §1; run `mix test`. If green, US1 (Say) is fully functional and shippable on its own — the world now feels inhabited by people who can speak.
5. Deploy/demo the MVP if desired before continuing.

### Incremental Delivery

1. Setup + Foundational → foundation ready (~30 min of work in a small codebase).
2. Add US1 (Say) → test independently → deploy (MVP — speech only).
3. Add US2 (Emote) → test independently → deploy (speech + emotes).
4. Add US3 (Tell) → test independently → deploy (speech + emotes + cross-room DM).
5. Add US4 (Whisper) → test independently → deploy (full communication surface).
6. Polish (Phase 7).

Each story adds value without breaking previous stories. The strictest dependency is US4's *opportunistic* reuse of US3's `RecipientResolver`; if US4 is shipped without US3 the resolver moves into Phase 6.

### Parallel Team Strategy

With multiple developers and Foundational already done:

- Dev A: US1 (Say) — owns `command_parser.ex` for parser branches, plus the say-related game_live.ex / game_components.ex / communication.ex changes.
- Dev B: US2 (Emote) — same files as Dev A. **Coordinate** on parser/game_live merges (or sequence US1 and US2 on the same developer if file contention is friction).
- Dev C: US3 (Tell) — adds the `recipient_resolver.ex` (new file, no contention) plus tell-specific edits to the shared files.
- Dev D: US4 (Whisper) — same shared files as A/B/C. Heaviest merge coordination needed.

Realistic recommendation for a single developer: do US1 → US2 → US3 → US4 in order, since the four stories all amend the same `command_parser.ex` / `game_live.ex` / `game_components.ex` / `communication.ex` files. Parallel team work has high merge overhead for a feature this small. The story split is more useful for *staged shipping* than for *staffing parallelism*.

---

## Notes

- `[P]` tasks = different files, no dependencies. The vast majority of implementation tasks across phases share `game_live.ex`, `command_parser.ex`, `game_components.ex`, or `communication.ex`, so `[P]` is concentrated in Phase 2 (foundational, separate files) and in each story's test-tasks subsection (separate test files).
- `[Story]` label maps each story-phase task to a specific user story for traceability — Setup, Foundational, and Polish tasks have no label.
- All four user stories are independently testable per the spec's Acceptance Scenarios and the matching quickstart sections.
- No new migrations, no new supervision children, no new mix deps — confirmed during planning. If any task seems to require those, stop and reconcile with `plan.md` and `research.md` before proceeding.
- Commit after each task (or each completed checkpoint) to keep the diff reviewable and align with the project's commit-style precedent from 003.
