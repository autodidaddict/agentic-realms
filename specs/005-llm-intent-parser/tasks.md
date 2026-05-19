# Tasks: Natural-Language Player Commands (LLM intent parser)

**Input**: Design documents from `/specs/005-llm-intent-parser/`
**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: The spec did not request strict TDD, but `plan.md` and `research.md` §12 enumerate test files as deliverables, and the project pattern (features 003 / 004) ships tests with the feature. Unlike 004, the user stories here do NOT slice the implementation — all three exercise the same resolver pipeline. The implementation therefore lands as one block in Phase 2 (Foundational); Phases 3–5 add the per-user-story **test** coverage that proves each story's acceptance scenarios. Tests must exist before the feature is considered complete.

**Organization**: Phase 2 is the complete implementation. Phases 3–5 are test phases, one per user story, each independently runnable and each proving a distinct facet of behavior (success path, refusal coverage, resilience).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story a task belongs to (US1, US2, US3)
- All file paths are repository-relative

## Path Conventions

Phoenix LiveView monolith (single Elixir project). New feature code lives in `lib/agenticrealms/anthropic.ex` (HTTP client) and `lib/agenticrealms/world/intent_resolver.ex` + `lib/agenticrealms/world/intent_resolver/` (resolver facade + helpers). The system prompt content lives in `priv/intent_resolver/`. Tests under `test/`. No new migrations, no event-store changes.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Add the one new dependency, wire Anthropic configuration across environments, and confirm a clean baseline.

- [X] T001 Add `{:req, "~> 0.5"}` to the deps list in `mix.exs` and run `mix deps.get` to install. Req is the only new runtime dependency (Finch-backed HTTP client; ships a `Req.Test` adapter used by the unit tests).
- [X] T002 Add the Anthropic configuration block across the three env files: defaults in `config/config.exs` (`base_url: "https://api.anthropic.com"`, `model: "claude-haiku-4-5-20251001"`, `timeout_ms: 5000`); env-var-driven overrides in `config/runtime.exs` (`ANTHROPIC_API_KEY`, plus optional `ANTHROPIC_BASE_URL` / `ANTHROPIC_MODEL` / `ANTHROPIC_TIMEOUT_MS`); and a `Req.Test`-stub `base_url` in `config/test.exs` so unit tests never hit the network. Config key: `config :agenticrealms, AgenticRealms.Anthropic, ...` per `research.md` §10.
- [X] T003 Run `mix test` from repo root and confirm all existing 003 / 004 tests pass (expect 133 tests, 0 failures, integration tests excluded) before any 005 work begins.

**Checkpoint**: `mix deps.get` succeeds, config compiles, baseline is green.

---

## Phase 2: Foundational (Blocking Prerequisites — full implementation)

**Purpose**: Build the entire intent-resolution pipeline. Because the three user stories all exercise the same code path, the implementation is monolithic and lands here in full. After this phase the feature is functionally complete; Phases 3–5 add the test coverage that proves each user story.

**⚠️ CRITICAL**: No user-story test work can begin until this phase is complete.

- [X] T004 [P] Create the system prompt content file `priv/intent_resolver/system_prompt.md` with the role, rules, and 9 few-shot examples per `contracts/system_prompt.md` "System prompt content". AND create `lib/agenticrealms/world/intent_resolver/system_prompt.ex` exposing `text/0` that compile-loads the markdown file via `@external_resource` + `File.read!/1`.
- [X] T005 [P] Create `lib/agenticrealms/world/intent_resolver/tools.ex` exposing `list/0`, which returns the 10 tool definitions (9 canonical actions + `refuse`) as a list of maps matching `contracts/tools.md` exactly. The `refuse` tool (last in the list) carries the `cache_control: %{type: "ephemeral"}` marker.
- [X] T006 [P] Create `lib/agenticrealms/world/intent_resolver/context_snapshot.ex` exposing `build/2` (player_id, raw_input → the volatile user-message string). Calls `Queries.look_room/1` and `Queries.list_inventory/1`, formats per `contracts/system_prompt.md` "Volatile user message format" (300-char description truncation, "(none)"/"(empty)" placeholders for empty collections, verbatim `Player typed:` line).
- [X] T007 [P] Create `lib/agenticrealms/anthropic.ex` — a thin Req wrapper exposing `create_message/1` (request-body map → `{:ok, response_body}` | `{:error, reason}`). Attaches `x-api-key` and `anthropic-version` headers, enforces the configured receive timeout, maps all non-200 / network / decode failures to `{:error, _}`. Reads config from `Application.fetch_env!(:agenticrealms, AgenticRealms.Anthropic)`.
- [X] T008 [P] Modify `lib/agenticrealms/application.ex` to add `{Task.Supervisor, name: AgenticRealms.IntentResolverTaskSupervisor}` to the supervision tree, placed after `Phoenix.PubSub`.
- [X] T009 Create `lib/agenticrealms/world/intent_resolver.ex` — the `resolve/2` facade per `contracts/intent_resolver_api.md`. Depends on T004–T007. Implements: pre-flight checks (500-char cap, current-room check), context build, Anthropic request construction (cached system + tools, volatile user message, `tool_choice: {type: "any"}`, `max_tokens: 256`), response parsing (single `tool_use` block → action tuple; `refuse` → `{:error, message}`; everything else → uniform refusal; multiple tool calls → "Try one action at a time."), and per-invocation `Logger` + `:telemetry` emission with the cache-hit signal from the response `usage` block.
- [X] T010 Modify `lib/agenticrealms_web/live/game_live.ex`: (a) replace the `{:unknown, raw}` branch of `handle_event("submit_command", …)` so it spawns `Task.Supervisor.async_nolink(AgenticRealms.IntentResolverTaskSupervisor, IntentResolver, :resolve, [player_id, raw])`, stores `%{ref:, raw_input:, spawned_at:}` in a new `:resolver_task` assign, sets a new `:input_locked` assign to `true`, and returns `{:noreply, socket}` immediately; (b) add a `handle_info/2` clause matching `{ref, {:ok, action_tuple}}` for the active `resolver_task.ref` that demonitors the ref, clears `:resolver_task`, unlocks input, and dispatches the action tuple through the SAME case branches the parser sentinels use (`handle_take`, `handle_move`, etc. — passing the stored `raw_input` so they echo `:cmd` correctly); (c) add a `handle_info/2` clause matching `{ref, {:error, refusal_msg}}` that demonitors, clears `:resolver_task`, unlocks input, appends a `:cmd` echo of the stored raw input followed by a `:system` refusal entry; (d) add a `handle_info/2` clause matching `{:DOWN, ref, …}` for the resolver task ref that treats a crashed task as a graceful refusal. Initialize `:resolver_task` (nil) and `:input_locked` (false) in `mount/3`.
- [X] T011 Modify the command-input rendering (`lib/agenticrealms_web/components/game_components.ex`, the `p-input-row` form) to disable the input and show a "thinking…" placeholder while `@input_locked` is true. Wire `@input_locked` through from `GameLive` assigns to the component.
- [X] T012 Run `mix compile --warnings-as-errors` and confirm the application boots cleanly (`iex -S mix` with the new `Task.Supervisor` child and no Anthropic key set — the feature must degrade gracefully, not crash, when `ANTHROPIC_API_KEY` is absent).

**Checkpoint**: The feature is functionally complete. With `ANTHROPIC_API_KEY` set, natural-language commands resolve; without it, they degrade to "I don't understand" refusals. Phases 3–5 now add proving tests.

---

## Phase 3: User Story 1 - Natural-Language Variants Resolve to Supported Actions (Priority: P1) 🎯 MVP

**Goal**: Prove that natural-language phrasings the fast parser rejects resolve to the correct canonical action for all nine verbs, producing the identical game effect as the canonical form.

**Independent Test**: With a mocked Anthropic response, `IntentResolver.resolve/2` returns the correct action tuple for each of the nine verbs; end-to-end in a LiveView, submitting `grab the lantern off the table` moves the lantern to inventory exactly as `take brass lantern` would.

### Tests for User Story 1

- [X] T013 [P] [US1] Create `test/agenticrealms/world/intent_resolver/tools_test.exs` — structural tests: exactly 10 tools; every canonical action (`take`, `drop`, `move`, `look`, `inventory`, `say`, `emote`, `tell`, `whisper`) present exactly once; `refuse` present; `refuse` carries the `cache_control` marker and is last; each tool has a well-formed `input_schema`; `move`'s direction is a 6-value enum.
- [X] T014 [P] [US1] Create `test/agenticrealms/world/intent_resolver/context_snapshot_test.exs` — `build/2` unit tests against a fixture room + inventory: room name/description/exits/objects/occupants render correctly; description truncates at 300 chars with an ellipsis; empty collections render as "(none)"/"(empty)"; the `Player typed:` line preserves the raw input verbatim (casing + internal whitespace).
- [X] T015 [P] [US1] Create `test/agenticrealms/world/intent_resolver_test.exs` with a `describe "resolve/2 — happy path"` block. Using `Req.Test` stubs that return a canned `tool_use` response, assert `resolve/2` returns the correct action tuple for each of the nine verbs (take/drop with `object`, move with `direction` enum, look/inventory with no args, say/emote with `text`, tell/whisper with `recipient`+`text`). Verify the action tuple shapes match the `CommandParser` sentinels exactly (per `data-model.md` Entity 5).
- [X] T016 [P] [US1] Create `test/agenticrealms_web/live/game_live_intent_parser_test.exs` (tagged `:integration`, consistent with 004's pattern) with a `describe "natural-language success path"` block. With the Anthropic call stubbed to return a `take` tool call, submit a natural-language command via the LiveView form and assert: the input locks during resolution, then unlocks; the lantern moves to the player's inventory; the `:cmd` echo shows the player's literal input (not a canonicalized form); the standard `:system` confirmation appears.

**Checkpoint**: US1 fully tested. The MVP — natural-language input resolving to correct actions — is proven.

---

## Phase 4: User Story 2 - Clear Refusals for Unsupported or Ambiguous Intent (Priority: P2)

**Goal**: Prove that out-of-scope, near-mapping, multi-step, and nonsense intent each produce a refusal entry with no game action taken, and that the resolver never substitutes a near-mapping action.

**Independent Test**: With mocked Anthropic responses, `resolve/2` returns `{:error, message}` for a `refuse` tool call and `{:error, "Try one action at a time."}` for a multi-tool response; end-to-end, a refusal-triggering input produces a `:system` refusal entry and no state change.

### Tests for User Story 2

- [X] T017 [US2] Append a `describe "resolve/2 — refusals"` block to `test/agenticrealms/world/intent_resolver_test.exs`: a `refuse` tool call returns `{:error, <model's message>}`; a response with two `tool_use` blocks returns `{:error, "Try one action at a time."}` (multi-step, FR-010); a `refuse` response for near-mapping input (`examine the lantern`) returns the model's hint message and asserts NO `look` action tuple is produced (FR-007a); a `refuse` for an out-of-game question returns the model's message verbatim.
- [X] T018 [P] [US2] Append a `describe "refusals"` block to `test/agenticrealms_web/live/game_live_intent_parser_test.exs`: with the resolver stubbed to return `{:error, msg}`, submit a refusal-triggering natural-language input and assert the LiveView appends a `:cmd` echo of the literal input plus a `:system` entry carrying the refusal message, takes no game action (inventory/room unchanged), and unlocks the input.

**Checkpoint**: US1 + US2 tested. Refusal safety boundary proven, including the near-mapping no-substitution rule.

---

## Phase 5: User Story 3 - Game Remains Responsive When the Resolver Fails (Priority: P3)

**Goal**: Prove that AI service failures (unreachable, timeout, malformed response, missing key) produce graceful refusals with zero crashes and zero impact on other players.

**Independent Test**: With the Anthropic call stubbed to fail in each mode, `resolve/2` returns the uniform graceful refusal; end-to-end, a failing resolver leaves the player's session usable and other players' fast-path commands unaffected.

### Tests for User Story 3

- [X] T019 [P] [US3] Create `test/agenticrealms/anthropic_test.exs` — HTTP client unit tests via `Req.Test`: the `x-api-key` and `anthropic-version` headers are attached; the request body carries `model`, `system`, `tools`, `messages`, `max_tokens`, `tool_choice`; a 200 response body is returned as `{:ok, body}`; 4xx and 5xx responses map to `{:error, _}`; a network/transport error maps to `{:error, _}`; a malformed (non-JSON) body maps to `{:error, _}`; the configured receive timeout is enforced.
- [X] T020 [US3] Append a `describe "resolve/2 — failure modes"` block to `test/agenticrealms/world/intent_resolver_test.exs`: HTTP timeout → `{:error, "I'm not sure what you meant just now."}`; HTTP 5xx → same; malformed JSON → same; a response with no `tool_use` block → same; a response with an unrecognized tool name → same; a missing `ANTHROPIC_API_KEY` → `{:error, "I don't understand that."}` (pre-005 fallback copy). No exception escapes `resolve/2` in any case.
- [X] T021 [P] [US3] Append a `describe "resilience"` block to `test/agenticrealms_web/live/game_live_intent_parser_test.exs`: with the resolver stubbed to fail, submit a natural-language command and assert the player sees a graceful `:system` refusal, the input unlocks, and the session remains responsive to a subsequent (canonical, fast-path) command; assert a second player's canonical command in the same test is unaffected (no shared blocking).

**Checkpoint**: All three user stories tested. The feature is proven across success, refusal, and failure paths.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Real-API validation, formatting, and regression confirmation.

- [X] T022 [P] Created `test/agenticrealms/world/intent_resolver_live_test.exs` (tagged `:live_llm`, excluded from the default run) — 12 curated inputs across all nine verbs + near-mapping/multi-step/out-of-game refusals. Self-skips when `ANTHROPIC_API_KEY` is unset; run on demand with `mix test --include live_llm`.
- [ ] T023 [P] **Deferred** — manual quickstart walkthrough needs `mix phx.server` + browser sessions; user-driven validation. Doc: `specs/005-llm-intent-parser/quickstart.md`.
- [X] T024 [P] `mix format` applied; `mix format --check-formatted` clean.
- [X] T025 [P] Full `mix test` — **175 tests, 0 failures** (4 excluded: 3 `:integration` + 1 `:live_llm`). Zero regressions in 003/004; tagged tests correctly excluded by default.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: T001–T003 — T001 before all; T002 before T009/T012; T003 is a gate before feature work.
- **Foundational (Phase 2)**: T004–T012 — depends on Phase 1. This phase is the complete implementation; it BLOCKS all test phases.
- **User Story test phases (Phases 3–5)**: each depends only on Phase 2 being complete. Once Phase 2 lands, US1 / US2 / US3 test phases can be written in parallel — they touch mostly separate test files (with intra-file sequencing noted below).
- **Polish (Phase 6)**: depends on Phases 3–5 for the regression sweep; T022/T023 (live validation) depend on Phase 2 only.

### Within Phase 2

- T004, T005, T006, T007, T008 — five distinct new files (+ one independent modification), all `[P]`.
- T009 depends on T004–T007 (it imports SystemPrompt, Tools, ContextSnapshot, Anthropic).
- T010 depends on T008 (Task.Supervisor) and T009 (IntentResolver).
- T011 depends on T010 (the `:input_locked` assign it renders is introduced in T010). Different file from T010, but sequenced after it.
- T012 is the post-implementation compile/boot gate — after T004–T011.

### Within each test phase

- Test tasks that create NEW files are `[P]` with each other.
- Test tasks that APPEND to a file created in an earlier phase are sequenced after that file exists and are not `[P]` with other appends to the same file. Specifically: T017 and T020 both append to `intent_resolver_test.exs` (created by T015) — they run sequentially. T018 and T021 both append to `game_live_intent_parser_test.exs` (created by T016) — sequentially.

### Parallel Opportunities

- **Phase 2**: T004–T008 in parallel (six distinct files / one independent edit).
- **Phase 3**: T013–T016 in parallel (four distinct new test files).
- **Phase 4**: T018 is `[P]` (different file from T017).
- **Phase 5**: T019 and T021 are `[P]` (distinct files from T020).
- **Phase 6**: T022–T025 all `[P]`.
- Across test phases, after Phase 2 lands, US1/US2/US3 can be staffed to different developers — the only coordination cost is the two shared test files (`intent_resolver_test.exs`, `game_live_intent_parser_test.exs`).

---

## Parallel Example: Phase 2 Foundational

```text
# Launch the five independent foundational tasks together:
Task: T004 — system prompt content + loader (priv/intent_resolver/, intent_resolver/system_prompt.ex)
Task: T005 — tool definitions (intent_resolver/tools.ex)
Task: T006 — context snapshot builder (intent_resolver/context_snapshot.ex)
Task: T007 — Anthropic HTTP client (anthropic.ex)
Task: T008 — Task.Supervisor child (application.ex)

# Then sequentially, because of dependencies:
T009 (intent_resolver.ex)  →  T010 (game_live.ex)  →  T011 (game_components.ex)  →  T012 (compile gate)
```

---

## Implementation Strategy

### MVP First (Phase 1 → 2 → 3)

1. Complete Phase 1 (Setup) and Phase 2 (Foundational) — this is the complete implementation.
2. Complete Phase 3 (US1 tests) — proves natural-language resolution works for all nine verbs.
3. **STOP and VALIDATE**: run `mix test`; walk quickstart §1–4 with a real key. If green, the MVP is shippable — players can speak naturally to the game.
4. Deploy / demo if desired.

### Incremental Delivery

1. Setup + Foundational → feature functionally complete.
2. Add US1 tests → success path proven → demo (MVP).
3. Add US2 tests → refusal coverage proven → demo.
4. Add US3 tests → resilience proven → demo.
5. Polish (live smoke test, regression sweep).

Because the implementation is monolithic (Phase 2), the "increments" here are increments of **proven confidence**, not increments of shipped code. The code ships once (Phase 2); each test phase raises the assurance level for one user story.

### A note on the monolithic Phase 2

Unlike feature 004 (where each user story added a new verb and thus new code), 005's three user stories all exercise the one resolver pipeline. There is no useful subset of the implementation that satisfies US1 without also satisfying US2's refusal handling (the resolver cannot function without the `refuse` path) or US3's failure handling (the resolver cannot function without timeout handling). The task structure reflects this honestly: implement once, then prove three ways.

---

## Notes

- `[P]` = different files, no dependency on an incomplete task. Concentrated in Phase 2 (distinct new files) and the test phases (distinct new test files).
- `[Story]` labels appear only on user-story test-phase tasks (US1/US2/US3). Setup, Foundational, and Polish tasks are unlabeled.
- No new migrations, no event-store changes, no `World.Commands` changes. The only new runtime dependency is `req`.
- The feature degrades gracefully without `ANTHROPIC_API_KEY` — every task must preserve that property (an unset key is a graceful refusal, never a crash).
- Commit after each task or logical group, consistent with the 003 / 004 commit cadence.
- The `:live_llm`-tagged smoke test costs real API tokens — keep it out of CI's default run; it is an on-demand validation tool.
