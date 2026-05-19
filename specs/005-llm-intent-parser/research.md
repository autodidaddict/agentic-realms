# Phase 0 Research — Natural-Language Player Commands

All `[NEEDS CLARIFICATION]` markers in spec.md were resolved during `/speckit-clarify`. This document captures the technical decisions that the plan depends on — specifically around the Claude API integration, prompt caching, tool design, async dispatch, and failure handling.

---

## 1. HTTP client choice — Req

**Decision**: Add `{:req, "~> 0.5"}` as the only new runtime dependency. Use it directly against the Anthropic Messages API endpoint.

**Rationale**: Req is the modern de-facto Elixir HTTP client — built on Finch, supports JSON body encoding/decoding natively, has first-class timeout configuration, and ships a `Req.Test` adapter for unit tests that lets us stub responses without spinning up a fake server. The Anthropic API surface we need is small (one endpoint, one request body shape, one response shape) so anything heavier (e.g., Tesla with middleware) is unjustified.

**Alternatives considered**:

- **Finch direct**: lower-level; we'd be hand-rolling JSON encoding and connection pooling. Req wraps this cleanly.
- **HTTPoison**: legacy; deprecated in favor of Mint/Finch-based stacks.
- **Anthropic SDK (third-party Hex packages like `anthropic`)**: thin wrappers that lag the API and add a dependency we'd have to vendor or patch. Direct HTTP is more maintainable.

---

## 2. Why no Elixir SDK

**Decision**: Talk to Anthropic via raw HTTPS. Build a thin `AgenticRealms.Anthropic` module (~80 lines) that encapsulates the auth header, base URL, model selection, timeout, and error mapping.

**Rationale**: The Anthropic Messages API is a JSON-in / JSON-out HTTPS endpoint. Tool use is just additional JSON in the request and a particular content block shape in the response. There is no streaming requirement for this feature (we wait for the full tool_use response before dispatching). All of this is straightforward in ~80 lines of Req-based code that we own and can iterate on without dependency updates.

Third-party Elixir SDKs add: dependency drift, opaque error mapping, often missing features (prompt caching support varies), and extra surface area for testing.

---

## 3. Model choice — Claude Haiku 4.5

**Decision**: Default model is `claude-haiku-4-5-20251001`. Configurable via `config/runtime.exs` so it can be changed without a code release.

**Rationale**: For a tightly-scoped tool-use task (pick one of 10 tools from short player input, augmented by ~200 tokens of room context), Haiku 4.5 is the right choice on three dimensions:

- **Latency**: Haiku is the fastest current Anthropic model. With prompt caching, sub-second p95 is comfortably achievable.
- **Cost**: Haiku's per-token rate is the lowest in the Claude 4 family. With caching applied to the bulk of the input (system prompt + tools), per-invocation cost is fractions of a cent.
- **Capability**: Tool-call accuracy for a small fixed tool set is well within Haiku's ability — this is not a reasoning-heavy task. If we encountered systematic misclassification we could escalate to Sonnet 4.6, but starting at Haiku is the right default.

**Alternatives considered**:

- **Sonnet 4.6 / Opus 4.7**: better at long-context reasoning, but more cost + latency. Overkill for this task.
- **Older Claude (3.x)**: slower and more expensive than Haiku 4.5 for similar capability. No reason to use.

---

## 4. Prompt caching strategy

**Decision**: Mark the **system block** with `cache_control: {type: "ephemeral"}`. (Implementation correction: render order is `tools → system → messages`, so a marker on the *system* block caches both the tools array and the system prompt — a marker on the last *tool* would cache only the tools. The original draft of this doc said "last tool definition"; the code places it on the system block.) Everything from the start of the request up to and including that marker is cached; the user message (volatile per request) is not.

**Cached content** (~2000–2500 tokens combined):

1. System prompt block: game rules, refusal guidance, few-shot examples of correct and incorrect mappings.
2. Tool definitions array: all 10 tools (9 canonical actions + `refuse`) with their input_schema and descriptions.

**Volatile content** (~150–250 tokens; never cached):

1. User message body: a compact JSON-like or markdown rendering of the current `RoomView` + player's inventory + the raw player input string.

**Cache TTL**: 5-minute ephemeral. Cache hit rate will be high during active play (system prompt is identical across requests and rooms; tool defs don't change). When the cache expires we pay the full input cost once and re-cache.

**Rationale**: For a small player base (~5 concurrent in dev), cache hits across requests are the norm. With ~2000 cached tokens, a cache hit reduces the input charge by ~10× (current Anthropic pricing — cached input reads are billed at a small fraction of new input). That's the difference between $0.002/call and $0.0002/call at Haiku rates.

**Caveat — minimum cacheable size (implementation correction)**: Claude Haiku 4.5's minimum cacheable prefix is **4096 tokens**, not ~1024 as this doc originally assumed. The system prompt + tools total ~2000–2500 tokens — **below the 4096 threshold**, so prompt caching does NOT engage at the current prompt size. This produces no error (the request is simply not cached); the `cache_control` marker is kept so caching activates automatically if the prompt later grows past 4096 tokens. The accepted tradeoff: uncached per-request cost is ~$0.003 at Haiku rates — negligible for the project's player base. Padding the prompt purely to clear the cache threshold was rejected as artificial. See the `Tools` module doc for the same note in code.

---

## 5. Tool design

**Decision**: 10 tools — one per canonical action plus `refuse`. Each tool's `input_schema` is the minimum it needs.

| Tool       | Input schema (JSON Schema sketch) | Notes |
|------------|-----------------------------------|-------|
| `take`     | `{object: string}`                | Object name passed through to `Communication`/`Commands` for case-insensitive room resolution. |
| `drop`     | `{object: string}`                | Same — inventory resolution downstream. |
| `move`     | `{direction: enum["north","south","east","west","up","down"]}` | Enum to prevent the LLM from inventing directions. |
| `look`     | `{}` (no args)                    | Renders current room. NOT for examining specific objects (FR-007a). |
| `inventory`| `{}` (no args)                    | |
| `say`      | `{text: string}`                  | Room-scoped broadcast. |
| `emote`    | `{text: string}`                  | Room-scoped narration. |
| `tell`     | `{recipient: string, text: string}` | Cross-room private. |
| `whisper`  | `{recipient: string, text: string}` | Same-room private. |
| `refuse`   | `{message: string}`               | The LLM's only sanctioned non-action output. `message` is the player-facing refusal text, authored per request. |

**Tool description guidance**: each tool's `description` field calls out (a) what the tool does, (b) when to use it, (c) when NOT to use it. The `look` description explicitly states "Use this when the player wants to see the current room as a whole. Do NOT use this when the player wants to examine a specific object — there is no examine tool yet; use `refuse` with a hint instead." This is the prompt-engineering enforcement of FR-007a.

**Rationale**: One-to-one mapping with canonical actions means there is zero translation needed between the LLM's tool call and the existing handler functions. The `refuse` tool gives the LLM a structured, sanctioned escape hatch — without it the model might emit malformed responses or hallucinate actions when stumped.

---

## 6. System prompt content

**Decision**: Author the system prompt as a markdown file under `priv/intent_resolver/system_prompt.md`, loaded at compile time via `@external_resource` + `File.read!/1`. The structure is fixed at deploy time; iteration is via redeploys.

**Section breakdown**:

1. **Role**: "You are the intent parser for Agentic Realms, a text-adventure MUD. Your job is to read raw player input and pick exactly one tool call from the available actions."
2. **Rules**:
   - "Pick exactly one tool per request. Never call multiple tools — multi-step intent must be refused."
   - "Refuse via the `refuse` tool when the player's intent doesn't map cleanly to a supported action."
   - "Do NOT substitute a near-mapping action. If the player asks to `examine` an object but no `examine` action exists, refuse — do not call `look` as a substitute. The `look` tool shows the current room as a whole."
   - "All `text` arguments pass through to game logic verbatim — preserve the player's casing and intent."
3. **Few-shot examples** (5–8):
   - Correct mappings: `grab the lantern off the table` → `take(object: "brass lantern")` (when present in room context)
   - Correct refusals: `examine the lantern` → `refuse(message: "...")`, `take the lantern and head north` → `refuse(message: "one action at a time")`
   - Edge cases: ambiguous references, missing recipient names, multi-step intent
4. **Context contract**: explains that each user message contains the current room state, the player's inventory, and the player's literal input — the model uses these to resolve references like "the lantern" against actual room contents.

**Rationale**: Few-shot examples are load-bearing for tool-call accuracy with small models. A handful of carefully-chosen examples gets us most of the way to SC-001 (95% correct mapping). The example count is chosen for accuracy, not to hit any cache threshold (see §4 — the cache does not engage at the current prompt size and padding for it was rejected).

---

## 7. Volatile user message structure

**Decision**: The user message is a single text block formatted as compact markdown:

```text
Current room: Stone Atrium
Description: A wide, pillared hall of mossy granite. (truncated to ~200 chars)
Exits: north (Forest Path), east (Corridor)
Objects here: brass lantern, leather-bound journal
Other players present: bob_44, carol_44
Your inventory: (empty)

Player typed: grab the lantern off the table
```

**Rationale**: Markdown is denser than JSON for human-style content (room descriptions read naturally) and Haiku parses it without trouble. The `Player typed:` line is the literal input passed verbatim — preserving its casing per FR-014's "player sees their original input echoed" rule.

**Field rules**:

- Room description truncated to a sensible bound (~300 chars) to keep token usage predictable.
- Object list contains names only; the resolver doesn't need short descriptions for action selection.
- Inventory list is name-only.
- "Other players present" pulled from `Queries.other_occupants_of/2` (now correctly online-filtered per 003b).

---

## 8. Async dispatch — `Task.Supervisor.async_nolink`

**Decision**: Add a `Task.Supervisor` (named `AgenticRealms.IntentResolverTaskSupervisor`) to the application supervision tree. When `GameLive` receives an `{:unknown, raw}` parser result, it:

1. Appends a transient `:cmd` log entry echoing the player's literal input (matches the existing pattern from 003/004 handlers).
2. Appends a transient `:thinking` log entry that renders as a subtle "…" affordance.
3. Locks the command input (`assign(:input_locked, true)` flag in socket assigns).
4. Spawns `Task.Supervisor.async_nolink(supervisor, IntentResolver, :resolve, [player_id, raw])`.
5. Stores the `task_ref` in socket assigns so `handle_info({ref, result}, socket)` can match it.
6. Returns `{:noreply, socket}` — LiveView is immediately responsive again.

When the task completes, the LiveView receives `{ref, {:ok, action_tuple}}` or `{ref, {:error, refusal_msg}}` and:

1. Removes the `:thinking` log entry.
2. Dispatches the action tuple to the existing handler (`handle_take`, `handle_move`, etc.) OR appends a `:system` refusal entry.
3. Unlocks the command input.
4. Demonitors the task ref.

**Why `async_nolink`**: a misbehaving Anthropic call (or our own bug) should NOT crash the LiveView. `async_nolink` is the standard Phoenix idiom for "call an external service, handle the result async, survive failures."

**Why a `Task.Supervisor` instead of bare `Task.async`**: bare tasks are linked to the caller and provide weaker supervision guarantees. The supervisor gives us a single audit point for active resolver invocations and ensures clean shutdown.

**Hung-task handling**: the resolver enforces a 5s timeout internally (via Req's `:receive_timeout` option). If the task hangs beyond that, the resolver returns `{:error, "I'm not sure what you meant just now."}` and the LiveView handles it like any other refusal.

**Concurrent submissions**: while a resolver task is in flight for a player, the input is locked — no second submission can race. If the player submits a canonical command while waiting, the input is disabled until the LLM result lands. (Alternative: drop input-lock and queue submissions. Reject for v1; lock is simpler and the wait is short enough to not be annoying.)

---

## 9. Failure-mode catalog

All of the following collapse to a single graceful refusal (`{:error, "I'm not sure what you meant just now."}` or a category-appropriate variant). No exceptions propagate; no crashes.

| Failure mode | Detection | Refusal copy |
|--------------|-----------|--------------|
| HTTP timeout (5s) | Req returns `{:error, %Mint.TransportError{reason: :timeout}}` or similar | "I'm not sure what you meant just now." |
| HTTP non-200 | Req response status not in 200..299 | Same |
| Malformed JSON in response body | `Jason.decode/1` raises or returns error | Same |
| Response has no `tool_use` content block | We expect `content` to contain at least one `tool_use` block | Same |
| Response has multiple `tool_use` blocks | Multi-tool calls are out of scope (multi-step) | "Try one action at a time." |
| Tool name not in expected set | Unrecognized tool means model violated the contract | Same as default |
| Tool input fails schema validation | E.g., `move` tool with a non-enum direction | Same |
| `refuse` tool called | Expected — LLM declined | `message` field is the player-facing copy (model-authored per request) |
| API key missing (`ANTHROPIC_API_KEY` unset) | Module-load check + per-request check | "I don't understand that." (mirrors existing pre-005 behavior) |

**Rationale**: A single uniform refusal path simplifies the LiveView's `handle_info` and the test surface. The differences between failure categories are observability-only (logged for diagnostics) — players see one of two messages.

---

## 10. Configuration

**Decision**: Three configurable values, all in `config/runtime.exs` so they read from environment at boot:

```elixir
config :agenticrealms, AgenticRealms.Anthropic,
  api_key: System.get_env("ANTHROPIC_API_KEY"),
  base_url: System.get_env("ANTHROPIC_BASE_URL") || "https://api.anthropic.com",
  model: System.get_env("ANTHROPIC_MODEL") || "claude-haiku-4-5-20251001",
  timeout_ms: String.to_integer(System.get_env("ANTHROPIC_TIMEOUT_MS") || "5000")
```

Compile-time defaults live in `config/config.exs`. Test overrides in `config/test.exs` point `base_url` at a Req.Test stub.

**Rationale**: Standard Elixir runtime config pattern. Env-var-driven so deployment doesn't require code changes to swap models or override the endpoint (useful for mock servers in CI).

---

## 11. Observability

**Decision**: Each resolver invocation emits a structured `Logger` entry at info level:

```elixir
Logger.info("intent_resolver", %{
  player_id: pid,
  input_length: byte_size(raw),
  outcome: :action_chosen | :refused | :error,
  tool_name: "take" | "refuse" | nil,
  latency_ms: 412,
  cache_hit: true | false  # parsed from response usage block if present
})
```

The cache-hit signal comes from Anthropic's response `usage` field (`cache_read_input_tokens` > 0 ⇒ hit). Aggregating this in production tells us whether the caching strategy is working.

**Telemetry**: emit a `:telemetry.execute([:agenticrealms, :intent_resolver, :resolve], measurements, metadata)` event with the same fields. Future dashboarding hooks into this.

**Rationale**: Without observability we can't tell whether the feature is working in production. The cache-hit signal in particular is load-bearing — if cache hits are rare, our cost projections are wrong.

---

## 12. Testing strategy

**Decision**: Three test layers + one tagged "live" smoke test.

| Layer | File | Coverage |
|-------|------|----------|
| Anthropic HTTP client | `test/agenticrealms/anthropic_test.exs` | Req.Test stubs for success, timeout, 4xx, 5xx, malformed body. Auth header attached. Model param plumbed. |
| Resolver unit | `test/agenticrealms/world/intent_resolver_test.exs` | Pass canned Anthropic responses (via the same Req.Test stub) for every tool name + the refuse tool + every failure mode listed in §9. Assert correct `{:ok, action_tuple}` or `{:error, refusal_msg}` return. |
| Context snapshot unit | `test/agenticrealms/world/intent_resolver/context_snapshot_test.exs` | Builds the user message from a fixture room + inventory. Verifies field rules (description truncation, occupant filter, etc.). |
| LiveView integration | `test/agenticrealms_web/live/game_live_intent_parser_test.exs` | Mocks the resolver; verifies unknown input triggers the async task path, the thinking entry appears, the resolved action is dispatched correctly. Tagged `:integration` (consistent with 004 pattern). |
| Live smoke test | `test/agenticrealms/world/intent_resolver_live_test.exs` | Real Anthropic call with a real API key against a curated input set covering all 9 verbs + the near-mapping refusal. Tagged `:live_llm` and excluded by default. Run with `mix test --include live_llm` after setting `ANTHROPIC_API_KEY`. |

**Mocking technique**: `Req.Test.stub/2` lets us register a per-test stub that intercepts requests by name. Resolver tests inject a stub-name into the Anthropic module via test-only config; production uses the live base URL.

---

## 13. Open items deferred to implementation

- **Exact few-shot example content**: drafted during implementation by iterating against the curated test set. Spec defines the categories of examples needed; specific wording is implementation detail.
- **System prompt token budget tuning**: we'll measure actual cache hit cost during the live smoke test and adjust the prompt's verbosity if needed.
- **`/who` or other action additions**: each new canonical action requires a new tool definition. The cost of adding one is small (a new entry in `World.IntentResolver.Tools` plus a corresponding `GameLive` dispatch branch — both already exist for existing verbs). Out of scope for 005 itself.

No remaining `[NEEDS CLARIFICATION]` items. Ready for Phase 1.
