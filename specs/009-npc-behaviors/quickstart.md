# Quickstart: NPC and Room Behaviors

Manual end-to-end verification of every user story after this feature ships.

## Prereqs

```bash
mix event_store.reset   # wipe historical events so the new behavior-carrying seed events land cleanly
mix ecto.reset          # rebuild read model + re-run seed
mix phx.server          # localhost:4000
```

The seed log MUST include `[World.Seed] starter map seeded` with no error output.

## Story 1 + 3 — NPC greets a player, room narrates the scene (P1 + P2, SC-001 + SC-007)

Open `http://localhost:4000/` in browser A. Register a fresh player as `alice`. Click `Play`.

The Stone Atrium room view renders. **Within ~200ms of arrival**, the narrative log MUST include both of these entries in this strict order (room first, NPC second, per FR-008a):

1. A `:room_speech` entry rendered as: `The cool air carries the scent of rain.` — italicized, NO actor name, NO quotation marks framing it.
2. A `:npc_speech` entry rendered as: `Garrick the Innkeeper says, "Welcome to the Stone Atrium."` — with attribution and quoted text.

Inspect the rendered HTML (`view-source:` or browser dev tools):
- The `:room_speech` block MUST have class `log-entry narrate narrate-room`.
- The `:npc_speech` block MUST have class `log-entry speech speech-npc`.
- The NPC block contains `<span class="who">Garrick the Innkeeper</span>` — NEVER `Garrick the Innkeeper#1` (FR-011).

## Story 2 — NPC says goodbye, room narrates departure (P1, SC-002)

Continuing in Alice's session, submit `go north`.

The destination room (North Corridor) renders. The behavior-sourced entries fire from the SOURCE room (the Stone Atrium):

1. `:npc_speech` from Garrick: `Garrick the Innkeeper says, "Farewell, traveler."`

Note: the Stone Atrium has NO `player_left` behavior in the seed (we only seeded `player_entered` for the room). So only Garrick speaks on departure. To verify a room-attached `player_left` works, manually add one to the Atrium via IEx and repeat the test — out of scope for the seed but easy to demonstrate.

## Story 3 — Triggering-player-only delivery for `:room_speech`

Open browser B (different incognito session). Register `bob`. Click `Play`. Bob is now in the Stone Atrium with Alice's session also in there (assuming Alice moved back via `s`).

When Bob arrives:
- Bob's log gets the room narration (`The cool air carries the scent of rain.`) AND Garrick's greeting.
- **Alice's log does NOT get the room narration** — `:room_speech` is delivered only to the triggering player (Bob). This is the anti-spam rule from the Q3 clarification.
- Alice's log DOES get Garrick's greeting — `:npc_speech` is delivered to every player in the room (Bob arriving + Alice already present).

Verify by inspecting Alice's session's narrative log — it should contain only ONE `:room_speech` entry (from her own arrival), not two.

## Story 4 — Multi-behavior composition

This isn't directly in the seed, but verifiable via IEx. After the world is up:

```elixir
iex> import Ecto.Query
iex> alias AgenticRealms.World.Schemas.NPCBlueprint
iex> alias AgenticRealms.Repo

iex> # Add a second player_entered behavior to Garrick's blueprint.
iex> Repo.update_all(
...>   from(b in NPCBlueprint, where: b.id == "garrick_the_innkeeper"),
...>   set: [
...>     behaviors: [
...>       %{"trigger" => "player_entered", "actions" => [%{"type" => "say", "text" => "Welcome to the Stone Atrium."}]},
...>       %{"trigger" => "player_entered", "actions" => [%{"type" => "say", "text" => "Mind the loose flagstone by the door."}]},
...>       %{"trigger" => "player_left", "actions" => [%{"type" => "say", "text" => "Farewell, traveler."}]}
...>     ]
...>   ]
...> )
```

**Important caveat (feature 008 full-copy)**: this direct DB mutation updates the BLUEPRINT but does NOT update the existing GARRICK CLONE in the Stone Atrium. To verify the multi-behavior firing, you'd need to spawn a NEW clone of the updated blueprint into a DIFFERENT room (using `Commands.spawn_npc_clone/3`), then trigger an arrival in that room.

For simpler manual testing, mutate the CLONE row directly:

```elixir
iex> alias AgenticRealms.World.Schemas.NPCClone
iex> [clone] = Repo.all(from c in NPCClone, where: c.blueprint_id == "garrick_the_innkeeper")
iex> Repo.update_all(
...>   from(c in NPCClone, where: c.id == ^clone.id),
...>   set: [
...>     behaviors: [
...>       %{"trigger" => "player_entered", "actions" => [%{"type" => "say", "text" => "Welcome to the Stone Atrium."}]},
...>       %{"trigger" => "player_entered", "actions" => [%{"type" => "say", "text" => "Mind the loose flagstone by the door."}]},
...>       %{"trigger" => "player_left", "actions" => [%{"type" => "say", "text" => "Farewell, traveler."}]}
...>     ]
...>   ]
...> )
```

Then move out and back into the Atrium. Garrick should now say two lines on arrival, in the authored order:
1. `Garrick the Innkeeper says, "Welcome to the Stone Atrium."`
2. `Garrick the Innkeeper says, "Mind the loose flagstone by the door."`

## Story 5 — Multi-action composition

Same approach as Story 4, but with a single behavior containing multiple actions:

```elixir
iex> Repo.update_all(
...>   from(c in NPCClone, where: c.id == ^clone.id),
...>   set: [
...>     behaviors: [
...>       %{
...>         "trigger" => "player_entered",
...>         "actions" => [
...>           %{"type" => "say", "text" => "First line."},
...>           %{"type" => "say", "text" => "Second line."}
...>         ]
...>       }
...>     ]
...>   ]
...> )
```

Move out and back. Verify both lines appear in authored order.

## Negative tests

### Behavior firings do NOT replay during read-model rebuild

Verify by IEx:

```elixir
iex> alias AgenticRealms.World.Application, as: WorldApp
iex> alias AgenticRealms.EventStore
iex> # Query the event store directly — check that no BehaviorFired or
iex> # similar events exist after multiple player movements.
iex> EventStore.stream_all_forward()
...> |> Enum.take(50)
...> |> Enum.map(& &1.event_type)
...> |> Enum.filter(&String.contains?(&1, "Behavior"))
[]
```

There should be ZERO events containing the substring `Behavior` in the entire event store. Behavior firings are non-event-sourced (FR-016).

### Disconnection does not fire `player_left`

In Alice's browser, hard-refresh (Cmd-Shift-R). The session disconnects without issuing a movement command. Garrick's `player_left → "Farewell, traveler."` MUST NOT fire — verified by inspecting Alice's previous-session log (if visible) and Bob's log (no farewell appearing in Bob's log when Alice's session drops).

### Validator rejects malformed behaviors at seed time

Edit `Seed.do_seed/0` locally to include a malformed behavior (e.g., wrong trigger atom) and run `mix ecto.reset`. The seed MUST raise with a clear error indicating which validator rule failed.

## Test suite

```bash
mix test                            # all unit tests, including new validator + interpreter tests
mix test --include integration test/agenticrealms_web/live/game_live_behaviors_test.exs
```

Both should pass.

## Operational checklist

For dev workflow when pulling this feature:

```bash
mix deps.get
mix event_store.reset
mix ecto.reset
mix phx.server
```

The combined reset is required because the seeded behaviors are carried in the new `RoomCreated`, `NPCBlueprintCreated`, and `NPCClonedFromBlueprint` event payloads. Replaying the OLD events (from before this feature) produces a world with `behaviors: []` everywhere — functionally correct but the demonstrable seeded behaviors won't be present until the events are re-emitted with the new payloads.
