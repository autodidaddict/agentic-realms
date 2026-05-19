# Phase 1 Data Model — Natural-Language Player Commands

This feature is **stateless** (per spec Assumptions). There are no Ecto schemas, no migrations, no DB tables, no event-store streams. Every datum lives for one request-response cycle and is then discarded.

The "data" here is a set of in-memory struct/map shapes that flow from player input → context builder → Anthropic API → response parser → action dispatcher. This document specifies those shapes.

---

## Entity 1 — Resolver Request

The package handed to `World.IntentResolver.resolve/2`.

```elixir
@type resolve_request :: %{
        required(:player_id) => integer(),
        required(:raw_input) => String.t()
      }
```

| Field | Type | Source | Notes |
|-------|------|--------|-------|
| `player_id` | `integer()` | `GameLive` socket assigns | Used to look up the player's room + inventory via existing queries. |
| `raw_input` | `String.t()` | the unknown-command branch of `CommandParser.parse/1` | Player's literal input, already trimmed by the parser. Length-checked against the 500-char cap (FR-017) before being passed in. |

There is intentionally no `session_id` here — the resolver doesn't need the per-LiveView session token (the resulting action sentinel is dispatched in `GameLive` where `session_id` is already available).

---

## Entity 2 — Resolver Context Snapshot

The volatile per-request context the resolver builds and sends to the LLM as the user message. Sourced from existing read-side queries.

```elixir
@type context_snapshot :: %{
        required(:room) => %{
          required(:name) => String.t(),
          required(:description) => String.t(),     # truncated to ~300 chars
          required(:exits) => [%{direction: atom(), target_name: String.t()}],
          required(:objects) => [%{name: String.t()}],
          required(:other_players) => [%{username: String.t()}]
        },
        required(:inventory) => [%{name: String.t()}],
        required(:raw_input) => String.t()
      }
```

**Field rules**:

| Field | Source | Rule |
|-------|--------|------|
| `room.name` | `Queries.look_room/1` → `RoomView.name` | Verbatim. |
| `room.description` | `Queries.look_room/1` → `RoomView.description` | Truncated to ≤300 characters (append `…` if cut). Keeps token budget predictable. |
| `room.exits` | `Queries.look_room/1` → `RoomView.exits` | Direction is one of the 6-element canonical set (`:north`/`:south`/`:east`/`:west`/`:up`/`:down`); target_name verbatim. |
| `room.objects` | `Queries.look_room/1` → `RoomView.objects` | Names only — the resolver doesn't need short descriptions for action selection. Order: same as the room view (alphabetical by name). |
| `room.other_players` | `Queries.look_room/1` → `RoomView.other_players` | Already online-filtered (per 003b). Usernames only. |
| `inventory` | `Queries.list_inventory/1` | Names only. |
| `raw_input` | The `Resolver Request.raw_input` | Verbatim — case preserved. |

If `Queries.look_room/1` returns `{:error, _}` (no current room — shouldn't happen mid-session since `GameLive.mount/3` spawns the player), the resolver returns `{:error, refusal}` without invoking the LLM.

---

## Entity 3 — Anthropic Request Body

The JSON body sent to `POST /v1/messages`. This is the wire shape per the Anthropic API contract — not a struct, just a map serialized by Jason.

```json
{
  "model": "claude-haiku-4-5-20251001",
  "max_tokens": 256,
  "system": [
    {
      "type": "text",
      "text": "<contents of priv/intent_resolver/system_prompt.md>",
      "cache_control": {"type": "ephemeral"}
    }
  ],
  "tools": [ /* 10 tool definitions — see contracts/tools.md */ ],
  "tool_choice": {"type": "any"},
  "messages": [
    {
      "role": "user",
      "content": "<rendered context snapshot — see contracts/system_prompt.md §user message>"
    }
  ]
}
```

**Key request-shape decisions**:

- `tool_choice: {type: "any"}` — forces the model to call a tool. Without this the model might respond with prose; with it, every response contains exactly one `tool_use` block. (If we ever want streaming clarifying-questions back to the player, we'd drop this — out of scope.)
- `max_tokens: 256` — tool calls are short; we don't need long outputs. Caps cost from any pathological run-on.
- `cache_control: {type: "ephemeral"}` on the system block — caches the system prompt for 5 minutes. Tool definitions occupy positions BEFORE the cache marker if we place the marker on the last tool entry; placing it on the system block instead means tools are NOT cached. Choice: place the marker on the **last tool definition** (see `contracts/system_prompt.md` for the exact placement), which caches everything from the start of the request up to and including that marker.

---

## Entity 4 — Anthropic Response (tool_use)

The relevant subset of the API response we actually parse.

```json
{
  "id": "msg_xxx",
  "type": "message",
  "role": "assistant",
  "model": "claude-haiku-4-5-20251001",
  "content": [
    {
      "type": "tool_use",
      "id": "toolu_xxx",
      "name": "take",
      "input": {"object": "brass lantern"}
    }
  ],
  "stop_reason": "tool_use",
  "usage": {
    "input_tokens": 312,
    "cache_creation_input_tokens": 0,
    "cache_read_input_tokens": 1842,
    "output_tokens": 28
  }
}
```

**Parsing rule**: scan `content` for the first block where `type == "tool_use"`. If there is exactly one such block and its `name` is in the expected tool set, return `{:ok, {name, input}}`. Anything else → `{:error, :unexpected_response}` (mapped to a uniform refusal by the resolver).

**Cache hit detection**: `usage.cache_read_input_tokens > 0` ⇒ cache hit. Logged for observability (see research §11).

---

## Entity 5 — Resolver Outcome

The return shape of `World.IntentResolver.resolve/2`.

```elixir
@type resolve_outcome ::
        {:ok, action_tuple}
        | {:error, refusal_message :: String.t()}

@type action_tuple ::
        {:take, object :: String.t()}
        | {:drop, object :: String.t()}
        | {:move, direction :: atom()}
        | {:look}
        | {:inventory}
        | {:say, text :: String.t()}
        | {:emote, text :: String.t()}
        | {:tell, recipient :: String.t(), text :: String.t()}
        | {:whisper, recipient :: String.t(), text :: String.t()}
```

**Critical design point**: the action tuples are **shape-compatible with `CommandParser.parse/1`'s success outputs** for the same verbs:

| Resolver tuple | Matches parser sentinel from feature 003/004 |
|----------------|---------------------------------------------|
| `{:take, name}` | `{:take, name}` |
| `{:drop, name}` | `{:drop, name}` |
| `{:move, :north}` | `{:move, :north}` |
| `{:look}` | `{:look}` |
| `{:inventory}` | `{:inventory}` |
| `{:say, text}` | `{:say, text}` |
| `{:emote, text}` | `{:emote, text}` |
| `{:tell, r, t}` | `{:tell, r, t}` |
| `{:whisper, r, t}` | `{:whisper, r, t}` |

This means `GameLive.handle_event` can dispatch the resolver's output through the **exact same case branches** that already handle the fast-path sentinels. No new handler functions are needed — only a new routing step that maps `{:unknown, raw}` → async resolver task → existing handler.

`refusal_message` is the player-facing refusal copy (either model-authored from a `refuse` tool call, or one of the system-canned messages from research §9).

---

## Entity 6 — Async Task Envelope (LiveView side)

When `GameLive` spawns the resolver, it tracks the in-flight invocation in socket assigns:

```elixir
%{
  resolver_task: %{
    ref: Task.ref(),
    raw_input: String.t(),
    spawned_at: System.monotonic_time(:millisecond)
  } | nil
}
```

Used to:

- Match the eventual `{ref, result}` message in `handle_info/2` (must match the active ref to avoid stale-result confusion if the player somehow triggers two resolvers — defensive).
- Render the "thinking…" UI affordance while non-nil.
- Compute end-to-end latency for telemetry.

Cleared (set to `nil`) after the task result is processed. Demonitored at the same time.

---

## What is explicitly NOT in the data model

| Not present | Where it would have lived | Why omitted |
|-------------|---------------------------|-------------|
| Ecto schema for resolver requests/responses | `lib/agenticrealms/world/schemas/...` | Stateless — nothing to persist. |
| Cached conversation history | A new ETS table or DB column | Stateless per Assumptions; each invocation is independent. |
| Per-player rate-limit counters | An ETS table or Redis | Deferred to operational tuning per FR-016. |
| Tool-call result confirmation back to the model | A `tool_result` content block in a follow-up turn | We don't do multi-turn reasoning. The single tool_use is the final answer. |
| Streaming response handling | Streaming SSE parser | Out of scope — tool calls are short and we don't show partial output. |
| Embedding/RAG over game content | Vector store, embedding code | Out of scope. The room context is small enough to fit in the prompt directly. |
