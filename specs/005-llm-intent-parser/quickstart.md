# Quickstart — Natural-Language Player Commands (feature 005)

A manual walkthrough to validate the feature end-to-end in local dev.

## Prerequisites

Assumes features 003 and 004 are fully working in your local checkout. If not, walk through `specs/003-persisted-world/quickstart.md` and `specs/004-player-communication/quickstart.md` first.

```bash
# Dependencies (one new dep: req)
mix deps.get

# DB / event store (untouched by 005)
mix ecto.setup
mix event_store.setup

# Confirm baseline
mix test
```

## Get an Anthropic API key

This feature calls the Anthropic Messages API. You need an API key from <https://console.anthropic.com>.

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

Without this env var set, the feature degrades gracefully: any natural-language input that the fast parser can't handle produces an "I don't understand that" refusal — same as pre-005 behavior. Setting the key unlocks the LLM fallback.

Optional overrides:

```bash
# Use a different model (default: claude-haiku-4-5-20251001)
export ANTHROPIC_MODEL="claude-sonnet-4-6"

# Tighter or looser HTTP timeout (default: 5000 ms)
export ANTHROPIC_TIMEOUT_MS="3000"

# Point at a mock server (default: https://api.anthropic.com)
export ANTHROPIC_BASE_URL="http://localhost:1234"
```

## Boot the server

```bash
mix phx.server
```

You'll need at least **two** browser sessions for the multi-player scenarios. Register two accounts via `/players/register` (e.g., **Alice** and **Bob**). Both start in the seeded atrium.

## 1. Canonical commands still fast (regression check)

Before testing the LLM path, confirm the fast path is unaffected. In Alice's tab, type:

```
look
take brass lantern
inventory
n
```

**Expected**: each command resolves instantly (under 50 ms — way faster than human perception). No "thinking..." indicator. Identical behavior to pre-005.

## 2. Natural-language take

```
grab the lantern off the floor
```

**Expected**:

- Your literal input echoes in the log as a `:cmd` entry (`grab the lantern off the floor`).
- A subtle "..." appears for ~300-800 ms while the LLM resolves the intent.
- The lantern moves to your inventory. The standard `:system` confirmation appears ("You take the brass lantern.").
- Bob's log (same room) shows the witness entry ("Alice takes the brass lantern.") — unchanged from 003.

Try variations to confirm the LLM is doing real work:

```
let me pick up that thing
I want the lantern please
```

**Expected**: each resolves to the same take action.

## 3. Natural-language movement

Drop the lantern back first so the room state is interesting:

```
put down the lantern
```

Then try movement variants:

```
head north
walk towards the corridor
let's go north
```

**Expected**: each takes Alice north. Bob sees the witness departure entry.

## 4. Natural-language communication

With both Alice and Bob in the same room:

```
say hi everyone how's it going
tell bob I'll be right back
ask bob if he's seen the journal
```

**Expected**:

- First command → standard `say` broadcast; Bob sees Alice's speech entry.
- Second command → `tell` to Bob; Bob sees a private tell entry.
- Third command → resolver maps "ask bob if he's seen the journal" to `tell(recipient: "bob_X", text: "have you seen the journal?")` (or similar paraphrase). The resolver is allowed to lightly rephrase questions into tell content — verify this matches your taste; if not, the system prompt's "preserve casing" rule should be tightened.

## 5. Refusal scenarios

Try input the resolver should refuse:

```
examine the lantern closely
```

**Expected**: refusal entry hinting that `look` shows the room but examining specific objects isn't supported yet. **Critical**: the resolver should NOT call `look` as a substitute — that would render the current room when you asked about a specific object.

```
attack the wizard
cast a spell
save my game
what time is it?
```

**Expected**: each produces a refusal entry. Wording varies (LLM-authored per request) — should be friendly and brief, never mentioning LLMs/tools/APIs.

```
take the lantern and head north
```

**Expected**: refusal hinting that the game only supports one action at a time. Try chaining manually:

```
take the lantern
n
```

**Expected**: both work (the second one is a canonical fast-path command).

## 6. Failure-mode validation

Test graceful degradation when the API misbehaves. Try in three ways:

**Without API key set**: unset `ANTHROPIC_API_KEY` and restart the server. Type a natural-language command. **Expected**: "I don't understand that." refusal (matches pre-005 behavior; no crash).

**With an invalid API key**: set `ANTHROPIC_API_KEY=sk-invalid` and restart. Type a natural-language command. **Expected**: graceful "I'm not sure what you meant just now." refusal within ~1 second. No crash. Bob's session unaffected.

**With a bogus base URL**: set `ANTHROPIC_BASE_URL=http://localhost:65000` (an unreachable port) and restart. Type a natural-language command. **Expected**: graceful refusal within ~5 seconds (the timeout bound). Bob's session unaffected.

## 7. Concurrency: input is locked while resolver works

Type a natural-language command and IMMEDIATELY try to submit another:

```
grab the lantern please
look      ← submit this before the first one completes
```

**Expected**: while the LLM is in flight, the input is locked (visually disabled). The second submission either bounces or is queued until the first resolves. Once the first command's result lands, input unlocks and the second submission can proceed.

(If lock-during-resolve feels too restrictive in practice, the lock can be loosened in a follow-up — the spec said it's MAY, not MUST.)

## 8. Observability check

Tail the server logs while issuing natural-language commands:

```bash
tail -f log/dev.log  # or wherever your dev logs land
```

Each resolver invocation should emit a structured info log line:

```
[info] intent_resolver player_id=42 input_length=27 outcome=action_chosen tool_name=take latency_ms=412 cache_hit=true
```

- `cache_hit=false` on the very first invocation after a server restart (cache window must be built first).
- `cache_hit=true` on every subsequent invocation within 5 minutes.
- `latency_ms` typically 300-800 ms on cache-hit invocations; up to ~1200 ms on the cold cache-miss invocation.

If you don't see `cache_hit=true` after a few invocations, the cache marker placement is wrong — investigate.

## 9. Tests

```bash
# Unit + integration (excludes :integration and :live_llm by default)
mix test

# All non-live tests including integration
mix test --include integration

# Live smoke test against the real Anthropic API (requires ANTHROPIC_API_KEY)
mix test --include live_llm test/agenticrealms/world/intent_resolver_live_test.exs
```

The live smoke test issues ~10 canned natural-language inputs against the real API and asserts the right tool was called. It's slow (~10-20 seconds) and costs ~$0.001-$0.005 in API tokens per run. Don't include it in CI's default suite.

## Done

If everything above works, you've validated:

- Fast path unchanged (canonical commands still instant).
- LLM path resolves natural-language variants for all 9 canonical actions.
- Refusal coverage for out-of-scope, near-mapping, multi-step, and out-of-game intent.
- Graceful failure under missing key, invalid key, and unreachable endpoint.
- Concurrency safety (input locked during resolution).
- Observability (cache hit rate visible, latency tracked).

Move on to `/speckit-tasks` to break implementation into tracked work items.
