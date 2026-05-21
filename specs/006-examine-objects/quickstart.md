# Quickstart: Examine Objects and Players

Manual end-to-end walk through the three user stories from `spec.md` against the seeded starter map. Use this to smoke-test the feature locally during implementation and after merge.

## Prerequisites

- Repo set up per the README (Postgres running, `mix setup` completed).
- `ANTHROPIC_API_KEY` exported in your shell (only required to verify natural-language phrasings via the LLM fallback — the fast-path examine works without it).
- Two browser sessions (different browsers, or one regular + one Incognito window) so you can drive two players in parallel.

## Boot

```sh
mix phx.server
```

Browse to `http://localhost:4000` and register / log in two accounts. Call them **Alice** and **Bob** for the rest of this guide.

## Story 1 — Examine a room object (P1)

**As Alice**, in the Stone Atrium starting room:

```
> look
```

Verify the room view lists the brass lantern.

```
> look brass lantern
```

**Expected**: a new `:detail` log entry appears showing:
- The object name `brass lantern` as a header.
- The long description body: `An old hand-lantern of dented brass. Its glass is smoked but unbroken, and a stub of candle still rests within.`

The brass lantern remains in the room (re-run `look` to confirm — the room view still lists it).

Try partial matching:

```
> look lantern
```

Should produce the same detail entry (one partial match, unique).

Try a natural-language phrasing (requires `ANTHROPIC_API_KEY`):

```
> examine the lantern closely
```

A brief processing pause should be followed by the same detail entry. The fast parser rejects `examine` as unknown, the LLM resolver maps it to `look` with target `"brass lantern"`, and the dispatch path renders the detail.

## Story 2 — Examine an inventory object (P1)

**Still as Alice**, take the lantern and move:

```
> take brass lantern
> n
```

Alice is now in the North Corridor, which has no objects.

```
> look brass lantern
```

**Expected**: the same detail entry as before. The lookup falls through to the inventory scope because the corridor has no copy.

Try a natural-language inventory examine:

```
> what does my lantern look like?
```

Should produce the detail entry via the LLM fallback (the resolver picks up "my lantern" against the inventory context).

## Story 3 — Examine another player (P2)

Get into the same room as Bob — easiest is to bring Alice back to the atrium and have Bob log in (he spawns there too).

**As Bob**, with Alice in the same room:

```
> look
```

The room view lists Alice as a present player.

```
> look alice
```

**Expected**: a `:detail` log entry whose body is exactly `Alice is a player.` (case of the display name preserved).

```
> look ALICE
```

Should produce the same entry (case-insensitive matching).

Try the natural-language form:

```
> who is alice?
```

Should produce the same entry via the LLM fallback.

Try self-examination:

```
> look me
```

**Expected**: a detail entry reading `Bob is a player.`

```
> look self
```

Same as above. Both `me` and `self` resolve to the acting player.

## Edge cases worth eyeballing

### Refusal for unseen targets

**As Bob**, in the atrium (Alice not present):

```
> look dragon
```

**Expected**: a system log entry `You don't see that here.` (FR-012). No detail entry.

### Refusal for ambiguous mixed-kind tie

This requires a setup that the starter map doesn't naturally provide (no player is named "Lantern" by default). Skip unless you've created such a fixture in test data.

### Offline-player rule

**As Alice**, with Bob in the same room. Bob logs out (closes his browser tab / clicks logout). Wait a beat for Phoenix.Presence to register the disconnect.

**As Alice**:

```
> look bob
```

**Expected**: `You don't see that here.` — Bob is filtered out by Presence (inherits feature 003a's offline filter).

### Privacy of examination

Open the browser console on Bob's session and watch the LiveView stream. **As Alice**, in the same room as Bob:

```
> look brass lantern
> look bob
```

**Expected**: Bob's log gets NO entries from either of Alice's examinations. Bob sees only his own input and his own commands' results.

### Fast-path latency

Open Phoenix LiveDashboard at `/dev/dashboard`. Filter the telemetry metrics for `agenticrealms.examine.resolve`. Run a fast-path examine several times. Latencies should consistently be under 50ms.

For comparison, run a natural-language examine and observe the `agenticrealms.intent_resolver.resolve` metric — that's where the 300–800ms typical LLM call time shows up. The fast path is the canonical performance budget; the AI path is bounded by FR-013's 5s timeout.

## Test invocation

The corresponding ExUnit suites:

```sh
mix test test/agenticrealms/world/command_parser_test.exs
mix test test/agenticrealms/world/examine_test.exs
mix test test/agenticrealms/world/intent_resolver/tools_test.exs
mix test test/agenticrealms_web/live/game_live_examine_test.exs
mix test test/agenticrealms_web/live/game_live_intent_parser_test.exs
```

The full suite (`mix test`) should remain green after this feature merges. The Constitution Check is not enforced (constitution is the unfilled template); the only quality gate is the full ExUnit run.
