# Quickstart — Player Communication (feature 004)

A manual walkthrough to validate the feature end-to-end in local dev. No new setup steps beyond what feature 003 already requires — communication is pure-runtime and adds no migrations or seeds.

## Prerequisites

Assumes feature 003 is fully working in your local checkout (server boots, seed runs, you can `look` / `go` / `take` / `drop` in a single browser tab). If not, run through `specs/003-persisted-world/quickstart.md` first.

```bash
# Dependencies (no new deps for 004)
mix deps.get

# DB / event store (untouched by 004)
mix ecto.setup       # if your DB isn't already set up; no new migrations to run
mix event_store.setup

# Run the test suite to confirm nothing is broken before you start
mix test
```

## Boot the server

```bash
mix phx.server
```

You'll need **three** browser sessions (different browsers or incognito windows so they each get a separate Phoenix session). Register three player accounts via `/players/register`:

- **Alice** (whatever password)
- **Bob**
- **Carol**

All three start in the same seeded starting room.

## 1. Say (US1, P1)

In Alice's tab, click **Play** and type:

```
say hello everyone
```

**Expected**:

- Alice's log: a first-person speech confirmation entry (e.g., "You say, 'hello everyone'.")
- Bob's log (same room): a witness speech entry attributed to Alice (e.g., "Alice says, 'hello everyone'.")
- Carol's log (same room): same witness entry as Bob.

Now have Bob type `north` (or whichever exit leads out) so Bob is no longer in Alice's room. Alice says again:

```
'hi
```

**Expected**:

- Alice: confirmation entry.
- Carol (still in room): witness entry.
- Bob (different room now): **no new entry**.

Test the apostrophe shortcut and empty refusal:

```
'           ← whitespace only
say         ← verb only
```

**Expected**: both produce a refusal entry in Alice's log ("Say what?") and no broadcast.

## 2. Emote (US2, P2)

Have Bob walk back to Alice's room. Alice types:

```
emote waves at the fire
```

**Expected**:

- Alice's log: third-person narration entry ("Alice waves at the fire.").
- Bob, Carol (same room): identical narration entry.

Try the aliases:

```
me bows
:smiles
```

**Expected**: same rendering ("Alice bows.", "Alice smiles."). Note that the period was auto-appended because the text didn't end with `.`, `!`, or `?`. Test that pre-punctuated input is not double-punctuated:

```
:laughs!
```

**Expected**: "Alice laughs!" (one `!`, not `!.`).

## 3. Tell (US3, P3)

Have Bob walk to a different room from Alice. Alice types:

```
tell bob meet me by the fire
```

**Expected**:

- Alice's log: actor-side confirmation ("You tell Bob, 'meet me by the fire'.").
- Bob's log (different room): private tell entry from Alice.
- Carol's log (still in Alice's room): **no new entry** — tell never broadcasts to the sender's room.

Note that `bob` was typed in lowercase but resolved to the registered username `Bob` (case-insensitive resolution). The confirmation should show the canonical casing (`Bob`).

Test ambiguity. Register a fourth account `BOB` (case variant of `Bob`):

- Visit `/players/register`, create `BOB` with any password.

Now have Alice try:

```
tell bob hello
```

**Expected**: refusal entry in Alice's log ("Multiple players match 'bob'."). No tell delivered to anyone.

(After this test, you can leave `BOB` registered — it doesn't interfere with the other scenarios as long as you address recipients unambiguously.)

Test offline-recipient handling. Have `BOB` log out (or close all of BOB's tabs). Alice tries:

```
tell BOB hello
```

**Expected**: Alice sees the neutral "could not be delivered" refusal. The refusal does NOT say "BOB is offline" or "BOB is in another room" — only that it couldn't be delivered (FR-016).

Test the alias and the no-text path:

```
t alice hi
t alice
```

**Expected**:

- `t alice hi`: refused with self-target refusal ("You can't tell yourself.").
- `t alice` (no text): refused with "Tell whom what?" (no recipient resolution attempted yet; the no-text refusal short-circuits).

## 4. Whisper (US4, P4)

Have Alice and Carol in the same room; Bob in a different room. Alice types:

```
whisper carol look out for the wizard
```

**Expected**:

- Alice's log: confirmation ("You whisper to Carol, 'look out for the wizard'.").
- Carol's log: private whisper entry from Alice.
- Bob's log (different room): **no new entry**.
- If you spawn a fourth player Dave in Alice & Carol's room: Dave's log shows **no new entry** either — whisper is private even within the same room.

Test the cross-room refusal:

```
w bob psst
```

**Expected**: Alice sees a refusal ("Bob is not nearby. Try `tell` instead."). No delivery to Bob.

Test self-whisper:

```
w alice talking to self
```

**Expected**: refusal ("You can't whisper to yourself.").

## 5. Multi-session

In a *second* browser tab for Alice (so two simultaneous LiveView sessions for the same player, both in the same room as Carol):

- From Alice's **tab 1**: `say hello`
  - **Tab 1**: actor-side confirmation entry.
  - **Tab 2** (same player, same room): witness speech entry attributed to Alice (mirroring 003's multi-session pattern).
  - **Carol**: witness speech entry.

- From Alice's **tab 1**: `tell carol private`
  - **Tab 1**: actor-side confirmation.
  - **Tab 2**: **no new entry** (tell does NOT echo to the sender's other sessions).
  - **Carol**: private tell entry.

## 6. Length cap

Paste a 600-character message into the input and submit `say` with it.

**Expected**: refusal ("Your message is too long..."). No broadcast.

Submit exactly 500 characters:

**Expected**: accepted. Broadcast goes through. (Use `Enum.join(List.duplicate("x", 500), "")` from `iex` to generate the payload if you don't want to hand-count.)

## 7. HTML escape (FR-024)

Submit `say <script>alert(1)</script>` from Alice.

**Expected**: every witness session renders the literal text `<script>alert(1)</script>` (escaped). No script execution, no DOM injection. Open the browser devtools and inspect the rendered log entry — it should contain `&lt;script&gt;` in the HTML source.

## Tests

```bash
# Just the new files
mix test test/agenticrealms/world/command_parser_test.exs \
         test/agenticrealms/world/communication_test.exs \
         test/agenticrealms/world/communication/recipient_resolver_test.exs \
         test/agenticrealms_web/live/game_live_communication_test.exs

# Full suite — should pass with no regressions
mix test
```

The communication unit tests use `Phoenix.PubSub.subscribe/2` to assert on broadcasts directly. The LiveView tests use `live_isolated/2` to spawn multiple independent LiveView processes representing different sessions; the standard `Phoenix.LiveViewTest.render/1` / `render_submit/2` flow drives input and asserts on rendered DOM.

## Done

If everything above works, you've validated all four user stories, all five clarifications (transient delivery, case-insensitive resolution, neutral offline refusal, 500-char cap, self-target refusal), and the multi-session and safety requirements. Move on to `/speckit-tasks` to break implementation into tracked work items.
