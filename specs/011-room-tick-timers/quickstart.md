# Quickstart: Room-Scoped Tick Timers (Feature 011)

A small manual smoke test exercising US1–US5. Assumes the feature is implemented, migration is run, and the seed has been applied (Stone Atrium has a tick room behavior, Garrick has a tick NPC behavior, and there's a ticking object in the room).

## Prerequisites

- Postgres running locally.
- `mix ecto.reset` (drops + recreates + migrates + seeds) executed at least once.
- The server running: `mix phx.server`.

## Steps

1. **Login as Alice.** Open `http://localhost:4000` and register a fresh user `alice_smoke` / `password_password`. After login you should land in the Stone Atrium with Garrick the Innkeeper visible. Most importantly: at this point the room scheduler starts (FR-002), and within ~1.25 s (250 ms join grace + 1 s default interval), the first tick-driven action should fire.

2. **(US1) Room ambient tick** — within the first ~1–3 seconds of arrival, observe a `:room_speech` line in your log from the room's tick behavior. The seed should include something like a periodic atmospheric narration ("The cool air carries the scent of rain.") fired by a `tick` trigger on the Stone Atrium. Expect: continued periodic narration at the seeded interval (e.g., every 30 s for ambient narration, every 20 s for Garrick's idle gesture).

3. **(US1) NPC idle tick** — within the same window, observe a `:npc_speech` line from Garrick's idle tick (an `emote`-style "Garrick polishes a tankard." once we add the `emote` action; for MVP, a `:say`-style line if the feature ships with say-only).

4. **(US4) Object tick** — there should be a ticking object in the room (e.g., a brass lantern). Observe its tick behavior firing periodically.

5. **(US4 — carry handoff) Pick up the lantern.**
   ```
   take lantern
   ```
   The lantern's tick behaviors continue firing because you are still in the Stone Atrium. The room scheduler still drives them.

6. **(US4 — room change with carried) Move north with the lantern.**
   ```
   go north
   ```
   The lantern's ticks should:
   - **STOP** in the Stone Atrium (the scheduler drops the object from scope on `RoomPlayerLeft{carried_object_ids: [lantern]}`).
   - **START** in the North Corridor (the new room's scheduler starts if needed and picks up the lantern's ticks).
   Watch for the next tick-driven line — it should appear in your log within ~1–3 s of arriving in the new room.

7. **(US4 — drop) Drop the lantern.**
   ```
   drop lantern
   ```
   The lantern's ticks continue firing — the room's scheduler now drives them via the in-room-objects path instead of the carried-objects path.

8. **(US2 — leave) Go back south.**
   ```
   go south
   ```
   The North Corridor's scheduler stops after the leave grace period (default 5 s) — assuming no other player is there. Watch your log to confirm no further ticks attributed to the lantern (which you left in the North Corridor, but you're no longer there to see them).

9. **(US2 — return) Go north again within the leave grace window.**
   You must do this within 5 seconds of step 8 for the leave grace to be in effect. The scheduler should NOT have been torn down; the lantern's tick cadence should continue from where it left off (drift-free per FR-008 / clarification Q3).

10. **(US5 — config-override sanity)** — outside the smoke test, the operator can verify configurability:
    ```bash
    # In config/dev.exs or via env:
    config :agenticrealms, AgenticRealms.World.Ticks,
      base_tick_rate_ms: 500,
      join_grace_ms: 100,
      leave_grace_ms: 2_000
    ```
    Restart, repeat steps 1–4. Tick cadences are at the new rate; grace periods are tighter.

## Pass criteria

- Within ~1.25 s of arriving in any seeded room, at least one tick-driven log entry appears.
- Tick cadence is consistent across multiple observed fires (drift-free per FR-008).
- Carrying a ticking object across rooms transfers it from one room's scheduler to the next without gaps (within ~1 base tick).
- After leaving a room AND the leave grace expires, no further ticks are emitted for that room.
- Re-entering a room within the leave grace continues the schedule (no "new conversation" / "fresh start" reset).
- An invalid `interval_ms` in any seeded behavior causes a clear, immediate validator error at server startup — server does NOT silently boot with a half-broken behavior.

## Troubleshooting

- **No ticks fire after arrival**: Verify `mix ecto.reset` ran (so the seed's tick behaviors are loaded). Check the scheduler is registered: `iex` → `AgenticRealms.World.Ticks.Registry.lookup(<room_id>)` should return `{:ok, pid}`. If `:error`, check Lifecycle is processing presence events.
- **Tick fires but cadence drifts**: This would be a bug. Capture timestamps and report — the `last_fire + interval` arithmetic should be drift-free.
- **Ticks fire when room is empty**: Lifecycle didn't see the leave event. Check `iex` → `:sys.get_state(AgenticRealms.World.Ticks.Lifecycle)` and inspect `live_per_room` and `started_schedulers`.

## Inspecting state in `iex`

```elixir
# Which rooms have active schedulers?
:sys.get_state(AgenticRealms.World.Ticks.Lifecycle).started_schedulers

# Inspect a specific scheduler's state
{:ok, pid} = AgenticRealms.World.Ticks.Registry.lookup(room_id)
GenServer.call(pid, :get_state)

# Force a scope refresh (test/debug)
GenServer.call(pid, :refresh)
```
