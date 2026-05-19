# Implementation Plan: Natural-Language Player Commands (LLM intent parser)

**Branch**: `005-llm-intent-parser` | **Date**: 2026-05-19 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/005-llm-intent-parser/spec.md`

## Summary

Player input that the existing fast `CommandParser` returns as `{:unknown, raw}` is routed to **Claude Haiku 4.5** via the Anthropic Messages API with **tool use** as the action-selection mechanism. Each canonical game action (`take`, `drop`, `move`, `look`, `inventory`, `say`, `emote`, `tell`, `whisper`) is exposed as a tool with a strict input schema; an additional `refuse` tool is the model's only sanctioned way to signal "no action" (FR-007 / FR-007a — used for out-of-scope, near-mapping, multi-step, and ambiguous intent). The model's single tool call is dispatched to the existing handler functions in `GameLive` — handlers do not change; only an upstream router is added.

**Load-bearing design decisions**:

- **No Elixir SDK**: Anthropic doesn't ship an official Elixir SDK and the third-party packages aren't worth the dependency surface. Use direct HTTP via **Req** against `POST /v1/messages` — JSON in, JSON out, ~80 lines of thin client code. Adds one runtime dependency (`req ~> 0.5`).
- **Prompt caching is mandatory**: tool definitions + system prompt are stable across requests (~1500–2000 tokens combined); a `cache_control: {type: "ephemeral"}` marker on the last tool definition cuts input cost ~10× for cache hits. Volatile content (per-request room snapshot + inventory + player input) lives in the user message and is never cached.
- **Async dispatch via `Task.Supervisor.async_nolink`**: the API call takes 300–800ms and MUST NOT block the LiveView process from handling other events (presence updates, multi-session broadcasts). The submit branch spawns a supervised task, immediately renders a transient "thinking…" entry and locks the input, then handles the task's `{ref, result}` message in a new `handle_info/2` clause that appends the resolved action / refusal and unlocks input.
- **Failure modes route to `:system` refusal**: HTTP error, timeout (5s hard cap), malformed response, no tool call, multiple tool calls, or unrecognized tool name all collapse to a single neutral refusal entry — no crash, no leak of LLM internals.
- **Hybrid stays hybrid**: the fast path from 003/004 is unchanged. The only modification to `GameLive.handle_event("submit_command", …)` is the existing `{:unknown, raw}` branch — it no longer immediately renders "I don't understand", it now spawns the resolver task.

**Per-clarification design** (Session 2026-05-19):

- Near-mapping intent (`examine X`, `inspect X`, `study X`) → resolver MUST pick the `refuse` tool with a helpful hint, NOT substitute `look`. This is enforced via (a) tool descriptions that explicitly call out the scope of each tool ("show the current room — not specific objects"), and (b) few-shot examples in the system prompt that demonstrate the correct refusal pattern.
- Refusal text is **resolver-authored per request** (free-form `message: string` field on the `refuse` tool), matching the original feature description's `respond_to_player(message)` framing.

## Technical Context

**Language/Version**: Elixir 1.15+ / Erlang OTP 26+ (unchanged from 003/004)
**Primary Dependencies**:
- **New**: `{:req, "~> 0.5"}` — modern HTTP client (Finch-backed). The only new runtime dep.
- **Existing**: Phoenix 1.8.5, Phoenix LiveView 1.1.0, `phoenix_pubsub`, `jason`, `ecto`. Communication PubSub topics from 004 are unaffected — this feature doesn't broadcast anything.
**External Service**: Anthropic Messages API at `https://api.anthropic.com/v1/messages`. Model: `claude-haiku-4-5-20251001`. API key sourced from `ANTHROPIC_API_KEY` env var; absence → graceful refusal (FR-011). Prompt caching enabled on the system prompt + tool definitions block.
**Storage**: None. Stateless per spec. No new migrations, no Ecto schema, no event store activity.
**Testing**: ExUnit. Three layers — (1) `IntentResolver` unit tests with a mocked HTTP layer (Req.Test), (2) `Anthropic` HTTP client unit tests against a fake server, (3) LiveView integration with mocked `IntentResolver`. A separate `:live_llm`-tagged smoke test exercises a real Anthropic call against a curated input set (NOT run by default — costs tokens; runs on demand with `--include live_llm`).
**Target Platform**: Web browser (desktop, unchanged scope).
**Project Type**: Phoenix LiveView monolith (unchanged).
**Performance Goals**:
- SC-002 — p95 LLM-fallback latency under 1s end-to-end. Haiku 4.5 + prompt caching + ~200 token volatile input typically lands at 300–800ms.
- SC-003 — fast path stays under 50ms p99. No change to the canonical parser code path → no measurable impact.
**Constraints**:
- Synchronous-from-LiveView's-perspective but async via `Task.Supervisor`: the LiveView's `handle_event` returns immediately; the `handle_info` for the task result delivers the action.
- 5-second hard timeout on the Anthropic call. Slow LLM → graceful refusal (FR-013).
- 500-character cap on player input handed to the resolver (FR-017, matches communication-verb cap from 004).
- API key required at runtime; if absent the feature degrades to "I don't understand" refusals (current 003/004 behavior for unknown commands) — no crash.
**Scale/Scope**:
- Same as 003/004 — handful of concurrent players, starter map.
- Cost envelope: at Haiku rates with cache hits, ~$0.0002 per non-canonical command. A player who types exclusively natural language for 100 commands costs ~$0.02. Comfortably bounded.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The project constitution (`.specify/memory/constitution.md`) is the unfilled template — no concrete principles ratified. No gates to enforce. Proceeding (same posture as 003/004).

**Post-Phase 1 re-check**: No violations. This feature reuses existing infrastructure (`GameLive`, `CommandParser`, existing action handlers) and adds two narrow new modules (`World.IntentResolver`, `Anthropic` HTTP client) plus a `Task.Supervisor` child. No changes to the event store, no changes to the `World.Commands` write path, no new migrations.

## Project Structure

### Documentation (this feature)

```text
specs/005-llm-intent-parser/
├── plan.md                  # This file (/speckit-plan output)
├── spec.md                  # Feature specification (clarified)
├── research.md              # Phase 0: technical decisions, prompt-caching strategy,
│                            #          tool schema design, failure-mode mapping
├── data-model.md            # Phase 1: resolver context snapshot shape, tool input schemas,
│                            #          resolver outcome variants
├── quickstart.md            # Phase 1: dev setup (API key), manual walkthrough, observability tips
├── contracts/
│   ├── tools.md             # Phase 1: the tool definitions (names, descriptions, input_schema)
│   │                        #          shipped to the Anthropic API on every request
│   ├── system_prompt.md     # Phase 1: the cached system prompt content + caching strategy
│   │                        #          (what's cached vs. volatile, cache hit telemetry)
│   └── intent_resolver_api.md # Phase 1: World.IntentResolver public function contract
└── checklists/
    └── requirements.md      # (Already created by /speckit-specify)
```

### Source Code (repository root)

```text
lib/
├── agenticrealms/
│   ├── anthropic.ex                            # NEW — thin Req wrapper for Anthropic Messages API
│   │                                              owns: auth header, base URL, timeout, error mapping
│   └── world/
│       ├── intent_resolver.ex                  # NEW — public facade `resolve/2` per spec FR-004..FR-013
│       │                                              builds context snapshot, calls Anthropic via the
│       │                                              client above, parses tool_use response, returns
│       │                                              either an action sentinel or {:error, refusal_msg}
│       └── intent_resolver/
│           ├── tools.ex                        # NEW — tool definition list (canonical action set +
│           │                                              :refuse). Single source of truth, used by
│           │                                              both prompt construction and response parsing.
│           ├── system_prompt.ex                # NEW — module attribute holding the cacheable
│           │                                              system prompt text (game rules, refusal
│           │                                              guidance, few-shot examples). priv-loaded.
│           └── context_snapshot.ex             # NEW — builds the volatile per-request context
│                                                       (RoomView + inventory) into a compact
│                                                       text/JSON form for the user message.
└── agenticrealms_web/
    └── live/
        └── game_live.ex                        # MODIFIED — {:unknown, raw} branch now spawns an
                                                          async resolver task; new handle_info clause
                                                          for the task's {ref, result} reply; transient
                                                          "thinking..." log entry + input lock during
                                                          resolution.

priv/
└── intent_resolver/
    └── system_prompt.md                        # NEW (optional) — system prompt text loaded at
                                                  compile time. Lives in priv/ so it ships with the
                                                  release and is easy to iterate on without code edits.

config/
├── config.exs                                  # MODIFIED — Anthropic base URL + model id + timeout
├── runtime.exs                                 # MODIFIED — ANTHROPIC_API_KEY env var passthrough
└── test.exs                                    # MODIFIED — point Anthropic base URL at a Req.Test stub

test/
├── agenticrealms/
│   ├── anthropic_test.exs                      # NEW — HTTP client unit tests via Req.Test
│   └── world/
│       ├── intent_resolver_test.exs            # NEW — resolver unit tests with mocked Anthropic
│       └── intent_resolver/
│           ├── tools_test.exs                  # NEW — tool definitions structural test (every
│           │                                              canonical action is represented exactly once;
│           │                                              :refuse is present; schemas validate)
│           └── context_snapshot_test.exs       # NEW — context builder unit tests (room + inventory
│                                                       serialization, length bounds)
└── agenticrealms_web/
    └── live/
        └── game_live_intent_parser_test.exs    # NEW — LiveView integration: unknown input routes
                                                          to resolver, "thinking..." appears, resolved
                                                          action dispatches correctly, failure modes
                                                          surface graceful refusals. Tagged :integration
                                                          (consistent with 004's pattern for tests that
                                                          stress the seed/event-store sandbox).
```

**Structure Decision**: All new code lives in two narrow namespaces — `AgenticRealms.Anthropic` (the HTTP client) and `AgenticRealms.World.IntentResolver` (the facade + helpers). The `World.IntentResolver` module is parallel to (and intentionally distinct from) `World.Communication` from 004 and `World.Commands` from 003 — each owns one orthogonal concern:

- `World.Commands` (003) — event-sourced write actions via Commanded
- `World.Communication` (004) — non-event-sourced PubSub broadcasts
- `World.IntentResolver` (005) — natural-language → canonical action mapping

There is no overlap and no shared state between them. The new `Task.Supervisor` is added to the application supervision tree so resolver invocations are properly supervised (and so a hung task doesn't block the LiveView).

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No violations. The new dependencies (`req`) and external service dependency (Anthropic API) are inherent to the feature's purpose; there is no simpler alternative that delivers natural-language intent resolution. The async-task pattern is the standard Phoenix LiveView idiom for "call out to an external service without blocking the LiveView process."
