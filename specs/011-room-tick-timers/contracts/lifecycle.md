# Contract: `AgenticRealms.World.Ticks.Lifecycle` (singleton GenServer)

The 0↔1 transition detector. One process per BEAM node (or one cluster-wide via Horde, deferred — see Scaling note). Subscribes to global presence + room movement events; maintains a per-room live-occupant set; starts/stops schedulers via the supervisor with grace-period absorption of bursts.

## Process registration

Started under the application supervisor with `name: AgenticRealms.World.Ticks.Lifecycle` — a single, fixed name. Not under Horde.

## Init

```elixir
@spec start_link(opts :: keyword()) :: GenServer.on_start()
```

Init body:

1. Read `join_grace_ms`, `leave_grace_ms` from application config.
2. `Phoenix.PubSub.subscribe(AgenticRealms.PubSub, AgenticRealmsWeb.Presence.topic())` — global "connected_players".
3. Start with empty state. Room-topic subscriptions are added on demand.
4. Return `{:ok, state}`.

## Casts

(none)

## Calls

### `:get_state` (test-only)

Returns full state for inspection.

### `{:notify_room_event, room_id, event}` (internal helper, called via test or future infra)

For tests that want to inject a synthesized room event without going through PubSub.

## Info messages

### `%{event: "presence_diff", payload: %{joins: joins, leaves: leaves}}`

Phoenix.Presence broadcasts these on the subscribed topic. Body:

1. For each `player_id` in `joins`: query `Queries.current_room_of(player_id)` (use cache if convenient). If the player has a current room, add `player_id` to `live_per_room[room_id]` and trigger an occupancy-change check for that room.
2. For each `player_id` in `leaves`: walk `live_per_room` and remove the player from each room they were in (typically just one); trigger an occupancy-change check for each affected room.
3. Subscribe to `room_topic(room_id)` for each newly-tracked room (so we receive `PlayerCurrentRoomChanged` for cross-room moves).

### `%RoomPlayerArrived{} = ev`

A player joined room `ev.room_id`. Add `ev.actor_id` to `live_per_room[ev.room_id]` (idempotent). Trigger occupancy-change check.

### `%RoomPlayerLeft{} = ev`

A player left room `ev.room_id`. Remove `ev.actor_id` from `live_per_room[ev.room_id]`. Trigger occupancy-change check.

### `%PlayerCurrentRoomChanged{} = ev`

Player moved from one room to another. Remove from old, add to new; trigger occupancy-change checks for both.

### `{:start_scheduler, room_id}` (self-message from `Process.send_after`)

Body:
1. Re-check `MapSet.size(live_per_room[room_id]) > 0` (defensive — player may have left during grace).
2. If still > 0: `RoomTicks.Supervisor.find_or_start(room_id)`; add `room_id` to `started_schedulers`; clear `pending_join[room_id]`.
3. If 0: do nothing; clear `pending_join[room_id]` (a leave during join grace cancels the start).

### `{:stop_scheduler, room_id}` (self-message)

Body:
1. Re-check `MapSet.size(live_per_room[room_id]) == 0`.
2. If still 0 AND `room_id` is in `started_schedulers`: terminate via `Horde.DynamicSupervisor.terminate_child(RoomTicks.Supervisor, pid)`; remove `room_id` from `started_schedulers`; clear `pending_leave[room_id]`.
3. If > 0: do nothing; clear `pending_leave[room_id]`.

## Occupancy-change check (internal helper)

Called after every event that mutates `live_per_room`:

```elixir
defp occupancy_changed(state, room_id) do
  count = MapSet.size(Map.get(state.live_per_room, room_id, MapSet.new()))
  started? = MapSet.member?(state.started_schedulers, room_id)

  cond do
    count > 0 and not started? ->
      # 0 → ≥1: cancel pending_leave (if any); schedule start
      cancel_timer(state.pending_leave[room_id])
      ref = Process.send_after(self(), {:start_scheduler, room_id}, join_grace_ms())
      put_in(state, [:pending_join, room_id], ref) |> remove_pending_leave(room_id)

    count == 0 and started? ->
      # ≥1 → 0: cancel pending_join (if any); schedule stop
      cancel_timer(state.pending_join[room_id])
      ref = Process.send_after(self(), {:stop_scheduler, room_id}, leave_grace_ms())
      put_in(state, [:pending_leave, room_id], ref) |> remove_pending_join(room_id)

    count > 0 and started? ->
      # already running with occupants — cancel any pending_leave (re-occupancy)
      cancel_timer(state.pending_leave[room_id])
      remove_pending_leave(state, room_id)

    count == 0 and not started? ->
      # nothing to do
      state
  end
end
```

## Scaling note

This module is a **singleton per node** in the MVP. Multi-node consideration: in a clustered deployment, multiple nodes would each independently observe Presence (which IS cluster-replicated) and attempt to start the scheduler. Horde's uniqueness invariant resolves this at the registry level — only one Scheduler can be registered per `room_id`, regardless of how many nodes ask. The redundant `find_or_start` calls are idempotent and harmless beyond a small bit of wasted work. A future feature can elect a leader Lifecycle per cluster if observability/cost becomes a concern.

## Test surface

`LifecycleTest`:

- Initial state: empty `live_per_room`, empty `started_schedulers`, empty `pending_join` / `pending_leave`.
- Presence-diff join for a player whose `current_room_id` is set → `live_per_room[room]` includes the player; a `pending_join[room]` timer is scheduled.
- After `join_grace_ms` of wall time, the scheduler IS started (assertion via `Horde.Registry.lookup`).
- A second join in the same room within the grace period does NOT schedule a second start (idempotent).
- A leave-then-rejoin within `leave_grace_ms` does NOT tear down the scheduler — the pending_leave timer is cancelled.
- A leave with no rejoin: after `leave_grace_ms`, the scheduler IS terminated and removed from the registry.
- `PlayerCurrentRoomChanged` correctly atomically moves the player from one room's set to another, triggering occupancy changes for both rooms.
- Multiple concurrent room transitions don't deadlock or corrupt state.
