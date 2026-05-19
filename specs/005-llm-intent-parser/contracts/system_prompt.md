# Contract — System prompt and prompt-caching strategy

Defines the system prompt content sent to the Anthropic Messages API, the caching strategy that keeps per-request cost low, and the volatile user-message shape.

## File layout

- **Static content**: `priv/intent_resolver/system_prompt.md` — markdown file loaded at compile time via `@external_resource` + `File.read!/1`. Allows iterating on prompt wording without touching code; redeploy required to pick up changes.
- **Render module**: `lib/agenticrealms/world/intent_resolver/system_prompt.ex` — exposes `text/0` returning the file's contents. Trivial; exists so the resolver can call it without filesystem awareness.

## What's cached vs. volatile

| Block | Position in request | Cached? | Approx tokens |
|-------|---------------------|---------|----------------|
| `system` block (role, rules, few-shot examples) | top-level `system` field | YES (everything up to the cache marker) | 800–1200 |
| `tools` array (10 tool definitions) | top-level `tools` field, before the cache marker | YES | 700–900 |
| `messages` array (single user message with context snapshot + player input) | top-level `messages` field, AFTER the cache marker | NO — volatile per request | 150–250 |

**Cache marker placement** (implementation-corrected): `cache_control: {type: "ephemeral"}` on the **system block**. Render order is `tools → system → messages`; anything BEFORE the marker is cached. A marker on the system block therefore caches the tools array + the system prompt as one window. (An earlier draft of this contract said "last tool definition" — that would cache only the tools, since the system block renders *after* the tools. The code places the marker on the system block.)

**Caching does not engage at the current prompt size**: Haiku 4.5's minimum cacheable prefix is 4096 tokens; system + tools total ~2000–2500 tokens. The marker is harmless (no error, request just isn't cached) and future-proofs a larger prompt. Uncached cost is ~$0.003/request — negligible. See `research.md` §4.

**Why not place the marker on the system block instead**: A cache marker on the system block would cache the system block ONLY and leave the tools array uncached. With ~800 tokens of tools that's a meaningful miss; caching them as part of the same window is strictly better.

## System prompt content (the markdown file)

The file `priv/intent_resolver/system_prompt.md` is structured as follows. Section breaks are emphasis markers for the model, not code structure.

```markdown
# Role

You are the intent parser for Agentic Realms, a text-adventure MUD. Your job
is to read raw player input and call exactly one tool from the available
actions. You never speak directly to the player — your response is always a
tool call.

# Game rules and tool-use protocol

- Call exactly one tool per request. Never call multiple tools. If the
  player's input describes more than one action (e.g., "take the lantern
  and head north"), call `refuse` with a message asking them to issue one
  action at a time.

- The `refuse` tool is your only sanctioned non-action output. Use it when:
  the player's intent doesn't map cleanly to any available action; the
  player asks an out-of-game question; the player attempts an action that
  doesn't exist (combat, magic, examining specific objects, etc.); or the
  input is ambiguous or nonsense.

- DO NOT substitute a near-mapping action. If the player asks to `examine`
  an object but no examine tool exists, call `refuse` — do NOT call `look`
  as a stand-in. The `look` tool shows the current room as a WHOLE, never a
  specific object.

- All `text` arguments pass through to game logic verbatim. Preserve the
  player's original casing, punctuation, and word choice in `say`, `emote`,
  `tell`, and `whisper`. Do not rewrite or paraphrase the player's speech.

- For object references: use the player's wording (e.g., "the brass lantern"
  or just "lantern"). The game performs case-insensitive lookup against
  actual room contents, so don't worry about exact capitalization. If the
  player references an object that is NOT in the room context, you may
  still attempt the action — the game will refuse with its own "you don't
  see that here" response.

- For recipient references in `tell` and `whisper`: use the name the player
  typed. The game performs case-insensitive matching against actual players.

# Examples

Each example shows a `user message` (the volatile context block plus player
input) followed by the tool call you should make.

## Example 1 — straightforward take

User message:
```
Current room: Stone Atrium
Objects here: brass lantern, leather-bound journal
Player typed: grab the brass lantern off the floor
```

Tool call: `take(object: "brass lantern")`

## Example 2 — direction with extra words

User message:
```
Current room: Stone Atrium
Exits: north (Forest Path), east (Corridor)
Player typed: I want to head north
```

Tool call: `move(direction: "north")`

## Example 3 — near-mapping refusal (DO NOT substitute look)

User message:
```
Current room: Stone Atrium
Objects here: brass lantern
Player typed: examine the lantern closely
```

Tool call: `refuse(message: "You can `look` to see the whole room, but examining specific objects isn't supported yet.")`

## Example 4 — multi-step refusal

User message:
```
Player typed: take the lantern and head north
```

Tool call: `refuse(message: "Try one action at a time — take the lantern first, then head north.")`

## Example 5 — out-of-game question

User message:
```
Player typed: what time is it?
```

Tool call: `refuse(message: "I can't answer that — try a game action like `look` or `inventory`.")`

## Example 6 — communication

User message:
```
Other players present: alice_42
Player typed: tell alice I'm running late
```

Tool call: `tell(recipient: "alice_42", text: "I'm running late")`

## Example 7 — whisper to same-room player

User message:
```
Other players present: bob_17
Player typed: lean in and quietly tell bob to watch out
```

Tool call: `whisper(recipient: "bob_17", text: "watch out")`

## Example 8 — inventory query

User message:
```
Your inventory: brass lantern, leather-bound journal
Player typed: what am I carrying?
```

Tool call: `inventory()`

## Example 9 — drop variant

User message:
```
Your inventory: brass lantern
Player typed: put down the lantern
```

Tool call: `drop(object: "brass lantern")`

# Final reminders

- One tool call per request. Multi-step → `refuse`.
- Near-mapping → `refuse` with a hint. Never substitute.
- Refusal messages should be brief, friendly, and never mention the LLM,
  tools, or any implementation internals.
- Preserve player casing and word choice in `say`, `emote`, `tell`,
  `whisper`.
```

## Volatile user message format

The single message in the `messages` array follows this template (filled per request by `World.IntentResolver.ContextSnapshot`):

```text
Current room: <room.name>
Description: <room.description, truncated to 300 chars>
Exits: <comma-separated "<direction> (<target_name>)" tuples, or "(none)">
Objects here: <comma-separated names, or "(none)">
Other players present: <comma-separated usernames, or "(none)">
Your inventory: <comma-separated names, or "(empty)">

Player typed: <raw_input verbatim>
```

**Field rules** (also in `data-model.md` Entity 2):

- Description trimmed to 300 characters; append `…` if truncated.
- Empty collections render as their named placeholder ("(none)", "(empty)") so the model sees an explicit signal instead of inferring from absence.
- "Other players present" is already online-filtered (per the 003b fix) — offline players don't appear.
- The `Player typed:` line is the literal raw input from the parser's `{:unknown, raw}` tuple — case preserved, whitespace preserved.

## Cache hit detection

After each response, the resolver inspects `response["usage"]["cache_read_input_tokens"]`. A positive value indicates the cache window was reused; zero indicates a cache miss (first request, or after the 5-minute TTL expired). Logged at `:info` level per request and emitted as a telemetry event for aggregation.

**Expected cache hit rates**:

- Within a single play session (commands issued within a 5-minute window): nearly 100%.
- Cold start (first command in a fresh session): 0% (cache creation).
- After a 5+ minute gap: 0% again (cache expired); back to 100% on subsequent requests.

If observed cache hit rate is consistently below ~80% during active play, investigate: cache marker placement bug, system prompt drift between deploys, or some other invalidator.

## Iteration workflow

To change the prompt:

1. Edit `priv/intent_resolver/system_prompt.md`.
2. Run the live-LLM smoke test against the curated input set (`mix test --include live_llm`).
3. If accuracy regresses on any case, rework the example or rule.
4. Commit, deploy. The 5-minute cache will rebuild on the first request post-deploy.

No code changes required for prompt iteration.
