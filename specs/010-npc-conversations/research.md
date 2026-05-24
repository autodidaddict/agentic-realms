# Research: NPC Conversations (Feature 010)

This document resolves the open technical questions raised by the spec and the planning input. Decisions are made with rationale and rejected alternatives recorded.

## R-001: Cluster-friendly Conversation discovery — Horde, `:global`, or PubSub routing?

**Context**: Per the planning input, `(player_id, npc_clone_id)` lookups must work across multiple BEAM nodes. Three viable options:

- `Horde.Registry` + `Horde.DynamicSupervisor` (CRDT-backed distributed registry/supervisor)
- `:global` + `DynamicSupervisor` (BEAM built-in)
- PubSub-based routing (no registry; messages routed by key over Phoenix.PubSub)

**Decision**: Use **Horde**.

**Rationale**:
- It is the canonical Elixir community pattern for "per-key dynamic processes that must be discoverable cluster-wide." Battle-tested by many production Phoenix apps with similar live-session requirements.
- Lookups are CRDT-backed and O(1) local — no cluster-wide locks per register/lookup, unlike `:global`. This matters when chats churn frequently (start, idle out, restart). At 60s idle timeout and modest player counts we won't hit `:global`'s ceiling immediately, but the pattern's headroom is meaningfully better.
- Survives node leaves: when a node holding a Conversation drops, the Horde supervisor either reaps the orphan (acceptable since chats are ephemeral) or hands off to another node via process-state CRDT (we'll choose reap; chat state is volatile anyway, so handoff isn't worth the implementation cost).
- Failures degrade gracefully: a missing registry entry just means "start a new Conversation" — the new-vs-continuing indicator naturally returns "new" after such an event, which is the correct UX.
- The `via` tuple form (`{:via, Horde.Registry, {NPCChat.Registry, {player_id, npc_clone_id}}}`) is API-compatible with `GenServer.call/3` and `start_link/1`, so the application code is mostly Horde-agnostic.

**Alternatives considered**:
- **`:global`** — works, no new dep, but each register takes a global name lock that's O(N) in node count. For modest scale this is fine, but the pattern is known to degrade in larger clusters. Also, `:global` doesn't supervise — we'd still need a DynamicSupervisor per node and a manual "is the pid on a remote node" check.
- **PubSub routing** — would require encoding chat operations as messages with `{player_id, npc_clone_id}` keys and broadcasting cluster-wide; the holding node responds. Avoids the registry entirely. Rejected because (a) Phoenix.PubSub isn't designed for request/response semantics; (b) we'd reinvent name resolution; (c) the GenServer abstraction is far cleaner — the planning input explicitly chose GenServer for the state holder.
- **A pinned-to-LiveView-node model** — keep each Conversation local to the LiveView's node, accept that reconnects to a different node start fresh. Simpler but violates the planning input's "must work across nodes" requirement (a reconnect that lands on a new node mid-chat would silently start a new conversation, breaking the continuation guarantee for users on multi-node clusters).

**Implementation notes**:
- Add `{:horde, "~> 0.9"}` to `mix.exs` deps.
- Start `Horde.Registry` (name: `AgenticRealms.World.NPCChat.Registry`, keys: `:unique`, members: `:auto`) and `Horde.DynamicSupervisor` (name: `AgenticRealms.World.NPCChat.Supervisor`, strategy: `:one_for_one`, members: `:auto`, distribution_strategy: `Horde.UniformDistribution`) as siblings of the existing children in `AgenticRealms.Application`.
- `:auto` member discovery uses `:net_kernel.monitor_nodes/1` under the hood — fine on top of DNSCluster.
- Wrap registration in a small helper module (`NPCChat.Registry`) to centralize the `via` tuple shape.

---

## R-002: GenServer idle-timeout mechanism — `:timeout` return, `:hibernate`, or explicit `:timer.send_after`?

**Context**: Conversations expire after 60s of inactivity (FR-005, FR-006). The planning input notes that GenServers have "built-in capability for dealing with idle timeouts."

**Decision**: Use the GenServer **`{:noreply, state, @idle_timeout}`** return shape. After `@idle_timeout` ms with no message, the runtime delivers a `:timeout` message to `handle_info/2`, where we terminate the process normally.

**Rationale**:
- This is the literal "built-in" idle-timeout mechanism the user invoked. No external timer to manage, no race condition between message arrival and timer fire (the timer is reset on EVERY message by virtue of being re-armed in each `handle_*` return).
- Termination via `{:stop, :normal, state}` causes Horde.DynamicSupervisor to clean up the registry entry; the next lookup naturally returns `:undefined` and we start fresh.
- `:hibernate` would save memory at the cost of GC pauses on the next message — overkill for a chat with at most 20 turns of state. Skip.
- `Process.send_after/3` with a manual timer ref would force us to track and cancel the ref on every incoming message; more code, more risk of leaks.

**Implementation notes**:
- Every `handle_call/3` / `handle_cast/2` / `handle_info/2` that doesn't already stop the process MUST return `{..., state, @idle_timeout}`.
- `@idle_timeout` is read from `Application.get_env(:agenticrealms, AgenticRealms.World.NPCChat, [])` with a default of `60_000`. Test config overrides to `200` so idle-timeout tests run fast.
- On `:timeout`: emit a debug log (`Logger.debug`) and `{:stop, :normal, state}`. No additional cleanup needed — Horde reaps the registry entry on process termination.

---

## R-003: Structured reply format — Anthropic tool-use, JSON output, or markup convention?

**Context**: FR-021 requires each reply to be exactly one of `speech` or `emote`. Three approaches:

- **Tool-use** with two tools (`say`, `emote`), `tool_choice: {type: "any"}` — same idiom as feature 005's `IntentResolver`.
- **JSON output mode** (where supported) — model returns `{type: "speech" | "emote", text: "..."}`.
- **Markup convention** — model returns text with leading tag `[SPEECH] ...` or `[EMOTE] ...`; parsed at runtime.

**Decision**: Use **tool-use** with two tools.

**Rationale**:
- The Anthropic Messages API tool-use path produces structured output with strong guarantees: the model MUST emit a tool call, the tool call MUST conform to the declared schema. Malformed output is the API's problem, not ours; we just check "did we get exactly one tool_use block, is the name `say` or `emote`."
- We have an existing pattern in feature 005 (`IntentResolver`) using `tool_choice: {type: "any"}` to force a tool call. Reusing it keeps the codebase coherent.
- Markup conventions are notoriously fragile — the model occasionally forgets the tag, double-tags, or wraps it in markdown. Tool-use eliminates that whole class of bug.
- The two tools are trivially small (one `text` field each), so they add ~50 tokens of overhead per call — well within budget.

**Alternatives considered**:
- **JSON output mode** — Anthropic offers `response_format: {type: "json_object"}` on some models, but tool-use is more reliable and our existing code path already uses it.
- **Markup convention** — rejected for fragility, as above.

**Implementation notes**:
- `NPCChat.Tools.list/0` returns the two tool definitions.
- `NPCChat.Reply.parse/1` scans the response `content` array; exactly one `tool_use` whose `name` is `say` or `emote` and whose `input.text` is a non-empty string → `{:speech, text}` or `{:emote, text}`; anything else → `{:error, :malformed}` and triggers the FR-011 fallback.

---

## R-004: Where does the chat enter the command pipeline — `CommandParser` fast path, `IntentResolver` only, or both?

**Context**: Feature 005 introduced a two-tier command pipeline: a fast `CommandParser` for exact matches, falling through to the LLM-backed `IntentResolver` for natural-language phrasing. `chat` could live in either tier.

**Decision**: Both — `CommandParser` handles the literal `chat <npc> <message>` form fast (no LLM round-trip for the parse); `IntentResolver` ALSO learns about chat so that "ask Garrick about the keys" routes here too.

**Rationale**:
- Fast-path coverage matters: most users will discover the `chat` verb from documentation/help text and type it literally. Sending those calls through the LLM parser would double the cost and latency for no gain.
- Natural-language phrasing ("ask the innkeeper about the rumors", "talk to Garrick", "tell the guard hello") should also resolve to chat. The IntentResolver already owns this surface; adding a `chat` tool there extends it cleanly.
- Splitting the work matches what every other verb in the project does (`say`, `look`, `take` all have both a CommandParser fast path and an IntentResolver tool).

**Implementation notes**:
- `CommandParser` gains a clause that recognizes `"chat " <> rest`, splits `rest` into NPC name + message via the first space-after-known-NPC heuristic (or the simpler approach: the first space-separated chunk is the NPC token, the rest is the message — same as `tell <player> <message>`).
- `IntentResolver.Tools` gains a `chat` tool: `{"player_target": "<npc name>", "message": "<player's text>"}`. The IntentResolver module's `:resolve` outcome adds `{:chat, npc_token, message}` to its action-tuple union.
- `GameLive` handles `{:chat, npc_token, message}` by calling `AgenticRealms.World.NPCChat.send/3`.

---

## R-005: Per-call LLM execution — synchronous from the LiveView, async from the Conversation, or async from the LiveView?

**Context**: The LLM call takes 1–3s. The LiveView must remain responsive. We need to decide where the async boundary sits.

**Decision**: Async **from the Conversation GenServer**. The LiveView calls `NPCChat.send/3` synchronously and gets back an immediate `{:ok, :new | :continuing}` indicator (so the "started new conversation" / "continuing" log entry can render before the reply arrives). The Conversation GenServer then spawns a Task under `NPCChat.TaskSupervisor` for the LLM call; the Task sends its result back to the GenServer via `Process.send/2`; the GenServer broadcasts the rendered reply on `player_topic(player_id)` for the LiveView to pick up via its existing `handle_info`.

**Rationale**:
- Two-stage feedback matches the spec UX exactly: FR-003 says the new-vs-continuing indicator MUST render BEFORE the reply. Synchronous indicator + async reply gives the player immediate confirmation that the command was accepted.
- The Conversation GenServer is the natural owner of the in-flight lockout (FR-020). It can set a `pending?: true` flag the moment it dispatches the Task, and clear it when the Task result arrives. Any second `:send` while `pending?` is true is rejected synchronously.
- Spawning the Task from inside the GenServer (under a separate Task.Supervisor, not the GenServer's own supervision) lets the GenServer continue handling messages (like the idle-timeout fire) while the LLM call is in flight.
- The LiveView never blocks on the LLM — the existing `handle_info(%ChatUtterance{}, ...)` path delivers the reply asynchronously over PubSub.

**Implementation notes**:
- `NPCChat.send/3` resolves the Conversation pid via `Horde.Registry.lookup/2`. If `[]`, it starts one via `Horde.DynamicSupervisor.start_child/2`. Then `GenServer.call(pid, {:send, player_id, message}, 5_000)`.
- The `:send` call (a) marks `pending?: true`, (b) computes "new" or "continuing" from `last_activity_at`, (c) updates `last_activity_at` and the history (player utterance only — NPC reply added later when it lands), (d) starts a Task under `NPCChat.TaskSupervisor` that calls `Anthropic.create_message` and on completion sends `{:llm_result, result}` back to the GenServer pid, (e) replies to caller with `{:ok, :new | :continuing}`.
- Task module uses `Task.Supervisor.start_child(NPCChat.TaskSupervisor, fn -> ... end)` — fire-and-forget; the Task is unlinked from the LiveView so a LiveView disconnect doesn't kill the LLM call mid-flight.
- The GenServer's `handle_info({:llm_result, result}, state)` clause parses the reply, appends the NPC turn to history, broadcasts `ChatUtterance` on `player_topic`, clears `pending?`, returns `{:noreply, new_state, @idle_timeout}`.

---

## R-006: Lore field — events extension, full-copy semantics, atom-table gotcha

**Context**: Feature 008 established that NPC clones get a full copy of blueprint fields at spawn time. Feature 009 added `behaviors` to both blueprint and clone events. The same pattern applies to `lore`.

**Decision**: Add `lore` to `NPCBlueprint` and `NPCClone` schemas; pipe it through `CreateNPCBlueprint` command and `NPCBlueprintCreated` event; copy it into `NPCClonedFromBlueprint`. Migration adds `lore TEXT NOT NULL DEFAULT ''`.

**Rationale**:
- This is the same plumbing pattern as feature 009's `behaviors`, so the project's wizard / replay / projection invariants are already validated for this shape.
- Default `''` (empty string, NOT null) lets FR-013 (the no-lore graceful-degradation path) handle the empty case uniformly without null-check noise.

**Atom-table gotcha**: Feature 009 discovered that the EventStore's JsonSerializer atomizes ALL keys in event payloads via `Jason.decode!(..., keys: :atoms!)`, crashing at startup when an atom-keyed map contains a string that's not yet in the atom table. `lore` is a top-level scalar (string), so the field name `:lore` becomes an atom via the schema/struct definition at compile time — no nested-map atomization happens. **No pre-declaration needed**. (For symmetry, if we later add nested structures inside `lore` we'll need to revisit.)

**Implementation notes**:
- One migration: `add_lore_columns.exs` — `add :lore, :text, null: false, default: ""` on both `npc_blueprints` and `npc_clones`.
- Three event/command struct extensions: `CreateNPCBlueprint`, `NPCBlueprintCreated`, `NPCClonedFromBlueprint` each get `lore: ""` in their defstruct (NOT in `@enforce_keys` — backward-compatible).
- Two schema extensions: `field :lore, :string, default: ""` in `NPCBlueprint` and `NPCClone`.
- Aggregate logic in `npc_blueprint.ex`: blueprint creation carries `lore` from the command; clone creation copies `lore` from the blueprint aggregate's stored field (alongside `behaviors`, `short_description`, etc.).
- Projector handlers in `world_projector.ex`: include `:lore` in the `Repo.insert!/2` keyword list for both blueprint and clone projections.
- Seed: extend Garrick's blueprint with a short lore paragraph (illustrative; e.g., "Garrick is a soft-spoken former bridge-guard who came south after the Riverford collapse twelve years ago...").

---

## R-007: Privacy delivery surface — new PubSub topic, reuse `player_topic`, or direct LiveView message?

**Context**: Chat replies must reach the chatting player only (FR-017). Three options:

- Reuse the existing `World.player_topic(player_id)` (used for feature 009's `BehaviorUtterance` private delivery)
- A new dedicated `World.chat_topic(player_id, npc_clone_id)` per conversation
- Direct `Process.send/2` from the Conversation GenServer to the LiveView pid

**Decision**: Reuse **`World.player_topic(player_id)`** with a new UI event struct `ChatUtterance` distinguished by `kind: :chat_speech | :chat_emote | :chat_system`.

**Rationale**:
- The LiveView already subscribes to `player_topic(player_id)` on connected mount. No new subscription wiring.
- Privacy is preserved because `player_topic` is keyed by `player_id` only — no other player subscribes to another player's topic (by construction).
- Adding more topics multiplies the cluster's PubSub bookkeeping for no benefit. One topic per player is the right granularity.
- Direct `Process.send/2` is rejected because (a) the LiveView pid changes on reconnect — the Conversation would need to track it; (b) PubSub is already cluster-aware, so it routes across nodes for free.

**Implementation notes**:
- `AgenticRealms.World.UIEvents.ChatUtterance` struct: `kind: :chat_speech | :chat_emote`, `npc_clone_id: String.t`, `npc_name: String.t`, `text: String.t`, `triggering_player_id: integer()` (= the chatting player).
- `AgenticRealms.World.UIEvents.ChatSystemMessage` struct: `kind: :chat_new | :chat_continuing | :chat_in_flight_rejection | :chat_fallback`, `npc_name: String.t`, `text: String.t`, `player_id: integer()`. (Alternative: unify into one struct with a kind atom. Keep separate for type clarity.)
- The LiveView handles each in `handle_info/2`, appends a log entry, and renders via new `log_entry` clauses in `game_components.ex`.

---

## R-008: Reply token cap, prompt-budget enforcement, and history trim policy

**Context**: FR-019 imposes three caps: per-utterance input length, per-reply token budget, total context budget. Need to operationalize.

**Decisions**:
- **Per-utterance input length**: 500 characters (matches feature 009's `say` cap and feature 005's intent input cap). Enforced in `NPCChat.send/3` BEFORE dispatching to the Conversation; rejection returns `{:error, :too_long}` so GameLive renders a usage hint.
- **Per-reply token budget**: 256 tokens, passed as `max_tokens` to the Anthropic API. Mirrors `IntentResolver`'s setting.
- **Total context budget**: Use Anthropic Haiku 4.5's 200k-token context window. We won't actually hit it — the worst-case prompt (full 20-turn history × 500 chars/turn ≈ 20k chars ≈ 5k tokens, plus lore ≤ 4k chars, plus room/tool schema ≈ 2k chars) is well under 12k tokens. The "evict oldest turns" code path is included for completeness but should rarely fire.
- **History trim**: Soft cap (FR-004) at 20 turns; on `:llm_result`, before appending the new turn, if the post-append size would exceed 20, drop the oldest pair (player+NPC) until we're at 20. The hard token-budget guard is a sanity check that drops further if needed.

**Rationale**:
- Concrete numbers are needed to make the implementation testable. 500/256 mirror existing project constants. The 20-turn cap was decided in /speckit.clarify Q1.
- Token budget enforcement is a defense-in-depth measure; the practical bound is the 20-turn cap. Defensive code only.

**Implementation notes**:
- `NPCChat.send/3` is the gate for input-length validation.
- `Conversation` maintains state.turns as a list; `Enum.take/2` from the tail to enforce the 20-turn cap after appending.
- The Task that calls Anthropic builds the messages array from state.turns + the current player utterance.

---

## R-009: Testing strategy — stubbed LLM, real GenServer, real Horde?

**Context**: Tests must verify (a) GenServer behavior (lockout, idle timeout, history trim), (b) cluster discovery semantics (single-node simulation is OK; full cluster CI is overkill), (c) the LLM round-trip (stubbed via `Req.Test`).

**Decision**:
- Unit tests for `Conversation`, `Tools`, `Reply`, `Context`, `SystemPrompt` use no LLM and no Horde — they exercise pure functions or a directly-spawned GenServer with `start_link` skipping the registry.
- Tests for `NPCChat` public API exercise Horde.Registry / Horde.DynamicSupervisor on a single node — they assert "given a key, lookup returns the same pid each time within idle window; after timeout, lookup returns `:undefined`".
- The LiveView integration test stubs `AgenticRealms.Anthropic` via `Req.Test` (same plug-injection pattern as feature 005). The plug returns canned `tool_use` responses.
- Idle-timeout tests set `:idle_timeout_ms` to ~200ms via test config and assert via `Process.alive?/1` and a brief `Process.sleep`.

**Rationale**:
- Stubbing keeps tests deterministic and fast (no network, no LLM cost).
- Single-node Horde is sufficient to validate the registry/supervisor wiring; multi-node testing is a CI consideration for a later feature.

**Implementation notes**:
- `test/support/` already has fixtures and test helpers from prior features; reuse.
- `Req.Test.set_req_test_to_shared/1` already used in feature 005 + 009 integration tests; reuse.
- Per-feature test idle-timeout override goes in `config/test.exs`.

---

## R-010: Backwards compatibility & merge ordering

**Context**: Feature 009 (behaviors) was merged just before this feature began. The lore field plumbing follows the exact same shape as the behaviors plumbing; merging this on top of 009 is straightforward (no overlapping event-payload key conflicts).

**Decision**: No special compatibility work. The migration adds a column with `NULL`-safe default. The event payloads gain a backward-compatible field (not in `@enforce_keys`).

**Rationale**:
- Same approach as feature 009's compatibility decisions, validated by replay tests already in the repo.
- Old events deserialize cleanly because the field has a default in the defstruct.

**Implementation notes**:
- Add a projection replay test (mirroring feature 009's `world_projector_npc_replay_test.exs`) to verify that an old `NPCBlueprintCreated` event (without `lore`) is projected with `lore = ""`.
