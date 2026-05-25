# Contract: `AgenticRealms.World.Ticks.Scheduler` (per-room GenServer)

The per-room tick scheduler. One process per active room, registered cluster-wide in `RoomTicks.Registry` under key `room_id`. Owns the beat timer, the in-scope tick-behavior set, the per-behavior `last_fire` map, and the dispatch loop. Refreshes scope incrementally on subscribed room events.

## Process registration

```elixir
{:via, Horde.Registry, {AgenticRealms.World.Ticks.Registry, room_id}}
```

## Init

```elixir
@spec start_link(room_id :: String.t()) :: GenServer.on_start()
```

Init body:

1. Read `base_tick_rate_ms`, `join_grace_ms`, `leave_grace_ms` from `Application.get_env(:agenticrealms, AgenticRealms.World.Ticks, [])` with defaults `(1_000, 250, 5_000)`.
2. `Phoenix.PubSub.subscribe(AgenticRealms.PubSub, World.room_topic(room_id))`.
3. Compute initial `in_scope` via `RoomTicks.Scope.compute(room_id)`.
4. Compute initial `live_occupants` via `Queries.live_occupants_of(room_id)` (new helper — players whose `current_room_id == room_id` AND online per Presence).
5. Set `scheduler_start_time = System.monotonic_time(:millisecond)`.
6. Schedule first beat: `Process.send_after(self(), :beat, base_tick_rate_ms)`.
7. Return `{:ok, state}` (no GenServer idle timeout — beat timer drives liveness).

## Calls

### `:refresh` (test-only / emergency)

```elixir
@spec refresh(pid()) :: :ok
def refresh(pid), do: GenServer.call(pid, :refresh)
```

Forces a full recompute of `in_scope` via `Scope.compute/1`. Used by tests to bypass any event-driven cache invalidation; can also be called manually if an event is suspected missed.

### `:get_state` (test-only)

Returns the full state. Used for inspection in unit tests.

## Info messages

### `:beat`

The periodic tick. Body:

1. `now = System.monotonic_time(:millisecond)`.
2. Compute `due = filter_due(in_scope, last_fire, scheduler_start_time, now)` (see below).
3. Sort `due` per FR-008a:
   - Primary: `target_kind` order — `:room` < `:npc` < `:object`
   - Secondary (within NPCs): NPC `target_serial` ascending
   - Secondary (within objects): `target_id` ascending (lexicographic on the binary id)
   - Tertiary (within a single target): `behavior_index` ascending (authored order)
4. For each due entry, **synchronously**:
   - For each action in `entry.actions`:
     - Dispatch via `Behaviors.ActionExecutor.execute(speaker_ctx, action, room_id, _triggering_player_id = nil)`
     - `speaker_ctx` is `{:room, room_id}` for room targets, `{:npc_clone, clone}` for NPCs, or `{:object, object}` for objects
   - Set `last_fire[entry.key] = now`
5. Re-arm: `Process.send_after(self(), :beat, base_tick_rate_ms)`.
6. `{:noreply, new_state}`.

```elixir
defp filter_due(in_scope, last_fire, start, now) do
  Enum.filter(in_scope, fn entry ->
    last = Map.get(last_fire, entry.key, start)
    now - last >= entry.interval_ms
  end)
end
```

### `%RoomPlayerArrived{} = ev`

- Add `ev.actor_id` to `live_occupants`.
- For each id in `ev.carried_object_ids`, fetch the object's behaviors and add tick entries to `in_scope` via `Scope.add_carried_object(in_scope, ev.actor_id, object_id)`.

### `%RoomPlayerLeft{} = ev`

- Remove `ev.actor_id` from `live_occupants`.
- For each id in `ev.carried_object_ids`, remove the corresponding entries from `in_scope` via `Scope.remove_carried_object(in_scope, ev.actor_id, object_id)`.
- Note: the scheduler does NOT terminate itself. Lifecycle decides teardown with grace.

### `%RoomNPCArrived{} = ev` (existing event from feature 007)

- Add NPC's behaviors to `in_scope` via `Scope.add_npc(in_scope, ev.npc_id)`.

### `%RoomNPCLeft{} = ev` (new in this feature)

- Remove NPC's behaviors from `in_scope` via `Scope.remove_npc(in_scope, ev.npc_id)`.
- Drop entries from `last_fire` for that NPC's behaviors (cleanup).

### `%RoomObjectTaken{}` / `%RoomObjectDropped{}`

- No scope change (object stays in this room — just changed possession). State unchanged.
- Future-proofing: if the object's behaviors need carrier-aware speaker context, the dispatch path can read the current owner at fire time.

### Other Phoenix.Presence diff messages

Not subscribed by the scheduler directly — Lifecycle owns Presence subscription. The scheduler relies on RoomPlayerArrived/Left for occupancy changes.

## FR-010 — Skip-stale semantics

If a tick action takes longer than the behavior's interval (a future concern — current actions are synchronous, but feature scope explicitly anticipates async LLM actions):

1. The dispatch path tracks "currently-firing" behaviors via `state.inflight` (a MapSet of behavior keys).
2. On a beat: a behavior whose key is in `inflight` is SKIPPED (not added to `due`).
3. When the action completes, `last_fire[key]` is set to the moment of DISPATCH (not the moment of completion) and the key is removed from `inflight`. Next eligibility is computed from the dispatch time, preserving the FR-008 cadence.

For this feature's MVP, all actions are synchronous (the `:say` action), so `inflight` is a single-beat transient — but the structure is in place for future LLM-bound actions.

## Recipients for tick-fired `:say` (R-007)

| Speaker context | Action | Recipients |
|-----------------|--------|------------|
| `{:room, room_id}` | `:say` | ALL live occupants of `room_id` (fan-out from `room_topic` is NOT used because feature 009's `:room_speech` was per-triggering-player; for tick-driven room speech, we broadcast as `:room_speech` to every live occupant's `player_topic`) |
| `{:npc_clone, clone}` | `:say` | All players in the room, via `room_topic(room_id)` broadcast of `BehaviorUtterance{kind: :npc_speech}` — same as feature 009 |
| `{:object, object}` | `:say` | All players in the room, via `room_topic(room_id)` broadcast (new — feature 009 didn't have object speakers). Attribution uses the object name |

## Test surface

`SchedulerTest`:

- First beat after init does NOT fire any behaviors (interval_ms > base_tick_rate_ms, so nothing is due on the first beat).
- A behavior with `interval_ms == base_tick_rate_ms` fires on the second beat (interval elapsed since `scheduler_start_time`).
- A behavior with `interval_ms == 3 × base_tick_rate_ms` fires every 3rd beat after the first eligibility.
- Drift-free cadence: across 10 fires, consecutive fire intervals are `interval_ms ± dispatch_tolerance` (≤ 20 ms).
- FR-008a ordering: with a room behavior, an NPC behavior, and an object behavior all due on the same beat, fire order is `room → npc → object`. Within multiple room behaviors at the same interval, authored order is preserved.
- `RoomNPCLeft` removes the NPC's behaviors from scope; subsequent beats don't fire them.
- `RoomPlayerLeft` with `carried_object_ids: [obj1]` removes obj1's tick entries from scope; subsequent beats don't fire them.
- `RoomPlayerArrived` with `carried_object_ids: [obj1]` adds obj1's tick entries to scope; subsequent beats fire them.
- `:refresh` recomputes scope from the read side (asserts the full set matches `Scope.compute/1`).
- `:get_state` returns the expected internal shape (asserted against the data-model.md spec).
