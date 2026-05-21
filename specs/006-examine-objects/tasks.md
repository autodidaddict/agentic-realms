# Tasks: Examine Objects and Players

**Input**: Design documents from `/specs/006-examine-objects/`
**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: The spec did not explicitly demand TDD, but the project pattern (003 / 004 / 005) ships proving tests with the feature. Following 005's structure: Phase 2 (Foundational) is the complete implementation; Phases 3–5 add per-user-story test coverage. The three user stories all exercise the same `Examine.examine/2` + parser + GameLive pipeline — they differ only in which scope (room object / inventory object / player) is being resolved. Implementing the pipeline once and proving it three ways gives the cleanest task graph.

**Organization**: Phase 2 is the complete implementation. Phases 3–5 are test phases, one per user story, each independently runnable. Phase 6 is polish and regression sweep.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story a task belongs to (US1, US2, US3)
- All file paths are repository-relative

## Path Conventions

Phoenix LiveView monolith (single Elixir project). New feature code lives in `lib/agenticrealms/world/examine.ex` + `lib/agenticrealms/world/examine/` (resolver facade + match struct). Existing files are extended: `lib/agenticrealms/world/command_parser.ex`, `lib/agenticrealms/world/intent_resolver.ex`, `lib/agenticrealms/world/intent_resolver/tools.ex`, `lib/agenticrealms_web/live/game_live.ex`, `lib/agenticrealms_web/components/game_components.ex`, `priv/intent_resolver/system_prompt.md`. No new runtime dependencies, no migrations, no event-store changes.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm the baseline is green before any 006 work begins. This feature adds no dependencies and no configuration; the only "setup" task is the regression checkpoint.

- [X] T001 Run `mix test` from repo root and confirm all existing 003 / 004 / 005 tests pass (expect 175+ tests, 0 failures; `:integration` and `:live_llm` tagged tests excluded by default). Baseline must be green before feature work begins. If a pre-existing failure surfaces, fix that first — 006 must not be built on top of a broken main.

**Checkpoint**: Baseline is green.

---

## Phase 2: Foundational (Blocking Prerequisites — full implementation)

**Purpose**: Build the entire examine pipeline end-to-end. Because the three user stories all exercise the same code path (with branches per target_kind), the implementation lands here as one block. After this phase the feature is functionally complete; Phases 3–5 add the test coverage that proves each user story.

**⚠️ CRITICAL**: No user-story test work can begin until this phase is complete.

- [X] T002 [P] Create `lib/agenticrealms/world/examine/match.ex` — the `AgenticRealms.World.Examine.Match` struct per `data-model.md` §1 and `contracts/examine_api.md`. Fields: `target_kind: :object | :player`, `name: String.t()`, `long_description: String.t() | nil`. `@enforce_keys [:target_kind, :name]`. Include the `@type t` definition.
- [X] T003 [P] Modify `lib/agenticrealms/world/command_parser.ex` per `contracts/parser.md`. Update the `parse_verb/1` `look`/`l` arm so that an empty rest still returns `{:look}` (unchanged), but a non-empty rest returns `{:look, normalize(rest_lc)}` — except that a normalized rest of exactly `"me"` or `"self"` returns the sentinel `{:look, "__self__"}`. Add `{:look, String.t()}` to the `@type result()` union. Existing `{:look}` behavior must be preserved byte-for-byte for the no-target case.
- [X] T004 [P] Modify `lib/agenticrealms/world/intent_resolver/tools.ex` per `contracts/tools.md`. Rewrite the `look` tool's `description` to the dual-purpose text ("Render the room OR examine a specific object/player"). Add an optional `target: %{type: "string", description: "..."}` property to its `input_schema.properties`. Leave `input_schema.required` as `[]`. Every other tool definition is byte-identical to the 005 baseline. `Tools.names/0` is unchanged.
- [X] T005 [P] Modify `priv/intent_resolver/system_prompt.md` per `contracts/system_prompt.md`. Four edits: (1) replace the "DO NOT substitute a near-mapping action" bullet in the "Game rules and tool-use protocol" section with the new "For object or player examination…" guidance; (2) rewrite Example 3 from a refusal demo to a `look`-with-target demo; (3) append new Examples 10–13 (inventory examine, player examine, self-examine via `"me"`, sanity-check whole-room `look` with no target); (4) update the final-reminders bullet to flip the examine guidance. The `SystemPrompt` Elixir loader compiles the markdown at compile time — no `.ex` change is required.
- [X] T006 [P] Modify `lib/agenticrealms_web/components/game_components.ex` per `contracts/ui_events.md`. Add two new `log_entry/1` clauses immediately after the existing `kind: :room` clauses: one for `%{kind: :detail, target_kind: :object}` rendering `<div class="log-entry detail detail-object">` with `.detail-head > .detail-name` and `.detail-body` for the long description; one for `%{kind: :detail, target_kind: :player}` rendering `<div class="log-entry detail detail-player">` with the `<name> is a player.` body. Both use HEEx auto-escaping for the `name` and `long_description` interpolations. Add a `.log-entry.detail` rule (with `.detail-object` / `.detail-player` modifiers) to whatever CSS file `.log-entry.room` lives in — pattern after the existing `.log-entry.private` styling so the entry is visually distinct from a room view (per FR-003).
- [X] T007 Create `lib/agenticrealms/world/examine.ex` exposing `examine/2` per `contracts/examine_api.md` (depends on T002). Implement the three-stage decision tree from `data-model.md` §3: pre-resolution self-alias check (`target == "__self__"` short-circuits to a `:player` Match for the acting player); Stage 1 collects exact case-insensitive matches across room objects (`Queries.look_room/1`), inventory objects (`Queries.list_inventory/1`), and same-room players (`Queries.other_occupants_of/2` + the acting player themselves); Stage 1 returns the lone match, refuses with `:ambiguous_mixed_kind` on object+player tie, `:ambiguous_player` on multi-player tie, otherwise falls into Stage 2 (inventory-over-room tiebreak for objects-only multi-exact, returning `:ambiguous_in_inventory` or `:ambiguous_in_room` when no single winner); Stage 3 (only when Stage 1 found 0 exact matches) does substring matching across all three scopes and returns the lone partial match, `:no_such_target`, or `:ambiguous_partial`. Emit `[:agenticrealms, :examine, :resolve]` telemetry exactly once per call with `%{player_id, outcome, target_kind: :object | :player | nil}` metadata. The module never raises (Ecto failures propagate to the caller).
- [X] T008 Modify `lib/agenticrealms/world/intent_resolver.ex`. (a) Extend the `@type action_tuple` union to include `{:look, String.t()}` alongside the existing `{:look}`. (b) Add a new clause to `to_action/2` matching `("look", %{"target" => t}) when is_binary(t) and t != ""` returning `{:ok, {:look, t}}`. Place this clause BEFORE the existing `to_action("look", _)` fallback so the more-specific pattern wins. (c) The existing `to_action("look", _)` clause stays as the no-target fallback. No other changes to the resolver facade.
- [X] T009 Modify `lib/agenticrealms_web/live/game_live.ex` (depends on T003, T007, T008). (a) Add a new arm to the `handle_event("submit_command", …)` case: `{:look, target} -> handle_look_target(socket, text, target, true)`, placed immediately after the existing `{:look}` arm. (b) Add `handle_look_target/4` (private). It calls `Examine.examine(player_id, target)` and matches on the result: `{:ok, %Match{target_kind: :object, name: name, long_description: ld}}` appends a `:cmd` echo and a `%{kind: :detail, target_kind: :object, name: name, long_description: ld}` log entry; `{:ok, %Match{target_kind: :player, name: name}}` appends a `:cmd` echo and a `%{kind: :detail, target_kind: :player, name: name}` log entry; `{:error, :no_such_target} when allow_fallback?` routes to `handle_unknown(socket, raw)` (per FR-011 / 005a-style fallback); `{:error, :no_such_target}` with `allow_fallback?: false` appends `:cmd` echo + `:system "You don't see that here."`; any `:ambiguous_*` variant appends `:cmd` echo + `:system "Which one do you mean?"` (no fallback — ambiguity is not a name-resolution failure); `{:error, :no_current_room}` appends `:cmd` echo + `:system "You are nowhere."`. (c) Add a new arm to `dispatch_resolved_action/3`: `{:look, target} -> handle_look_target(socket, raw, target, false)`, placed alongside the existing `{:look}` arm. The `allow_fallback?: false` on this path is what enforces the no-loop guard from FR-013.
- [X] T010 Run `mix compile --warnings-as-errors` and confirm clean. Boot `iex -S mix` and confirm no crashes (no new supervisor children needed — Examine is a pure module, no Application changes). Spot-check at the IEx prompt: `AgenticRealms.World.Examine.examine(player_id, "brass lantern")` against a seeded fixture returns a `{:ok, %Examine.Match{...}}` tuple.

**Checkpoint**: The feature is functionally complete. A player typing `look brass lantern` in the seeded starter map sees the lantern's long description; `look alice` (with Alice present) sees `Alice is a player.`; `examine the lantern` (with a working `ANTHROPIC_API_KEY`) does the same via the LLM fallback. Phases 3–5 now prove each user story.

---

## Phase 3: User Story 1 - Examine an Object in the Current Room (Priority: P1) 🎯 MVP

**Goal**: Prove that an object in the player's current room can be examined via the canonical `look <target>` form AND via natural-language phrasings (`examine X`, `inspect X`, `study X`), producing a detail entry whose body is the persisted long description.

**Independent Test**: Place Alice in the Stone Atrium (which seeds with a brass lantern). `Examine.examine(alice.id, "brass lantern")` returns `{:ok, %Match{target_kind: :object, name: "brass lantern", long_description: "An old hand-lantern..."}}`. End-to-end via the LiveView: submit `look brass lantern`, see a `:detail` entry with the right body. Submit `examine the brass lantern` (stubbed LLM returns `look` with `target: "brass lantern"`), see the same `:detail` entry.

### Tests for User Story 1

- [X] T011 [P] [US1] Append a `describe "look [target] parser extension"` block to `test/agenticrealms/world/command_parser_test.exs` covering every rule in `contracts/parser.md`: `look brass lantern` → `{:look, "brass lantern"}`, `look BRASS LANTERN` → `{:look, "brass lantern"}` (lowercased), `look   the   journal  ` → `{:look, "the journal"}` (trim + collapse), `look me` → `{:look, "__self__"}`, `look self` → `{:look, "__self__"}`, `look ME` → `{:look, "__self__"}`, `l me` → `{:look, "__self__"}`, `l self` → `{:look, "__self__"}`, `look someone` → `{:look, "someone"}` (NOT mapped), `look mead` → `{:look, "mead"}` (substring `me` does not trigger the alias because the full target is `mead`), `look` / `l` → `{:look}` (existing — regression guard).
- [X] T012 [P] [US1] Append two tests to `test/agenticrealms/world/intent_resolver/tools_test.exs`. (a) The `look` tool's `input_schema.properties` map contains a `target` key whose value is `%{"type" => "string", "description" => <non-empty string>}`. (b) The `look` tool's `input_schema.required` list is `[]` (target remains optional). The existing tool-count and tool-names structural tests must still pass (regression guard — 10 tools total, names unchanged).
- [X] T013 [P] [US1] Append a test to `test/agenticrealms/world/intent_resolver_test.exs` under `describe "parse_response/1 — happy path (US1)"` (or the existing happy-path describe — match the file's organization): a `tool_use` response with name `"look"` and `input: %{"target" => "brass lantern"}` produces `{:ok, {:look, "brass lantern"}}`. A separate test: a `tool_use` response with name `"look"` and `input: %{}` still produces `{:ok, {:look}}` (the no-target fallback clause). A test with `input: %{"target" => ""}` collapses to `{:ok, {:look}}` (empty string → no-target — most charitable interpretation per `data-model.md` §6).
- [X] T014 [P] [US1] Create `test/agenticrealms/world/examine_test.exs` with a `describe "examine/2 — room objects (US1)"` block. Seed a room with a brass lantern (via `Seed.run/0` or a fixture helper). Test: exact match returns the object Match with the right `name` and `long_description`. Test: partial match (`"lantern"`) on a room with one matching object returns the same Match. Test: substring match against a non-matching object (`"dragon"`) returns `{:error, :no_such_target}`. Test: ambiguous partial match (two distinct objects both containing the substring) returns `{:error, :ambiguous_partial}`. Test: `no_current_room` for a player whose `PlayerState` has no `current_room_id` returns `{:error, :no_current_room}`. (Inventory and player cases are covered in T016 and T019; this file is created here and appended in US2 / US3 phases.)
- [X] T015 [P] [US1] Create `test/agenticrealms_web/live/game_live_examine_test.exs` (tag `:integration`, consistent with 003a/005 patterns) with a `describe "examine room object (US1)"` block. With Alice mounted in the Stone Atrium: submit `look brass lantern` via the LiveView form; assert the resulting HTML contains a `<div class="log-entry detail detail-object">`, the lantern's name in `.detail-name`, and the lantern's long description in `.detail-body`. The lantern remains in the room (`Queries.look_room(alice.id).objects` still contains it). The room layout's `:cmd` echo shows `look brass lantern` verbatim. Second scenario (LLM fallback): with the IntentResolver stubbed to return `{:ok, {:look, "brass lantern"}}`, submit the natural-language input `examine the brass lantern`; assert the same `:detail` entry is rendered, the `:cmd` echo shows the literal natural-language input (NOT canonicalized to `look brass lantern`), and the input lock/unlock cycle behaves correctly (parallel to T016/T021 in 005's tasks).

**Checkpoint**: US1 fully tested. The MVP — examining a room object via canonical and natural-language phrasings — is proven.

---

## Phase 4: User Story 2 - Examine an Object in the Player's Inventory (Priority: P1)

**Goal**: Prove that an object in the player's inventory is examinable (and that the inventory-over-room precedence from FR-006a holds when the same name appears in both).

**Independent Test**: Alice takes the brass lantern, moves to the North Corridor (which has no objects), submits `look brass lantern`, and sees the lantern's detail entry — the lookup finds the lantern in inventory. Separately, with the same lantern name present in both a player's inventory AND the current room (via a fixture), the inventory copy wins.

### Tests for User Story 2

- [X] T016 [US2] Append a `describe "examine/2 — inventory objects (US2)"` block to `test/agenticrealms/world/examine_test.exs` (created in T014; sequenced after T014). Test: with a player carrying a leather-bound journal in the empty corridor, `examine(player_id, "journal")` returns a `:object` Match with the journal's long description. Test: inventory-over-room precedence — seed a room and inventory that BOTH contain an object named `brass lantern`, call `examine(player_id, "brass lantern")`, and assert the returned Match's `long_description` matches the inventory copy (not the room copy). Test: `:ambiguous_in_inventory` — a player carrying two objects with the same exact name (fixture setup), `examine` returns `{:error, :ambiguous_in_inventory}`. Test: `:ambiguous_in_room` — multiple identically named objects in the room, none in inventory, returns `{:error, :ambiguous_in_room}`.
- [X] T017 [US2] Append a `describe "examine inventory object (US2)"` block to `test/agenticrealms_web/live/game_live_examine_test.exs` (created in T015; sequenced after T015). Scenario: Alice takes the brass lantern, moves north, submits `look brass lantern`. Assert the `:detail` entry renders with the lantern's long description (the resolver found it in inventory). The room view (re-rendered by a follow-up `look` with no target) shows no brass lantern, confirming the lantern is in inventory. Second scenario (LLM fallback): with the IntentResolver stubbed to return `{:ok, {:look, "leather-bound journal"}}`, submit `read my journal` and assert the journal's detail entry is rendered.
- [X] T018 [P] [US2] Append an `examine`-style natural-language input test to `test/agenticrealms_web/live/game_live_intent_parser_test.exs` (the file from 005 that already exists). With the resolver stubbed to return `{:ok, {:look, "brass lantern"}}`, submit `examine the brass lantern closely`; assert the LiveView dispatches through `handle_look_target/4` and renders a `:detail` entry — proving the LLM-fallback wiring for the new action tuple shape is end-to-end correct. Different file from T017 (`game_live_examine_test.exs` vs. `game_live_intent_parser_test.exs`), so this task IS parallelizable with T017 once T015/T016 exist.

**Checkpoint**: US1 + US2 tested. Both fast-path and LLM-fallback examine flows work for room AND inventory objects, and the inventory-over-room precedence is proven.

---

## Phase 5: User Story 3 - Examine Another Player in the Current Room (Priority: P2)

**Goal**: Prove that another player in the same room is examinable and renders the placeholder `<name> is a player.` line; that self-examination works via `me` / `self` and via the player's own username; that offline players are not examinable; and that examination produces NO witness entries for anyone else.

**Independent Test**: Two browser sessions, Alice and Bob, both in the Stone Atrium. Bob submits `look alice` → his log shows `Alice is a player.`. Alice's log shows NOTHING (privacy contract — FR-010, SC-005). Bob's `look me` shows `Bob is a player.`. After Alice logs out (Presence drops her), Bob's `look alice` returns `You don't see that here.` (the offline filter inherited from 003a applies).

### Tests for User Story 3

- [X] T019 [US3] Append a `describe "examine/2 — players and self (US3)"` block to `test/agenticrealms/world/examine_test.exs` (sequenced after T014 and T016). Test: player-in-same-room examine — with Alice and Bob both placed in the Stone Atrium (Presence tracked), `examine(bob.id, "alice")` returns a `:player` Match with `name: "Alice"` (case preserved from the username column) and `long_description: nil`. Test: case-insensitive matching — `examine(bob.id, "ALICE")` returns the same Match. Test: self-alias — `examine(alice.id, "__self__")` returns a `:player` Match with `name: <alice's stored username>` without needing to consult the room's player list (verified by stubbing `Queries.other_occupants_of/2` to return `[]` — the self-alias path must not depend on it). Test: self-by-name — `examine(alice.id, alice.username |> String.downcase())` returns the same Match. Test: offline-player filter — with Alice's Presence tracker untracked (or never tracked), `examine(bob.id, "alice")` from the same room returns `{:error, :no_such_target}`. Test: mixed-kind tie — fixture seeded so a room contains an object named "Lantern" AND a player named "Lantern" both in scope; `examine(player_id, "lantern")` returns `{:error, :ambiguous_mixed_kind}`.
- [X] T020 [US3] Append a `describe "examine player and self (US3)"` block to `test/agenticrealms_web/live/game_live_examine_test.exs` (sequenced after T015 and T017). Scenario A: mount two LiveView sessions for Alice and Bob, both placed in the Stone Atrium. Bob submits `look alice`. Assert Bob's HTML contains a `<div class="log-entry detail detail-player">` with `Alice is a player.` body. CRITICAL: assert Alice's LiveView log assign is UNCHANGED — no entry was appended. This proves SC-005 (no witness entries for examination). Scenario B: Bob submits `look me`. Assert Bob's HTML contains `Bob is a player.`. Scenario C: Bob submits `look self`. Same outcome as B. Scenario D: Alice's session terminates (untrack from Presence). Bob submits `look alice`. Assert the `:detail` entry is NOT rendered; instead a `:system` entry `You don't see that here.` appears. Scenario E (LLM fallback): with the resolver stubbed to return `{:ok, {:look, "alice"}}`, Bob submits `who is alice anyway` and gets the same `Alice is a player.` detail entry.
- [X] T021 [P] [US3] Append a player-examine natural-language fallback test to `test/agenticrealms_web/live/game_live_intent_parser_test.exs`. With the resolver stubbed to return `{:ok, {:look, "me"}}` (the parser-injected self-alias is `__self__`, but the LLM emits the literal `"me"` per the system prompt — the Examine module accepts both), submit `look at myself`. Assert the LiveView renders a `:detail` entry with the acting player's name. Different file from T020, so this task IS parallelizable with T020.

**Checkpoint**: All three user stories tested. The fast-path + LLM-fallback wiring, the inventory-over-room precedence, the player-render contract, the self-alias, the offline-player filter, and the privacy contract are all proven.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Update the live-LLM smoke test to reflect the spec change (examine is no longer a refusal), confirm formatting, sweep for regressions, and run the manual quickstart.

- [X] T022 [P] Update `test/agenticrealms/world/intent_resolver_live_test.exs` — change the `@cases` entry `{"examine the brass lantern very closely", :refuse}` to `{"examine the brass lantern very closely", :look}`. The `classify/1` helper already extracts the chosen tool name as an atom (first element of the action tuple, or `:refuse` for the refuse tool). Optionally append a second `:look`-expected entry covering `study the journal carefully` to broaden the curated set. The `:refuse` entries for `take the lantern and then head north` (multi-step) and `what time is it in the real world` (out-of-game) MUST remain — those refusals are unchanged by 006.
- [X] T023 [P] Sweep `test/agenticrealms/world/intent_resolver_test.exs` and `test/agenticrealms_web/live/game_live_intent_parser_test.exs` for narrative comments / describe-block names that refer to "near-mapping refusal" or assert refusal for `examine`-style input. The underlying response-mapping behavior (refuse → error, look → look) is unchanged, so the assertions still pass; only the framing language is stale. Rename the relevant describe blocks (e.g. "near-mapping intent" → "generic refusal") and adjust the test docstrings. Do NOT change assertions — those are still load-bearing. This task is presentation-only.
- [X] T024 Update `GameData.suggestions/0` (in `lib/agenticrealms/game_data.ex`) to include an `examine <object>` or `look at <object>` suggestion chip, exposing the new verb to players who discover the game via the suggestion bar. Not strictly required by the spec but elevates feature discoverability. Verify the chip click path (`handle_event("click_suggestion", …)` → `handle_event("submit_command", …)`) reaches the new `{:look, target}` parser arm.
- [X] T025 Walk through `specs/006-examine-objects/quickstart.md` manually: boot `mix phx.server`, log in as Alice and Bob, run every step in the quickstart, confirm each expected outcome. Pay extra attention to the privacy contract (Alice's log MUST be empty after Bob examines her or any object). This task is deferred-during-CI but MUST be done before tagging the feature complete.
- [X] T026 [P] `mix format` from repo root; `mix format --check-formatted` clean. Then `mix compile --warnings-as-errors` clean.
- [X] T027 [P] Full `mix test` from repo root. Expect: 0 failures across all 003 / 004 / 005 / 006 tests (~210 total expected — count is approximate as the test files grow). The `:integration` and `:live_llm` tags MUST remain excluded by default. Run `mix test --include integration` separately to confirm the new LiveView integration tests pass with real DB sandbox checkouts.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: T001 — gate before feature work.
- **Foundational (Phase 2)**: T002–T010 — depends on Phase 1. This phase is the complete implementation; it BLOCKS all test phases.
- **User Story test phases (Phases 3–5)**: each depends only on Phase 2 being complete. Once Phase 2 lands, US1 / US2 / US3 test phases can run in parallel — they touch mostly separate test files, with intra-file sequencing noted below.
- **Polish (Phase 6)**: T022/T023/T024 depend on Phase 2; T025–T027 depend on Phases 3–5 for the regression sweep.

### Within Phase 2

- T002 (Match struct), T003 (parser), T004 (Tools), T005 (system prompt), T006 (GameComponents) — five independent file targets, all `[P]`.
- T007 (Examine module) depends on T002 (uses the Match struct).
- T008 (IntentResolver `to_action`) depends on nothing in this feature (it's a self-contained clause addition), but logically pairs with T004 (the tool schema). No code dep — safe to start in parallel with T004 after T002, but cleaner if sequenced after T004 for narrative coherence. Acceptable either way.
- T009 (GameLive) depends on T003 (parser sentinel), T007 (Examine module), T008 (IntentResolver action_tuple). Must be sequenced last among code tasks.
- T010 is the post-implementation compile/boot gate.

### Within each test phase

- Test tasks that create NEW files are `[P]` with each other (across files).
- Test tasks that APPEND to a file created in an earlier phase are sequenced after that file exists and are NOT `[P]` with other appends to the same file. Specifically:
  - T014 creates `examine_test.exs`; T016 and T019 append to it — they run sequentially.
  - T015 creates `game_live_examine_test.exs`; T017 and T020 append to it — sequentially.
  - T018 and T021 both append to the pre-existing `game_live_intent_parser_test.exs` — sequentially.

### Parallel Opportunities

- **Phase 2**: T002–T006 in parallel (five distinct files / one priv-content edit). Then T007 (after T002), T008 in parallel with T007, then T009 (after T003 + T007 + T008), then T010.
- **Phase 3**: T011, T012, T013, T014, T015 all `[P]` (five distinct test files / file-creations).
- **Phase 4**: T018 is `[P]` with T017 (different files).
- **Phase 5**: T021 is `[P]` with T020 (different files).
- **Phase 6**: T022, T023, T026, T027 all `[P]` with each other; T024 and T025 sequential (T024 modifies code; T025 needs the suggestion chip in place).
- Across test phases, after Phase 2 lands, US1/US2/US3 can be staffed to different developers — coordination cost is the two shared test files (`examine_test.exs` is built up through T014→T016→T019; `game_live_examine_test.exs` through T015→T017→T020).

---

## Parallel Example: Phase 2 Foundational

```text
# Wave 1 — five independent foundational tasks (T002–T006 all [P]):
Task: T002 — Examine.Match struct (lib/agenticrealms/world/examine/match.ex)
Task: T003 — CommandParser look-target extension (lib/agenticrealms/world/command_parser.ex)
Task: T004 — Tools.ex look-tool schema update (lib/agenticrealms/world/intent_resolver/tools.ex)
Task: T005 — priv system prompt edits (priv/intent_resolver/system_prompt.md)
Task: T006 — GameComponents :detail log_entry clauses (lib/agenticrealms_web/components/game_components.ex)

# Wave 2 — depends on Wave 1:
Task: T007 — World.Examine module (lib/agenticrealms/world/examine.ex)     [depends on T002]
Task: T008 — IntentResolver to_action clause (lib/agenticrealms/world/intent_resolver.ex)

# Wave 3 — depends on T003 + T007 + T008:
Task: T009 — GameLive handle_look_target + dispatch arms (lib/agenticrealms_web/live/game_live.ex)

# Wave 4 — gate:
Task: T010 — mix compile --warnings-as-errors + iex boot smoke
```

---

## Parallel Example: Phase 3 User Story 1

```text
# All five tasks touch different files and have no dependencies on each other:
Task: T011 — parser tests (test/agenticrealms/world/command_parser_test.exs)
Task: T012 — tools schema test (test/agenticrealms/world/intent_resolver/tools_test.exs)
Task: T013 — IntentResolver parse_response test (test/agenticrealms/world/intent_resolver_test.exs)
Task: T014 — Examine room-object tests (test/agenticrealms/world/examine_test.exs)
Task: T015 — LiveView integration (test/agenticrealms_web/live/game_live_examine_test.exs)
```

---

## Implementation Strategy

### MVP First (Phase 1 → 2 → 3)

1. Complete Phase 1 (Setup baseline) and Phase 2 (Foundational implementation) — the feature is functionally complete after this.
2. Complete Phase 3 (US1 tests) — proves the canonical use case (examine a room object) works.
3. **STOP and VALIDATE**: run `mix test` and walk Story 1 of `quickstart.md`. If green, the MVP is shippable — players can examine the brass lantern.
4. Deploy / demo if desired.

### Incremental Delivery

1. Setup + Foundational → feature functionally complete.
2. Add US1 tests → room-object examine proven → demo (MVP).
3. Add US2 tests → inventory-object examine + precedence proven → demo.
4. Add US3 tests → player examine + self + offline filter + privacy proven → demo.
5. Polish (live smoke test update, formatting, regression sweep).

Because the implementation is monolithic (Phase 2), the "increments" are increments of **proven confidence**, not increments of shipped code. The code ships once (Phase 2); each test phase raises the assurance level for one user story. Same posture as feature 005's task structure.

### Parallel Team Strategy

With multiple developers:

1. Team completes Phase 1 + Phase 2 together (Phase 2 has a clear wave structure; pair-coding is reasonable).
2. Once Phase 2 lands:
   - Developer A: US1 (Phase 3)
   - Developer B: US2 (Phase 4 — but coordinates with A on `examine_test.exs` / `game_live_examine_test.exs` for sequenced appends)
   - Developer C: US3 (Phase 5 — same coordination)
3. Polish (Phase 6) sweeps after all three user stories are tested.

### A note on the monolithic Phase 2

Like feature 005, 006's three user stories all exercise the same code path — the `Examine.examine/2` function with three branches (object-in-room, object-in-inventory, player-in-room), the same parser sentinel, the same LiveView dispatch, and the same `:detail` log-entry kind (two render branches). There is no useful subset of the implementation that satisfies US1 without also satisfying US2 (the resolver gathers all three scopes in one pass) or US3 (the parser already handles the player-name case the same way it handles object names). The task structure reflects this honestly: implement once, then prove three ways.

---

## Notes

- `[P]` = different files, no dependency on an incomplete task. Concentrated in Phase 2 (distinct files / file-touches) and the test phases (distinct test files).
- `[Story]` labels appear only on user-story test-phase tasks (US1/US2/US3). Setup, Foundational, and Polish tasks are unlabeled.
- No new dependencies, no migrations, no event-store changes, no PubSub topics, no Application supervisor changes. The feature is the smallest blast radius that satisfies the spec.
- The render layer uses HEEx auto-escaping for `name` and `long_description` — defensive escaping for object-name and player-name interpolation. Object long descriptions are seed-controlled today; the auto-escape stays in place against future player-authored object content.
- Commit cadence: one commit per task or per logical group, consistent with 003 / 004 / 005's pattern.
- SC-005 (privacy contract) is the single most important assertion in T020 Scenario A — it requires a parallel-session test setup. Without that scenario, the no-broadcast invariant is unproven.
- The live_llm smoke test (T022) costs real API tokens — kept out of CI's default run; on-demand validation tool.
