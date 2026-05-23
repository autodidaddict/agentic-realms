# Quickstart: Static NPCs

Manual end-to-end verification of every user story in the spec against the seeded starter map after this feature ships. Each section is independently testable.

## Prereqs

```bash
mix ecto.reset           # rebuild dev DB; reseeds via priv/repo/seeds.exs
mix phx.server           # localhost:4000
```

Confirm `seeds.exs` calls `AgenticRealms.World.Seed.run/0` (existing) and that the seed log line `[World.Seed] starter map seeded` appears in the server output. The seed extension for this feature dispatches one additional `SpawnNPC` command — Garrick the Innkeeper into the Stone Atrium.

## Story 1 — See an NPC in a room (P1, FR-004 / FR-005)

1. Open `http://localhost:4000/` in browser A.
2. Register or log in as `alice`.
3. Click `Play`.
4. Verify the room view of the Stone Atrium renders THREE sections in the body:
   - **Objects**: contains `brass lantern — a dented brass lantern` (existing).
   - **Other players**: empty on first login.
   - **Also here**: contains `Garrick the Innkeeper — a wiry innkeeper in a stained apron`.
5. Verify the section heading is the literal string `Also here:` (case preserved per FR-004).

**Empty-section check**:
1. Type `go north` to move into the North Corridor.
2. Verify the new room view contains no `Also here:` heading at all (the corridor has zero NPCs).
3. Type `go south` to return.

## Story 2 — Examine an NPC (P1, FR-006 / FR-007 / FR-008 / FR-009)

Continuing in Alice's session from Story 1:

1. Type `look garrick`.
2. Verify a new `:detail` log entry appears containing Garrick's full long description: `"A wiry man in a stained apron, his hands callused and his eyes patient. He polishes a tankard that already looks clean and watches the door without quite seeming to."`
3. Type `examine the innkeeper`.
4. Verify the same detail entry renders (via the LLM resolver fallback — there will be a brief network-call latency, ~300–800ms).
5. Type `inspect garrick`.
6. Verify the same detail entry renders.
7. Type `look at the old man`.
8. Verify the same detail entry renders.
9. Type `go east` to move to the Dusty Library.
10. Type `look garrick`.
11. Verify a refusal entry appears: `"You don't see that here."` — Garrick is not in this room.
12. Type `go west` to return to the Stone Atrium.

**Examination is private** (FR-010):
- Open browser B in a different incognito session, register or log in as `bob`, click `Play`.
- Verify Bob now appears in Alice's room view's "Other players" section and Alice appears in Bob's.
- In Alice's session, type `look garrick`.
- Verify Bob's narrative log shows NO new entry — examination produces no witness entry.

## Story 3 — Witness an NPC arriving in a room (P2, FR-011 / FR-012 / FR-014)

This story requires triggering a `SpawnNPC` dispatch while a live session is connected to the destination room. The seed-time spawn already fires during DB reset, but verifying the arrival entry requires a session connected at the moment of the spawn.

1. With Alice's browser already in the Stone Atrium, open a remote IEx attached to the running server:
   ```bash
   iex -S mix phx.server   # if not already running
   # ... in another terminal:
   iex --remsh observer@localhost --name console@localhost
   ```
   (Or simply use the existing IEx if the server is started with `iex -S mix phx.server`.)

2. From IEx, dispatch a one-off `SpawnNPC` for a second NPC into the Atrium:
   ```elixir
   alias AgenticRealms.World.Application, as: WorldApp
   alias AgenticRealms.World.Commands.SpawnNPC

   WorldApp.dispatch(
     %SpawnNPC{
       room_id: AgenticRealms.World.Seed.starting_room_id(),
       npc_id: Ecto.UUID.generate(),
       name: "Maelyn the Bard",
       short_description: "a slender bard tuning a lute",
       long_description:
         "A slender woman in travelling leathers, her long fingers coaxing a half-melody from a battered lute. She glances up as you enter, then back to her strings."
     }
   )
   ```

3. Switch back to Alice's browser.
4. Verify her log appended a new `:system` entry: `Maelyn the Bard arrives.`
5. Type `look`.
6. Verify the `Also here:` section now lists BOTH `Garrick the Innkeeper` and `Maelyn the Bard`.
7. Switch to Bob's browser.
8. Verify Bob's log ALSO appended `Maelyn the Bard arrives.` (multi-recipient delivery — FR-011).

**Multi-session check** (FR-014):
- Open browser C in a third incognito session, log in as Alice again (same account, second tab/session).
- Click `Play`.
- From IEx, dispatch another `SpawnNPC` (e.g., a third NPC named "Renn the Apprentice").
- Verify BOTH of Alice's browsers (A and C) receive the arrival entry — multi-session delivery for the same player.

**Zero-broadcast-when-empty** (FR-013):
- Have Alice (browser A) `go north` to the North Corridor.
- Have Bob (browser B) also `go north`.
- From IEx, dispatch a `SpawnNPC` into the Dusty Library (a room neither player occupies).
- Verify neither Alice's nor Bob's log shows any entry — the broadcast fan-out had no recipients on the Library's room topic.
- Have Alice `go south` then `go east` to enter the Library.
- Verify the new NPC appears in the room view's `Also here:` section — the world state correctly reflects the spawn even though no live arrival entry was sent.

## Story 4 — Try to take an NPC (P3, FR-015 / FR-016)

Back in Alice's session in the Stone Atrium:

1. Type `take garrick`.
2. Verify a refusal entry: `You can't take that.`
3. Verify Garrick still appears in the `Also here:` section on the next `look`.
4. Verify Alice's inventory is unchanged (`inventory` shows whatever she had before — Garrick is NOT in it).
5. Type `pick up the innkeeper` (natural-language variant).
6. Verify the same refusal entry: `You can't take that.`
7. Verify Bob's log shows NO entry — no witness entry for failed actions (FR-016).

## Story 1 acceptance scenario 4 — Seeded starter map

```bash
mix ecto.reset
```

1. Tail the server logs and verify `[World.Seed] starter map seeded` appears.
2. Query the DB to confirm the NPC row exists:
   ```bash
   mix ecto.psql -- -c "SELECT id, name, room_id FROM world_npcs;"
   ```
   (Or via IEx: `AgenticRealms.Repo.all(AgenticRealms.World.Schemas.NPC) |> Enum.map(& &1.name)`.)
3. Verify exactly one row, `Garrick the Innkeeper`, in the Stone Atrium's room id.

## Negative tests

**Per-room name collision rejected** (FR-001a):
- From IEx, attempt:
  ```elixir
  WorldApp.dispatch(%SpawnNPC{
    room_id: AgenticRealms.World.Seed.starting_room_id(),
    npc_id: Ecto.UUID.generate(),
    name: "garrick the innkeeper",       # case-insensitive same as the seeded NPC
    short_description: "x",
    long_description: "y"
  })
  ```
- Expect `{:error, :npc_name_taken_in_room}`.

**Same name allowed in different rooms** (FR-001a):
- From IEx, attempt the same dispatch above but with `room_id` set to the North Corridor's id.
- Expect `:ok` — the broadcast fires (to no recipients), the projector inserts, and a follow-up `look` from a player in the Corridor lists the duplicate-name NPC there.

**Unknown room rejected**:
- From IEx, attempt `SpawnNPC` with `room_id: Ecto.UUID.generate()` (random unused UUID).
- Expect `{:error, :room_not_found}`.

**Empty long description rejected** (FR-001):
- From IEx, attempt `SpawnNPC` with `long_description: ""`.
- Expect `{:error, :long_description_required}`.

## Test suite

```bash
mix test
```

All new test files in `test/agenticrealms/world/` and `test/agenticrealms_web/live/game_live_npc_test.exs` should pass. Existing tests should continue to pass — the only modifications to existing test files are additive (new test cases in `room_test.exs`, `queries_test.exs`, `examine_test.exs`, `commands_take_test.exs`, `world_projector_test.exs`, `context_snapshot_test.exs`, `game_live_intent_parser_test.exs`). No prior assertions are changed.
