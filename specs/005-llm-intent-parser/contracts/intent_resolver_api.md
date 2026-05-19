# Contract — `AgenticRealms.World.IntentResolver` public API

The resolver facade orchestrates the full natural-language → action pipeline: build the volatile context, call the Anthropic API, parse the tool response, and return a canonical action tuple or a refusal message.

## Module location

`lib/agenticrealms/world/intent_resolver.ex`

Sits alongside `World.Commands` (003 event-sourced write side) and `World.Communication` (004 non-event-sourced broadcasts). The three modules are intentionally separate — they share no state, and each owns one orthogonal concern.

## Public function

```elixir
@spec resolve(player_id :: integer(), raw_input :: String.t()) ::
        {:ok, action_tuple()}
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

## Behavior

1. **Pre-flight checks**:
   - `String.length(raw_input)` ≤ 500 (FR-017) — otherwise return `{:error, "Your message is too long (max 500 characters)."}`. (This SHOULD have been caught upstream in `GameLive`, but the resolver is defensive.)
   - `Queries.look_room(player_id)` returns `{:ok, room_view}` — otherwise return `{:error, "You are nowhere."}` (matches the existing 003 refusal for the "no current room" edge case).

2. **Build the context snapshot** via `ContextSnapshot.build/2` (room view + inventory + raw input, formatted per `contracts/system_prompt.md` "Volatile user message format"). Pure function; no I/O.

3. **Construct the Anthropic request body** with the cached system prompt + cached tools + the volatile user message. The system prompt content comes from `SystemPrompt.text/0` (compile-loaded from `priv/intent_resolver/system_prompt.md`). The tools list comes from `Tools.list/0`.

4. **Call the Anthropic Messages API** via `AgenticRealms.Anthropic.create_message/1`. This call:
   - Includes the auth header (`x-api-key`) and `anthropic-version` header.
   - Enforces a 5-second timeout on the HTTP receive.
   - Returns `{:ok, response_body}` on 200-class responses or `{:error, reason}` on any failure mode (HTTP error, timeout, malformed JSON).

5. **Parse the response**:
   - Scan `response_body["content"]` for the first `type: "tool_use"` block.
   - If exactly one such block AND the tool name is in the expected 10-tool set AND its input fields validate against the schema:
     - Map the tool name + input to an action tuple per the table below.
     - Return `{:ok, action_tuple}`.
   - If the tool is `refuse`: return `{:error, response.input["message"]}` (the LLM-authored refusal text).
   - For any other shape (multiple tool_use blocks, unrecognized tool name, missing required field, etc.): return `{:error, uniform_failure_message()}`.

6. **Log + emit telemetry** with player_id, latency_ms, outcome, tool_name, cache_hit (boolean) for every invocation (research §11). Logging and telemetry happen BEFORE the function returns so the caller sees a consistent record.

## Tool-call → action-tuple mapping

| Tool name | Input fields | Action tuple |
|-----------|--------------|--------------|
| `take` | `object: string` | `{:take, object}` |
| `drop` | `object: string` | `{:drop, object}` |
| `move` | `direction: enum` | `{:move, String.to_existing_atom(direction)}` (safe because enum is constrained) |
| `look` | (none) | `{:look}` |
| `inventory` | (none) | `{:inventory}` |
| `say` | `text: string` | `{:say, text}` |
| `emote` | `text: string` | `{:emote, text}` |
| `tell` | `recipient: string, text: string` | `{:tell, recipient, text}` |
| `whisper` | `recipient: string, text: string` | `{:whisper, recipient, text}` |
| `refuse` | `message: string` | `{:error, message}` (this becomes the refusal returned to the caller) |

## Uniform failure message

For all unexpected-response cases (HTTP error, timeout, malformed JSON, unrecognized tool, multiple tool_use blocks, schema violations), the resolver returns:

```elixir
{:error, "I'm not sure what you meant just now."}
```

Exception: multi-tool-use responses (a misbehaving model that ignored the "one tool" rule) collapse to:

```elixir
{:error, "Try one action at a time."}
```

These are the only two system-canned refusal messages. Every other refusal comes from the model itself via the `refuse` tool.

## Concurrency / process model

The resolver is **synchronous and stateless** at the module level — no GenServer, no ETS, no internal queues. Each call runs in the caller's process (which, in `GameLive`, is a supervised `Task` per request — see plan §async dispatch).

The expensive part of the call is the HTTP round-trip; that's enforced by Req's `:receive_timeout`. There is no shared mutable state to coordinate.

Multiple concurrent invocations (e.g., two players typing natural-language commands simultaneously) run in parallel and do not interfere — they each get their own Task, their own HTTP connection (Finch handles connection pooling), and their own response.

## Configuration the resolver reads

- `Application.fetch_env!(:agenticrealms, AgenticRealms.Anthropic)[:model]` — model id; default `claude-haiku-4-5-20251001`.
- `Application.fetch_env!(:agenticrealms, AgenticRealms.Anthropic)[:timeout_ms]` — HTTP receive timeout; default 5000.
- `System.fetch_env!("ANTHROPIC_API_KEY")` — API key; absence at module load is fine, but per-request absence returns `{:error, "I don't understand that."}` (matches the existing pre-005 unknown-command behavior).

## Out-of-process callers

The resolver is callable from any Elixir process — primarily from `GameLive`'s supervised Task, but also directly from tests with mocked Anthropic responses. There is no LiveView-specific state required at the resolver boundary; `player_id` and `raw_input` are the only inputs.

## Contract on response time

The resolver enforces a hard 5-second internal timeout (FR-013). If the HTTP call exceeds this, `AgenticRealms.Anthropic.create_message/1` returns `{:error, :timeout}` and the resolver returns the uniform failure refusal. Callers MUST NOT need their own timeout — the resolver's bound is authoritative.

## Versioning

The action-tuple shapes are deliberately shape-compatible with the `CommandParser` fast-path sentinels (003/004). This compatibility is load-bearing — `GameLive`'s case branches dispatch them identically. Any change to a tuple's shape requires a coordinated update to `CommandParser` + `IntentResolver` + every `GameLive` handler.
