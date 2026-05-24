# Tasks: NPC Conversations (Feature 010)

**Input**: Design documents from `/specs/010-npc-conversations/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Test tasks are INCLUDED — the spec defines extensive success criteria (SC-001 through SC-007) and the project's prior features (005, 007, 008, 009) all built with paired test coverage. The pattern continues.

**Organization**: Tasks are grouped by user story (US1–US5 from spec.md) so each story can be implemented and verified independently after the foundational layer is complete.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Parallelizable — different files, no dependencies on incomplete tasks
- **[Story]**: User story (US1–US5); omitted for Setup, Foundational, and Polish phases

## Path Conventions

Phoenix LiveView single project. All paths under repo root `/Users/kevin/code/autodidaddict/agentic-realms/`. Implementation files under `lib/`, tests under `test/`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project-level dependency and configuration scaffolding.

- [X] T001 Add `{:horde, "~> 0.9"}` to the `deps/0` list in `mix.exs` (alphabetically near the other libraries).
- [X] T002 Run `mix deps.get` to fetch Horde; verify `mix compile` still succeeds.
- [X] T003 [P] Create directory `lib/agenticrealms/world/npc_chat/` for the new module tree.
- [X] T004 [P] Create directory `test/agenticrealms/world/npc_chat/` for the new test tree.
- [X] T005 [P] Add to `config/test.exs` a `config :agenticrealms, AgenticRealms.World.NPCChat, idle_timeout_ms: 200` override so idle-timeout tests run fast.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Persistent lore plumbing, cluster supervision tree, transient UI event types, and rendering — all consumed by every user story below.

⚠️ Every task in this phase MUST complete before any User Story phase begins.

### Persistence layer — lore column + event extensions

- [X] T006 Create migration `priv/repo/migrations/<timestamp>_add_lore_columns.exs` that adds `lore TEXT NOT NULL DEFAULT ''` to both `npc_blueprints` and `npc_clones` (template per data-model.md §1.4).
- [X] T007 Run `mix ecto.migrate` and verify schema reflects the new column (use `psql` or `mix ecto.dump`).
- [X] T008 [P] Add `field :lore, :string, default: ""` to `lib/agenticrealms/world/schemas/npc_blueprint.ex` (alongside the existing fields).
- [X] T009 [P] Add `field :lore, :string, default: ""` to `lib/agenticrealms/world/schemas/npc_clone.ex`.
- [X] T010 [P] Add `field :lore, :string, default: ""` to the `defstruct`/`@enforce_keys`-safe section of `lib/agenticrealms/world/commands/create_npc_blueprint.ex` (NOT in @enforce_keys — backward compat).
- [X] T011 [P] Add `field :lore, :string, default: ""` to `lib/agenticrealms/world/events/npc_blueprint_created.ex` (same backward-compat pattern as feature 009's `behaviors`).
- [X] T012 [P] Add `field :lore, :string, default: ""` to `lib/agenticrealms/world/events/npc_cloned_from_blueprint.ex`.
- [X] T013 Extend `lib/agenticrealms/world/npc_blueprint.ex` aggregate: blueprint creation carries `lore` from the command into `NPCBlueprintCreated`; clone creation copies `lore` from the aggregate state into `NPCClonedFromBlueprint` (full-copy semantics — mirror feature 008/009 plumbing).
- [X] T014 Extend `lib/agenticrealms/world/projections/world_projector.ex` to include `:lore` in the `Repo.insert!/2` keyword list for `NPCBlueprintCreated` and `NPCClonedFromBlueprint` handlers.
- [X] T015 Extend `lib/agenticrealms/world/seed.ex`: add a `garrick_lore` string (a short paragraph naming Garrick's bridge-guard / Riverford backstory) and pass it on `CreateNPCBlueprint` for the Garrick blueprint (FR-015).

### Cluster supervision tree

- [X] T016 Create `lib/agenticrealms/world/npc_chat/registry.ex` — a thin module that defines `child_spec/1` returning `{Horde.Registry, name: __MODULE__, keys: :unique, members: :auto}` and a `via_tuple/1` helper that produces `{:via, Horde.Registry, {__MODULE__, key}}`.
- [X] T017 Create `lib/agenticrealms/world/npc_chat/supervisor.ex` — wraps `Horde.DynamicSupervisor` with `name: __MODULE__, strategy: :one_for_one, members: :auto, distribution_strategy: Horde.UniformDistribution`. Exposes `start_child/1` and `find_or_start/2` helpers.
- [X] T018 Create `lib/agenticrealms/world/npc_chat/task_supervisor.ex` — a thin wrapper that starts `Task.Supervisor` under name `AgenticRealms.World.NPCChat.TaskSupervisor`. (Used by Conversation for LLM-call tasks.)
- [X] T019 Add the three children to `lib/agenticrealms/application.ex` `start/2`: `AgenticRealms.World.NPCChat.Registry`, `AgenticRealms.World.NPCChat.Supervisor`, `AgenticRealms.World.NPCChat.TaskSupervisor` — placed as siblings of the existing `IntentResolverTaskSupervisor` (the natural neighbor since both supervise LLM-related work).

### Transient UI event types

- [X] T020 [P] Add `AgenticRealms.World.UIEvents.ChatUtterance` struct to `lib/agenticrealms/world/ui_events.ex` per contracts/ui_events.md — keys `:kind` (`:chat_speech | :chat_emote`), `:npc_clone_id`, `:npc_name`, `:text`, `:triggering_player_id`, all `@enforce_keys`.
- [X] T021 [P] Add `AgenticRealms.World.UIEvents.ChatSystemMessage` struct to `lib/agenticrealms/world/ui_events.ex` — keys `:kind` (`:chat_new | :chat_continuing | :chat_in_flight_rejection | :chat_fallback`), `:npc_name`, `:text`, `:player_id`, all `@enforce_keys`.

### Rendering

- [X] T022 [P] Add a `log_entry/1` clause for `kind: :chat_speech` to `lib/agenticrealms_web/components/game_components.ex` — renders `<div class="log-entry speech speech-npc speech-chat"><span class="who">{actor_name}</span> says, &ldquo;{text}&rdquo;</div>` per contracts/render.md.
- [X] T023 [P] Add a `log_entry/1` clause for `kind: :chat_emote` to `lib/agenticrealms_web/components/game_components.ex` — renders `<div class="log-entry emote emote-chat"><span class="who">{actor_name}</span> {text}</div>`.
- [X] T024 [P] Add a `log_entry/1` clause for `kind: :chat_system` to `lib/agenticrealms_web/components/game_components.ex` — renders `<div class={"log-entry chat-system " <> kind_class}>{text}</div>` where `kind_class` is derived from `kind_variant` (`:chat_new` → `"chat-new"`, `:chat_continuing` → `"chat-continuing"`, `:chat_fallback` → `"chat-fallback"`, `:chat_in_flight_rejection` → `"chat-in-flight"`).

### Replay safety check

- [X] T025 [P] Add a test to `test/agenticrealms/world/world_projector_npc_replay_test.exs` that constructs an old-shape `NPCBlueprintCreated` event (no `lore` key) via `struct/2` and asserts the projector inserts a Blueprint row with `lore == ""` — defends the FR-014/backward-compat invariant from research.md R-010.

---

## Phase 3: User Story 1 — Player chats with an NPC and receives an in-character reply (P1)

**Story goal**: A logged-in player can issue `chat <npc> <message>` to an NPC in their room, see a "started new conversation" indicator, then see Garrick's in-character reply rendered privately in their log.

**Independent test**: After login as a fresh player, type `chat Garrick hello`; observe the `:chat_new` system message then a `:chat_speech` or `:chat_emote` entry in the log; no entries leak to another player's session.

### Pure modules (parallelizable)

- [X] T026 [P] [US1] Create `lib/agenticrealms/world/npc_chat/tools.ex` implementing `list/0` and `names/0` per contracts/tools.md (two tools: `say` and `emote`, each with a required `text` string input).
- [X] T027 [P] [US1] Create `lib/agenticrealms/world/npc_chat/reply.ex` implementing `parse/1` per contracts/reply.md — exactly-one `tool_use` block in `content`, matched against `Tools.names()`, with a non-empty trimmed text → `{:speech, t} | {:emote, t} | {:error, :malformed}`.
- [X] T028 [P] [US1] Create `lib/agenticrealms/world/npc_chat/system_prompt.ex` implementing `text/1` per contracts/system_prompt.md — accepts the snapshot map and produces the system prompt string. Covers FR-008 a–f including the empty-lore fallback paragraph (used downstream for US5).
- [X] T029 [P] [US1] Create `lib/agenticrealms/world/npc_chat/context.ex` implementing `snapshot/2` (queries the room state) and `build_request/3` (assembles the Anthropic Messages API request body with `max_tokens: 256`, the system prompt, the two tools, `tool_choice: any`, and the history+current-utterance messages array) per contracts/context.md.

### Conversation GenServer (the central state holder)

- [X] T030 [US1] Create `lib/agenticrealms/world/npc_chat/conversation.ex` — the `use GenServer` module per contracts/conversation.md. Implement `start_link/1` (registered via `Registry.via_tuple({player_id, npc_clone_id})`), `init/1` (caches `npc_name`, `npc_clone_id`, `lore` from the passed clone struct; sets `turns: []`, `pending?: false`, `last_activity_at: nil`), and the idle-timeout return shape `{:ok, state, @idle_timeout}`. Read `@idle_timeout` from `Application.get_env(:agenticrealms, AgenticRealms.World.NPCChat, [])[:idle_timeout_ms] || 60_000`.
- [X] T031 [US1] In `lib/agenticrealms/world/npc_chat/conversation.ex`, implement `handle_call({:send, player_id, message}, _from, state)`: (a) if `pending?` → reply `{:error, :still_thinking}` (FR-020); (b) otherwise compute `new_or_continuing` from `last_activity_at` (nil OR `now - last_activity_at > 60_000` → `:new`, dropping any stale `turns`); (c) broadcast a `ChatSystemMessage` (`:chat_new` or `:chat_continuing`) on `player_topic`; (d) set `pending? = true`, `pending_player_message = message`, `last_activity_at = now`; (e) start a Task under `NPCChat.TaskSupervisor` that calls `Anthropic.create_message(Context.build_request(snapshot, state.turns, message))` and sends `{:llm_result, ref, result}` to `self()`; (f) reply `{:ok, new_or_continuing}` with `{:noreply, _, @idle_timeout}` (NB: the reply happens in `:reply` and state continues with the timeout).
- [X] T032 [US1] In `lib/agenticrealms/world/npc_chat/conversation.ex`, implement `handle_info({:llm_result, ref, {:ok, response_body}}, state)`: call `Reply.parse/1`; on `{:speech, t}` or `{:emote, t}` append two entries to `turns` (player + NPC), broadcast `ChatUtterance{kind: :chat_speech | :chat_emote}` on `player_topic`, clear `pending?`, `pending_player_message`, `task_ref`. On `{:error, :malformed}` fall through to the failure path.
- [X] T033 [US1] In `lib/agenticrealms/world/npc_chat/conversation.ex`, implement `handle_info({:llm_result, ref, {:error, _reason}}, state)`: DO NOT append `pending_player_message` to `turns`; broadcast `ChatSystemMessage{kind: :chat_fallback, text: "{npc_name} seems lost in thought."}` on `player_topic`; clear `pending?`, `pending_player_message`, `task_ref`. (FR-011)
- [X] T034 [US1] In `lib/agenticrealms/world/npc_chat/conversation.ex`, implement `handle_info(:timeout, state)` returning `{:stop, :normal, state}` (FR-006 idle reap). Also handle `{:DOWN, ref, :process, _, reason}` for the Task in case the Task crashes unexpectedly — same treatment as `:llm_result` error.
- [X] T035 [US1] In `lib/agenticrealms/world/npc_chat/conversation.ex`, add a test-only `handle_call({:get_state}, _from, state)` clause returning the full state — used by Conversation tests for introspection.

### Public API + command pipeline

- [X] T036 [US1] Create `lib/agenticrealms/world/npc_chat.ex` — the dev-facing API module — implementing `send/3` per contracts/npc_chat_api.md (input validation FR-019a, NPC resolution, find-or-start the Conversation, forward via `GenServer.call`). Implement `find/2` for tests.
- [X] T037 [US1] Extend `lib/agenticrealms/world/command_parser.ex` to recognize `"chat " <> rest` as the fast path. Parse `rest` as `npc_token <whitespace> message` — first token is the NPC name (matching the existing `tell <player> <message>` parsing pattern). Return `{:chat, npc_token, message}`. On a too-short or malformed `chat` line return `{:error, :chat_usage}` so GameLive can render a usage hint.
- [X] T038 [US1] Add a `chat` tool definition to `lib/agenticrealms/world/intent_resolver/tools.ex` (with `npc` and `message` parameters) per research.md R-004, so natural-language phrasing ("talk to garrick", "ask the innkeeper about ...") resolves to chat. Add `:chat` to `IntentResolver.action_tuple()` and `IntentResolver.parse_response/1` mapping.
- [X] T039 [US1] Update `lib/agenticrealms/world/intent_resolver/system_prompt.ex` (and/or the prompt text constants used by it) to document the `chat` tool's availability so the LLM picks it for conversation phrasing.

### LiveView wiring

- [X] T040 [US1] In `lib/agenticrealms_web/live/game_live.ex`, add the `{:chat, npc_token, message}` action handler (next to the existing `:say`, `:emote`, `:look` handlers). It calls `NPCChat.send(player_id, npc_token, message)` and maps the result tuple to log entries (or renders the appropriate refusal text for `:no_such_npc`, `:ambiguous_npc`, `:too_long`, `:empty_message`, `:still_thinking`, `:no_current_room`).
- [X] T041 [US1] In `lib/agenticrealms_web/live/game_live.ex`, add a `handle_info(%ChatUtterance{} = u, socket)` clause that appends a `%{kind: u.kind, actor_name: u.npc_name, text: u.text}` entry to `@log` (or whatever the existing log assigns key is) via the existing append helper.
- [X] T042 [US1] In `lib/agenticrealms_web/live/game_live.ex`, add a `handle_info(%ChatSystemMessage{} = m, socket)` clause that appends a `%{kind: :chat_system, kind_variant: m.kind, text: m.text}` entry to `@log`.

### Tests (US1 — happy path)

- [X] T043 [P] [US1] Create `test/agenticrealms/world/npc_chat/tools_test.exs` covering contracts/tools.md test surface — list length, schema shape, names set, JSON round-trip.
- [X] T044 [P] [US1] Create `test/agenticrealms/world/npc_chat/reply_test.exs` covering contracts/reply.md test surface — speech, emote, malformed-name, empty-text, missing-text, multi-tool, zero-tool, missing-content, non-list-content, whitespace trimming.
- [X] T045 [P] [US1] Create `test/agenticrealms/world/npc_chat/system_prompt_test.exs` covering contracts/system_prompt.md test surface — required-substring assertions for each FR-008 clause, presence/absence of lore branch, purity.
- [X] T046 [P] [US1] Create `test/agenticrealms/world/npc_chat/context_test.exs` covering contracts/context.md test surface — snapshot shape, build_request shape, message_history mapping, history trim eviction.
- [X] T047 [US1] Create `test/agenticrealms/world/npc_chat/conversation_test.exs` with: (a) "first :send returns {:ok, :new} and broadcasts :chat_new BEFORE returning"; (b) "{:llm_result, _, speech-shaped response} appends to turns and broadcasts :chat_speech"; (c) "{:llm_result, _, emote-shaped response} broadcasts :chat_emote"; (d) "{:llm_result, _, error} does NOT append to turns and broadcasts :chat_fallback". Each test uses a directly-spawned Conversation (bypassing the registry) and a stubbed Anthropic via `Req.Test`.
- [X] T048 [US1] Create `test/agenticrealms/world/npc_chat_test.exs` for the public API covering happy-path send (`{:ok, :new}` → state-machine continues to broadcast reply), `:no_such_npc`, `:ambiguous_npc`, `:too_long`, `:empty_message`. Uses the real Horde.Registry / Horde.DynamicSupervisor (the application tree is started by `AgenticRealms.DataCase`).

---

## Phase 4: User Story 2 — Multi-turn history persists within the timeout window (P2)

**Story goal**: A multi-turn chat with an NPC carries history forward across turns until 60 seconds of inactivity, then resets cleanly.

**Independent test**: Send three `chat Garrick ...` within 60s — first reports `:chat_new`, next two report `:chat_continuing`; wait >60s; the fourth reports `:chat_new` and the LLM call carries no prior turns.

- [X] T049 [US2] In `lib/agenticrealms/world/npc_chat/conversation.ex`, implement the 20-turn-pair history cap (per FR-004): after appending a player+NPC pair to `turns`, drop the oldest pair(s) from the head so `length(turns) <= 40`. Add an `@history_cap_pairs 20` module attribute.
- [X] T050 [US2] In `lib/agenticrealms/world/npc_chat/context.ex`, refine `build_request/3` so the messages array reflects `state.turns` correctly — alternating user/assistant entries, in oldest-to-newest order. Assistant entries render their prior mode (speech wraps as `Name says, "..."`, emote as `Name <text>`) so the LLM sees its own previous form.
- [X] T051 [US2] In `lib/agenticrealms/world/npc_chat/conversation.ex`, refine the new-vs-continuing logic in `handle_call({:send, ...})` to be airtight: `:new` strictly when `last_activity_at == nil` OR `now - last_activity_at > 60_000` (the timeout reference, not the spec's "≤ 60s within"). On `:new`, drop any stale `turns` entries from a prior conversation that somehow survived (defense-in-depth — the idle reap should have killed them, but a quick reconnect could race).
- [X] T052 [P] [US2] Extend `test/agenticrealms/world/npc_chat/conversation_test.exs` with: (a) "second :send within 60s returns {:ok, :continuing} and broadcasts :chat_continuing"; (b) "after the 21st turn, history is capped at 20 pairs and the oldest pair is dropped"; (c) "idle-timeout (with idle_timeout_ms: 200 override) terminates the process and Horde.Registry.lookup returns []"; (d) "two independent (player_id, npc_clone_id) pairs maintain separate histories".
- [X] T053 [P] [US2] Extend `test/agenticrealms/world/npc_chat/context_test.exs` with: (a) "history with 1 player + 1 NPC turn produces a 3-message array (user, assistant, user)"; (b) "history with 21 turn-pairs produces a 41-message array — wait, no, this is impossible because Conversation trims first — instead: build_request given 21 pairs in `turns` evicts the oldest pair before producing the array".

---

## Phase 5: User Story 3 — NPC reply is grounded in the surrounding environment (P2)

**Story goal**: When the player asks the NPC about other players or objects in the room, the NPC's reply reflects current room state.

**Independent test**: With Alice and Bob in the same room with Garrick, Alice asks `chat Garrick who's here besides me?` — the LLM call's system prompt contains Bob's display name; the NPC's reply (stubbed in tests) references him.

- [X] T054 [US3] In `lib/agenticrealms/world/npc_chat/context.ex` `snapshot/2`, ensure `other_players` excludes both the chatting player AND the participating NPC, contains display names only, and is filtered by `Presence.online?/1` (consistent with feature 003b's offline-filtering pattern).
- [X] T055 [US3] In `lib/agenticrealms/world/npc_chat/context.ex` `snapshot/2`, populate `objects` as a list of `%{name, short_description}` from `Queries.list_objects_in_room/1`, truncating each `short_description` to 200 characters to bound prompt growth.
- [X] T056 [US3] In `lib/agenticrealms/world/npc_chat/system_prompt.ex` `text/1`, render `other_players` and `objects` into the "The scene" section per contracts/system_prompt.md.
- [X] T057 [P] [US3] Extend `test/agenticrealms/world/npc_chat/context_test.exs` with: (a) "snapshot/2 does NOT include the chatting player in other_players"; (b) "snapshot/2 does NOT include the participating NPC"; (c) "snapshot/2 truncates object short_descriptions to 200 chars"; (d) "snapshot/2 filters offline players from other_players".
- [X] T058 [P] [US3] Extend `test/agenticrealms/world/npc_chat/system_prompt_test.exs` with: (a) "with two other players present, both names appear in the system prompt"; (b) "with three objects present, all three short descriptions appear in the system prompt"; (c) "with no other players present, the 'Also present' clause is omitted"; (d) "with no objects present, the 'Nearby you can see' clause is omitted".

---

## Phase 6: User Story 4 — Out-of-lore questions receive an in-theme refusal (P3)

**Story goal**: When the player asks something off-topic or outside the NPC's lore, the LLM emits an emote-mode refusal (per system prompt) rather than a meta-reference.

**Independent test**: Stub the Anthropic call to return an `emote` tool-use response simulating `"raises an eyebrow curiously"`; the player log shows the rendered emote without any "as an AI" substring.

- [X] T059 [US4] In `lib/agenticrealms/world/npc_chat/system_prompt.ex`, verify the FR-008c clause is present and explicitly prefers emote-mode refusals (already in contracts/system_prompt.md rule 4). Adjust copy if the existing text under-specifies this preference.
- [X] T060 [P] [US4] Add a test to `test/agenticrealms/world/npc_chat/system_prompt_test.exs`: "rule 4 (out-of-scope refusal) contains the substring 'in-theme refusal' AND the substring 'emote'".
- [X] T061 [P] [US4] Add a test to `test/agenticrealms/world/npc_chat/conversation_test.exs`: "when LLM returns an emote-mode reply with text 'raises an eyebrow curiously', the broadcast ChatUtterance has kind: :chat_emote and text without surrounding quotes; the rendered HTML (via game_components render in a sub-test) does NOT contain any of: 'as an AI', 'as a language model', 'I am a chatbot', 'as a chatbot'".

---

## Phase 7: User Story 5 — NPCs without lore still respond minimally (P3)

**Story goal**: An NPC with `lore == ""` produces in-scene replies via the fallback paragraph; no crash, no fabrication.

**Independent test**: Seed a test NPC with empty lore in fixtures; chat with it; verify the system prompt uses the fallback paragraph and the broadcast reply is rendered correctly (with stubbed LLM).

- [X] T062 [US5] In `lib/agenticrealms/world/npc_chat/system_prompt.ex`, confirm `text/1` branches on `lore == ""` to substitute the empty-lore fallback paragraph (per contracts/system_prompt.md). This branch should already be in T028's implementation — this task is the verification + any adjustment.
- [X] T063 [P] [US5] Add a test to `test/agenticrealms/world/npc_chat/system_prompt_test.exs`: "with lore: \"\", the output contains 'You have no detailed backstory of your own' (the empty-lore fallback phrase) AND does NOT contain a stray '# Your identity and background' heading with empty content".
- [X] T064 [US5] Extend `test/agenticrealms/world/npc_chat/conversation_test.exs` with a test that constructs a Conversation for an NPC clone with `lore = ""` and confirms: (a) `:send` is accepted normally; (b) the LLM request payload (intercepted via `Req.Test`) contains the empty-lore fallback paragraph in its `system` block; (c) a stubbed reply is rendered identically to the lore-populated case.

---

## Phase 8: Polish & Cross-Cutting

**Purpose**: Cross-cutting verification, integration test, lint, documentation.

### Integration: end-to-end LiveView test

- [X] T065 Create `test/agenticrealms_web/live/game_live_chat_test.exs` (tagged `@moduletag :integration`) as a single comprehensive test covering US1–US5 in sequence — mirrors the feature 009 integration test pattern. Uses `Req.Test.set_req_test_to_shared/1` and a stub plug that returns canned `tool_use` responses (alternating speech/emote/empty-lore/refusal variants). The test asserts:
  - US1: `chat Garrick hello` produces `:chat_new` log entry then a `:chat_speech` log entry; both visible in Alice's rendered HTML; neither visible in Bob's HTML (SC-007).
  - US2: A second `chat Garrick ...` within the test's idle-timeout window produces `:chat_continuing`, and the second LLM-call payload contains the first turn's text in its `messages` array.
  - US3: With Bob in the room, a `chat Garrick who's here` LLM call payload's system prompt contains Bob's display name.
  - US4: A stubbed emote response (`"raises an eyebrow curiously"`) renders as a `:chat_emote` entry and the rendered HTML contains no "as an AI" / "as a language model" substrings.
  - US5: An NPC with `lore = ""` (set via Repo.update_all on a clone in the test setup) gets a system prompt that contains the empty-lore fallback paragraph.
  - FR-020: A second `chat Garrick ...` issued while a prior call is in flight (simulated via a Plug that sleeps before responding) produces a `:chat_in_flight_rejection` log entry and does NOT result in a second LLM call.
  - FR-016: After Alice moves north, `chat Garrick ...` is rejected with a no-such-NPC message.
- [X] T066 Add a helper `flush(view)` to the integration test file (mirrors feature 009's `flush/1` helper) and any `count_occurrences/2` style helpers needed for the SC-007 leak audit.

### Quality gates

- [X] T067 [P] Run `mix format --check-formatted` and ensure all new files are formatted (use `mix format` to auto-format if needed).
- [X] T068 [P] Run `mix compile --warnings-as-errors` and resolve any new warnings.
- [X] T069 [P] Run `mix test` (excludes `:integration`) and verify all unit/contract tests pass.
- [X] T070 [P] Run `mix test --include integration` and verify the new integration test passes.

### Documentation

- [X] T071 Add module @moduledoc strings to every new file under `lib/agenticrealms/world/npc_chat/` and `lib/agenticrealms/world/ui_events.ex` additions, each pointing back to `specs/010-npc-conversations/` and citing the relevant FR(s).
- [X] T072 [P] Add a Logger.debug call inside the Conversation's `:timeout` handler ("conversation (#{player_id}, #{npc_clone_id}) idled out") and inside the Context's eviction path ("evicted N turn-pairs to fit token budget") — supports the FR-019 / SC-005 verification in dev.

### Manual smoke

- [X] T073 Execute the quickstart.md walkthrough end-to-end on a clean `mix ecto.reset` + `mix phx.server`. Confirm all 9 expected log entries appear (including the FR-017 privacy check via Bob's window). Record any deviations as new tasks.

---

## Dependencies

**Phase ordering**:

```text
Setup (Phase 1) — T001–T005
       │
       ▼
Foundational (Phase 2) — T006–T025
       │
       ▼
US1 (Phase 3) — T026–T048    ←──── MVP slice
       │
       ▼
US2 (Phase 4) — T049–T053   ←──── multi-turn history
       │
       ▼
US3 (Phase 5) — T054–T058   ←──── environmental grounding
       │
       ▼
US4 (Phase 6) — T059–T061   ←──── out-of-lore refusal
       │
       ▼
US5 (Phase 7) — T062–T064   ←──── empty-lore fallback
       │
       ▼
Polish (Phase 8) — T065–T073
```

**Cross-story dependencies**:

- US2 depends on US1's Conversation GenServer (T030–T035) and Context module (T029) being in place. After US1, history was minimally exercised; US2 finishes the history-cap and continuing-indicator behavior.
- US3 depends on US1's Context module being in place. US3 adds the room/players/objects details to the snapshot.
- US4 depends on US1's SystemPrompt and Conversation tests. It's mostly verification of behavior already encoded in the foundational layer.
- US5 depends on US1's SystemPrompt module (which already includes the empty-lore branch from T028). It's primarily test coverage.
- After all US stories complete, Polish runs the integration test and final quality checks.

**Within-phase dependencies**:

- T006 → T007: migration must be created before it can be run.
- T013, T014: aggregate and projector touch fields added in T008–T012.
- T019 depends on T016, T017, T018 (must exist before being supervised).
- T030 (Conversation init) depends on T016 (Registry via_tuple) and T020/T021 (UI event structs the conversation emits) and T029 (Context module the conversation uses).
- T031–T035 are sequential edits to the same file (`conversation.ex`).
- T036 (NPCChat public API) depends on T017 (Supervisor.find_or_start) and T030–T035 (Conversation).
- T040, T041, T042 are sequential edits to `game_live.ex`.

---

## Parallel Execution Examples

### Setup (Phase 1)

T003, T004, T005 are mutually independent and can run in parallel after T001+T002.

### Foundational (Phase 2)

After T006+T007 (migration created and run):

- T008, T009, T010, T011, T012, T015 (file additions) can run in parallel.
- T013 must wait for T010, T011, T012.
- T014 must wait for T011, T012.
- T016, T017, T018 (independent file creates) can run in parallel.
- T019 must wait for T016, T017, T018.
- T020, T021, T022, T023, T024 can run in parallel.
- T025 can run in parallel with anything after T014.

### US1 (Phase 3)

After Phase 2 is complete:

- T026, T027, T028, T029 (the four pure modules) can run in parallel.
- T030–T035 are sequential edits to `conversation.ex`.
- T036 depends on T030–T035.
- T037, T038, T039 (CommandParser + IntentResolver edits) can run in parallel after T036.
- T040, T041, T042 (GameLive edits) are sequential.
- T043, T044, T045, T046 (parallel test files) can run in parallel.
- T047 depends on T030–T035 + `Req.Test` plug setup.
- T048 depends on T036.

### Polish (Phase 8)

T067, T068, T069 can run in parallel. T070 depends on T065+T066. T072 depends on T030+T029. T071 is a single sweep across all new files.

---

## Implementation Strategy

### MVP first

Complete Phase 1 + Phase 2 + Phase 3 (US1). At that point, the system supports:

- A logged-in player can `chat Garrick hello` and receive an in-character reply.
- Other players in the room see nothing of the exchange (FR-017).
- A second concurrent chat command to the same NPC is rejected (FR-020).
- Failed LLM calls produce the in-theme fallback line (FR-011).
- Idle-timeout reaps Conversation processes after 60 seconds.

Ship this as a demonstrable slice. The user can verify the privacy guarantee and the in-character reply quality before investing in the remaining stories.

### Incremental delivery

Each subsequent US is a self-contained add-on:

1. **+US2** — adds the multi-turn history cap and the explicit "continuing" indicator semantics. Tests verify continuity.
2. **+US3** — wires the room state into the system prompt. Tests verify the NPC has access to who else is around.
3. **+US4** — adjusts the system prompt to prefer emote-mode refusals. Tests verify refusal patterns.
4. **+US5** — verifies the empty-lore branch works. Tests verify the fallback paragraph.

After all five user stories, Phase 8 wraps with an end-to-end integration test (mirrors features 005, 007, 008, 009 patterns), formatting/lint passes, documentation, and a manual smoke run from quickstart.md.

### Validation gates

- **After Phase 2**: `mix compile` succeeds; old replay test (T025) passes confirming backward compat; the supervision tree starts cleanly (boot `iex -S mix` and verify `Process.whereis(AgenticRealms.World.NPCChat.Supervisor)` returns a pid).
- **After Phase 3 (US1)**: T047, T048 pass; manual `chat Garrick hello` in `iex` produces the expected flow.
- **After Phase 4 (US2)**: T052, T053 pass; idle-timeout test verified with the 200ms override.
- **After Phase 5 (US3)**: T057, T058 pass; the system prompt for a multi-player room demonstrably contains all the right names.
- **After Phase 6 (US4)**: T060, T061 pass; refusal-pattern audit passes.
- **After Phase 7 (US5)**: T063, T064 pass.
- **After Phase 8**: integration test (T065) passes including the SC-007 zero-leak audit; quickstart smoke passes; `mix format`, compile warnings, full test suite all green.
