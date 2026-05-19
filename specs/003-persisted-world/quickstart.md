# Quickstart — 003 Persisted World

**Date**: 2026-05-18
**Branch**: `003-persisted-world`
**Audience**: developer setting up the feature locally and validating it works end to end.

This document walks through the one-time setup, the day-to-day dev loop, and a hand-runnable validation script that exercises every clarification recorded in the spec. It is **not** a substitute for the test suite — but a smoke pass through this script should reveal any large regressions before opening a PR.

---

## 1. One-time setup

After pulling the branch:

```bash
mix deps.get
mix event_store.init        # creates the agenticrealms_eventstore database and its migrations
mix ecto.setup              # ecto.create + ecto.migrate + run priv/repo/seeds.exs (which seeds the starter world)
```

If you've previously run the feature and want to reset everything:

```bash
mix ecto.reset              # drops the read-model DB, recreates, re-migrates, re-seeds
mix event_store.drop && mix event_store.init   # nukes the event store so the seed events are fresh
```

**Connection strings**: by default both databases live on the local Postgres instance configured in `config/dev.exs`:

- `agenticrealms_dev` — read-model DB (existing).
- `agenticrealms_eventstore_dev` — event store DB (new).

In production (`config/runtime.exs`), both are read from `DATABASE_URL` and `EVENTSTORE_URL` respectively. If you prefer a single DB with a separate schema, set the `eventstore` config option `schema: "eventstore"` instead of `database: …`; both layouts are supported by the adapter.

---

## 2. Running the app

```bash
iex -S mix phx.server
```

Visit `http://localhost:4000`, register a new player (or log in with an existing one), and click **Play**. You should land in the **Stone Atrium** of the seeded starter map. A `:room` entry should appear in your narrative log on mount.

---

## 3. Hand validation script

The following sequence covers every story (US1–US5) and every clarification (Q1–Q5). Run it in two browser windows to exercise the multi-player and multi-session cases.

### Single-player happy path

Open one browser, log in as **alice**, click Play.

| # | Action | Expected |
|---|---|---|
| 1 | Read the on-mount log entry. | `:room` entry: "Stone Atrium" + description + exits (north → corridor, east → library) + objects ("brass lantern"). |
| 2 | Type `look` and press Enter. | A fresh `:room` entry matching #1. |
| 3 | Type `inventory`. | `:system` entry: "You aren't carrying anything." |
| 4 | Type `take brass lantern`. | `:system` entry: "You take the brass lantern." |
| 5 | Open the Inventory HUD card. | Shows ONE row: "brass lantern" with its short description. No equipped marker, no quantity badge, no filter input. (FR-031, Q3.) |
| 6 | Type `inv`. | `:system` entry listing the brass lantern. Same data as the HUD card. (FR-015.) |
| 7 | Type `look`. | `:room` entry — note that the brass lantern is NO LONGER listed in the room's objects. |
| 8 | Type `go east`. | `:room` entry for "Dusty Library." Log shows you arrived. |
| 9 | Type `take reading lectern`. | `:system` entry: "You can't take the reading lectern." (FR-010.) |
| 10 | Type `take leather-bound journal`. | `:system` entry: "You take the leather-bound journal." |
| 11 | Type `west`. | `:room` entry for "Stone Atrium" — back where you started. |
| 12 | Type `drop brass lantern`. | `:system` entry: "You drop the brass lantern." |
| 13 | Type `look`. | `:room` entry — brass lantern is back in the room; leather-bound journal is still in your inventory. |
| 14 | Type `north`. | `:room` entry for "North Corridor" (the empty room). |
| 15 | Type `look`. | `:room` entry showing no objects, no other players. |
| 16 | Type `south`. | `:room` entry for "Stone Atrium." |
| 17 | Type `dance`. | `:system` entry: "I don't understand \"dance\"." (FR-018.) |
| 18 | Type `   ` (only whitespace) and press Enter. | NO log change. (FR-019.) |
| 19 | Restart the Phoenix server (`Ctrl-C ENTER`, then `iex -S mix phx.server`). Reload the page. | You are restored to "Stone Atrium" (your last known location) with the leather-bound journal still in your inventory. (SC-004, FR-004.) |

### Two-player witness propagation

Keep the **alice** window open in the Stone Atrium. In a second browser (different profile / private window) register and log in as **bob**, click Play.

| # | Window | Action | Expected in OTHER window |
|---|---|---|---|
| 20 | bob | Has just mounted in the Stone Atrium. | **alice** sees a `:system` entry: "bob arrives." (FR-027, U3.) |
| 21 | alice | Type `look`. | (no effect on bob — `look` is query-only, D6.) |
| 22 | alice | Type `take brass lantern`. | **bob** sees: "alice takes the brass lantern." (FR-025, U1.) |
| 23 | bob | Open Inventory HUD card. | Empty — bob is not carrying anything. |
| 24 | bob | Type `look`. | `:room` entry — brass lantern no longer listed in room contents. (SC-007.) |
| 25 | alice | Type `drop brass lantern`. | **bob** sees: "alice drops the brass lantern." (FR-026, U2.) |
| 26 | alice | Type `go east`. | **bob** sees: "alice leaves to the east." (FR-028, U4.) |
| 27 | bob (still in Atrium) | Type `east`. | **alice** (now in Library) sees: "bob arrives from the west." (FR-027, U3 with direction.) |

### Concurrent take race (Q1)

Have **alice** in the Atrium and **bob** in the Atrium. The brass lantern is on the floor (drop it back if needed).

| # | Action | Expected |
|---|---|---|
| 28 | Both windows type `take brass lantern` and press Enter as close to simultaneously as you can. | EXACTLY ONE wins: that player's log shows "You take the brass lantern." The OTHER player's log shows "You don't see that here." (FR-011, Q1.) Both players' HUDs reflect the correct outcome. |

### Multi-session (Q5)

Open a SECOND tab as **alice** (so you have two tabs both logged in as alice).

| # | Tab | Action | Expected |
|---|---|---|---|
| 29 | Tab A | Type `take leather-bound journal` (if you dropped it earlier, move to the Library and pick it up again first). | Tab A: "You take the leather-bound journal." Tab B: the Inventory HUD card AND `inventory` command BOTH now show the journal — but Tab B did NOT receive a confirmation log entry. (FR-032, FR-033, FR-034.) |
| 30 | Tab A | Type `go west` (if you are in the Library). | Tab A: `:room` entry for the destination. Tab B: also receives a `:room` entry for the new room (via `PlayerCurrentRoomChanged` → re-rendered look) AND its room-topic subscription has been swapped to the new room. (Verify by having Tab B issue `look` — the result matches Tab A.) |
| 31 | A third browser as **carol**, mounted in the destination room. | Carol's first log on mount: `:room` entry showing alice present. | When alice (from tab A) takes/drops/moves, carol sees the witness messages. When alice (from tab A) takes an object, **neither** of alice's tabs receives a `RoomObjectTaken` witness (FR-029, FR-035). |

### FR-022 deleted-room recovery (manual)

(This is harder to simulate in dev without a DB hack; document the steps for posterity.) From `iex`:

```elixir
# 1. Get alice's current_room_id
state = AgenticRealms.Repo.get_by!(AgenticRealms.World.Schemas.PlayerState, player_id: alice_id)
# 2. Delete that room's read-model row (simulating a seed change)
AgenticRealms.Repo.delete_all(from r in AgenticRealms.World.Schemas.Room, where: r.id == ^state.current_room_id)
# 3. On alice's next page reload of /play, she should be respawned in the Stone Atrium
# 4. Her log should include the FR-022 "previous location is no longer reachable" system message
```

### FR-023 account-deletion returns objects

Have **alice** carrying the brass lantern in the Stone Atrium. From the Settings page, delete alice's account. Log in as **bob** (or any other player), navigate to the Stone Atrium, and `look`. The brass lantern should be present in the room. (FR-023.)

---

## 4. Test suite

```bash
mix test                      # full suite (includes Postgres setup)
mix test test/agenticrealms/world/         # aggregate, projection, parser, queries
mix test test/agenticrealms_web/live/game_live_test.exs   # integrated LiveView flows
```

The Commanded in-memory adapter is used in the test environment to avoid per-test event-store DB resets; see `config/test.exs`.

---

## 5. Known sharp edges (heads-up for the implementer)

- **Aggregate identity must be a string** in Commanded; convert `player.id` (integer) with `Integer.to_string/1` at the dispatch boundary. Define a helper `World.player_stream_id/1` and use it everywhere to avoid drift.
- **The Player aggregate has no inventory state** (per the data-model.md §1.2 final decision). Don't add inventory tracking to it — that's read-model territory only. Tests should not assert against aggregate inventory.
- **Direction normalization** belongs in `World.Direction.parse/1` and `World.Direction.opposite/1` — don't sprinkle string-to-atom logic across the parser, broadcaster, and aggregates.
- **`World.Seed.run/0`** must be idempotent. The seed task in `priv/repo/seeds.exs` checks `Repo.aggregate(Room, :count) == 0` before dispatching any seed commands. Running it twice must not duplicate rooms.
- **HUD card markup** in `lib/agenticrealms_web/components/game_components.ex` currently renders the 001 mock (`equipped`, `quantity`, etc.). Per FR-031 (Q3), strip those bindings entirely — do not just hide them with CSS.
- **Subscriber-side actor exclusion** is enforced in `GameLive.handle_info/2` clauses for U1–U4: pattern-match `%RoomObjectTaken{actor_id: actor_id}` where `actor_id == socket.assigns.current_player.id` → discard. This is the only place this rule lives; don't try to do it in the broadcaster.
- **Don't use `String.to_atom/1`** on parser input (AGENTS.md guideline + memory leak risk). The parser's verb table uses literal pattern matching against pre-allocated atoms only.
