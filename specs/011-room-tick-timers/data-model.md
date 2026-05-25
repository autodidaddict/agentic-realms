# Data Model: Room-Scoped Tick Timers (Feature 011)

## 1. Persistent additions

### 1.1 `world_objects.behaviors` (new column)

| Attribute    | Value                                                          |
|--------------|----------------------------------------------------------------|
| Column name  | `behaviors`                                                    |
| Type         | `jsonb`                                                        |
| Constraints  | `NOT NULL DEFAULT '[]'::jsonb`                                 |
| Shape        | Same as feature 009's room/NPC `behaviors`: a JSON array of `{trigger, actions, [interval_ms]}` maps. |
| Audience     | Wizard-authored data. The new `tick` trigger uses `interval_ms`; other triggers ignore it. |
| Inheritance  | Authored directly on the object row. No object blueprint concept in this feature (deferred). |

### 1.2 Event/command extensions (backward-compatible)

Two existing structs get a `behaviors: []` field added to their defstruct (NOT in `@enforce_keys`). Old payloads deserialize with `behaviors = []`.

- `AgenticRealms.World.Commands.PlaceObject` — `field :behaviors, {:array, :map}, default: []`
- `AgenticRealms.World.Events.ObjectPlacedInRoom` — `field :behaviors, {:array, :map}, default: []`

The `ObjectTaken` / `ObjectDropped` event shapes are NOT extended. The object's `behaviors` field is canonical on the read side; carry/drop events reference the object by id and the projector / runtime read the row.

### 1.3 UIEvent extensions (backward-compatible)

Two existing UI events get a `carried_object_ids: []` field added (NOT in `@enforce_keys`). Default `[]`; current consumers ignore.

- `AgenticRealms.World.UIEvents.RoomPlayerArrived` — `carried_object_ids: []`
- `AgenticRealms.World.UIEvents.RoomPlayerLeft` — `carried_object_ids: []`

Per R-008: schedulers listen for these and adjust their object-scope subset when a player moves rooms while carrying ticking objects.

One new UI event type:

- `AgenticRealms.World.UIEvents.RoomNPCLeft` — keys: `room_id`, `npc_id`, `npc_name`. Mirrors `RoomNPCArrived` from feature 007. Added in this feature for forward-compatibility (R-009); production emission point follows whenever NPC despawn ships.

### 1.4 Migration: `add_object_behaviors_column.exs`

```elixir
defmodule AgenticRealms.Repo.Migrations.AddObjectBehaviorsColumn do
  use Ecto.Migration

  def change do
    alter table(:world_objects) do
      add :behaviors, :map, null: false, default: %{}
      # Note: Ecto's :map => Postgres jsonb. Default must be set in SQL
      # via execute for jsonb default; see actual migration template below.
    end
  end
end
```

(Final migration uses `add :behaviors, :jsonb, null: false, default: fragment("'[]'::jsonb")` — full template in `tasks.md`.)

### 1.5 Atom-table preservation

The `behaviors` JSONB content uses string keys at the Ecto layer but **atom** keys after EventStore deserialization (Jason `keys: :atoms!`). Feature 009 pre-declared `:trigger`, `:actions`, `:type`, `:text` in `Application.__behavior_atoms__/0`. This feature ADDS:

- `:interval_ms`

to that list. Without this, the EventStore's notification publisher would crash on the first `ObjectPlacedInRoom` event that carries a tick behavior.

---

## 2. Volatile (non-persistent) entities

### 2.1 `AgenticRealms.World.Ticks.Scheduler` (GenServer state)

| Field                  | Type                                                       | Notes |
|------------------------|------------------------------------------------------------|-------|
| `room_id`              | `String.t()`                                               | The room this scheduler serves. Registry key. |
| `base_tick_rate_ms`    | `integer()`                                                | Cached at init from `Application.get_env`. Drives the periodic `:beat` message. |
| `scheduler_start_time` | `integer()` (monotonic ms)                                 | When `init/1` returned. Used as the "never-fired" fallback for behaviors whose `last_fire` is `nil`. |
| `in_scope`             | `[behavior_entry()]`                                       | Ordered list of in-scope tick behaviors (see §2.2). Refreshed incrementally on scope-changing events. |
| `last_fire`            | `%{behavior_key() => integer()}`                           | Per-behavior last-fire monotonic timestamp. Missing key means "never fired since scheduler start." |
| `inflight`             | `MapSet.t(behavior_key())`                                 | Set of behaviors whose action is currently dispatching (used for FR-010 skip-stale). |
| `leave_grace_ref`      | `reference() | nil`                                        | Timer ref for the scheduled-but-pending teardown after 1→0 transition. `nil` while occupied. |
| `live_occupants`       | `MapSet.t(integer())`                                      | Player ids of live occupants in this room. Drives the "no-occupants" path. |

#### `behavior_entry()`

```elixir
@type behavior_entry :: %{
        target_kind: :room | :npc | :object,
        target_id: String.t() | integer(),
        target_serial: integer() | nil,         # NPC serial for ordering; nil for room/object
        behavior_index: non_neg_integer(),       # position in target's behaviors list
        interval_ms: pos_integer(),
        actions: [map()]
      }
```

#### `behavior_key()`

```elixir
@type behavior_key :: {target_kind :: atom(), target_id :: term(), behavior_index :: non_neg_integer()}
```

#### State transitions

```text
init(room_id)
  │
  ├─ compute initial in_scope via Scope.compute(room_id)
  ├─ subscribe to PubSub topics: room_topic(room_id) + connected_players
  ├─ set scheduler_start_time = now
  ├─ Process.send_after(self(), :beat, base_tick_rate_ms)
  ▼
running
  │
  ├─ handle_info(:beat, state)
  │     │
  │     │ now = System.monotonic_time(:millisecond)
  │     │ due = filter in_scope where (now - (last_fire[key] || start)) >= interval_ms AND not inflight
  │     │ sorted = sort due by FR-008a (target_kind, target_serial, target_id, behavior_index)
  │     │ for each due behavior:
  │     │   put inflight (during dispatch — released synchronously since current actions are not LLM-bound)
  │     │   dispatch via Behaviors.ActionExecutor (recipients per R-007)
  │     │   last_fire[key] = now
  │     │   remove from inflight
  │     │ re-arm Process.send_after(self(), :beat, base_tick_rate_ms)
  │     ▼
  │
  ├─ handle_info(%RoomPlayerArrived{} = ev, state)
  │     │ live_occupants ← MapSet.put(live_occupants, ev.actor_id)
  │     │ in_scope ← Scope.add_player_carried(in_scope, ev.actor_id, ev.carried_object_ids)
  │     │ if leave_grace_ref != nil: Process.cancel_timer; leave_grace_ref ← nil
  │     ▼
  │
  ├─ handle_info(%RoomPlayerLeft{} = ev, state)
  │     │ live_occupants ← MapSet.delete(live_occupants, ev.actor_id)
  │     │ in_scope ← Scope.remove_player_carried(in_scope, ev.actor_id, ev.carried_object_ids)
  │     │ (Lifecycle module handles teardown, not the scheduler itself)
  │     ▼
  │
  ├─ handle_info(%RoomNPCArrived{} = ev, state)
  │     │ in_scope ← Scope.add_npc(in_scope, ev.npc_id)  -- queries DB for the NPC's behaviors
  │     ▼
  │
  ├─ handle_info(%RoomNPCLeft{} = ev, state)
  │     │ in_scope ← Scope.remove_npc(in_scope, ev.npc_id)
  │     │ last_fire ← drop keys for that NPC's behaviors
  │     ▼
  │
  ├─ handle_info(%RoomObjectTaken{} = ev, state)
  │     │ // object's behaviors stay in scope — they just moved from "in room" to "carried by player in room"
  │     │ (in_scope unchanged; carrier-id annotation updated for future move tracking)
  │     ▼
  │
  ├─ handle_info(%RoomObjectDropped{} = ev, state)
  │     │ // mirror image of ObjectTaken — same scope, different carrier annotation
  │     ▼
  │
  └─ handle_call(:refresh, _from, state)   // emergency / test only
        state ← state | in_scope: Scope.compute(room_id)
```

Note: the scheduler does NOT terminate itself on `RoomPlayerLeft`. The Lifecycle module owns teardown decisions (with grace).

### 2.2 `AgenticRealms.World.Ticks.Lifecycle` (singleton GenServer state)

| Field              | Type                                       | Notes |
|--------------------|--------------------------------------------|-------|
| `live_per_room`    | `%{room_id => MapSet.t(player_id)}`        | Authoritative "live players per room" — built from Presence diffs + room movement events. |
| `pending_join`     | `%{room_id => reference()}`                | Pending 0→1 join-grace timers. Key absent if no pending join. |
| `pending_leave`    | `%{room_id => reference()}`                | Pending 1→0 leave-grace timers. Key absent if no pending leave. |
| `started_schedulers` | `MapSet.t(room_id)`                      | Rooms with currently-running schedulers. |

#### Behavior

- Subscribes on init to `connected_players` Presence topic and to all `room_topic`s lazily (subscribes to `room_topic(room_id)` the first time a room becomes a candidate for ticking).
- Handles `%{event: "presence_diff"}` messages: maps joins → "player_id is now online"; maps leaves → "player_id is now offline." For each, looks up the player's `current_room_id` and updates `live_per_room`.
- Handles `RoomPlayerArrived` / `RoomPlayerLeft` / `PlayerCurrentRoomChanged` UI events: updates `live_per_room` for the relevant rooms.
- On EACH update, recomputes the affected room's `MapSet.size(live_per_room[room_id])` and triggers the lifecycle path:
  - **0 → ≥1**: cancel any pending_leave for this room; if no scheduler is started, set `pending_join[room_id] = Process.send_after(self(), {:start_scheduler, room_id}, join_grace_ms)`.
  - **≥1 → 0**: cancel any pending_join for this room; if a scheduler IS started, set `pending_leave[room_id] = Process.send_after(self(), {:stop_scheduler, room_id}, leave_grace_ms)`.
- `handle_info({:start_scheduler, room_id}, state)`:
  - Re-check size > 0 (defensive); if still > 0, call `RoomTicks.Supervisor.find_or_start(room_id)`; add `room_id` to `started_schedulers`; clear `pending_join[room_id]`.
- `handle_info({:stop_scheduler, room_id}, state)`:
  - Re-check size == 0; if still 0, terminate the scheduler via `Horde.DynamicSupervisor.terminate_child(RoomTicks.Supervisor, pid)`; remove `room_id` from `started_schedulers`; clear `pending_leave[room_id]`.
- Survives node restarts cleanly: starts with empty state; Presence + room subscriptions repopulate state as events arrive.

### 2.3 `AgenticRealms.World.Ticks.Scope` (pure module)

```elixir
@spec compute(room_id :: String.t()) :: [behavior_entry()]
def compute(room_id) do
  # Queries:
  #   - Room.behaviors filtered to trigger==tick
  #   - All NPCClone.behaviors for clones with current_room_id == room_id, filtered to trigger==tick
  #   - All Object.behaviors for objects with room_id == room_id, filtered to trigger==tick
  #   - All Object.behaviors for objects carried by any player whose current_room_id == room_id, filtered to trigger==tick
  #   - All Object.behaviors for objects carried by any NPC in this room (currently NPCs don't carry inventory — placeholder for future feature; returns [] today)
  # Returns a list of behavior_entry() sorted per FR-008a.
end

@spec add_npc([behavior_entry()], npc_id :: String.t()) :: [behavior_entry()]
@spec remove_npc([behavior_entry()], npc_id :: String.t()) :: [behavior_entry()]
@spec add_player_carried([behavior_entry()], player_id :: integer(), [object_id :: String.t()]) :: [behavior_entry()]
@spec remove_player_carried([behavior_entry()], player_id :: integer(), [object_id :: String.t()]) :: [behavior_entry()]
```

Pure (DB-bound on `compute/1`; pure list ops on the incremental helpers).

---

## 3. Validation rules

Per FR-005 / clarification Q5, the existing `AgenticRealms.World.Behaviors.Validator.validate/1` gains:

- `"tick"` added to the known-trigger whitelist.
- A new validation clause: when `trigger == "tick"`, the behavior map MUST have an `interval_ms` field that is:
  - **present** (not omitted, not `nil`)
  - **an integer** (not a float, not a string, not anything else)
  - **positive** (`> 0`)
  - **a positive integer multiple of the base tick rate** (read from `Application.get_env(:agenticrealms, AgenticRealms.World.Ticks, [])[:base_tick_rate_ms] || 1000`)
- Failure shapes:
  - `{:error, {:invalid_tick_interval, %{reason: :missing}}}`
  - `{:error, {:invalid_tick_interval, %{reason: :non_integer, value: ...}}}`
  - `{:error, {:invalid_tick_interval, %{reason: :non_positive, value: ...}}}`
  - `{:error, {:invalid_tick_interval, %{reason: :non_multiple, value: ..., base_rate: ...}}}`

---

## 4. Identity and uniqueness

- **Scheduler key** = `room_id`. One scheduler per room, cluster-wide (Horde.Registry `keys: :unique`).
- **Lifecycle** = singleton, started under the application supervisor with a fixed name (`AgenticRealms.World.Ticks.Lifecycle`). Multi-node future is left to a leader-election feature; single-node is the supported configuration in this feature.
- **Behavior key** = `{target_kind, target_id, behavior_index}` — uniquely identifies a tick behavior across the cluster.

---

## 5. Relationships

```text
Room ──── 1 ─── 0..1 RoomTicks.Scheduler  (lifecycle: 0..1 — exists only while live-occupied)
                              │
                              │ scope tracks:
                              ▼
              ┌───────────────┼────────────────┬────────────────────┐
              ▼               ▼                ▼                    ▼
       Room.behaviors    NPCClone(s) in    Object(s) in room    Object(s) carried by
       (trigger==tick)   room (their       (their behaviors,     live occupants
                         behaviors,        trigger==tick)        (their behaviors,
                         trigger==tick)                          trigger==tick)
```

Lifecycle and Scheduler are non-persistent. The four data sources (`Room.behaviors`, `NPCClone.behaviors`, `Object.behaviors`, `Object.behaviors via inventory`) are persistent.

---

## 6. Data volume / scale

- Per-room scheduler: a few hundred bytes of state + small lists/maps proportional to in-scope behavior count.
- Cluster-wide schedulers: bounded by `number of currently-occupied rooms` (NOT all rooms).
- Lifecycle: O(R) where R is the number of CANDIDATE rooms (rooms that have ever had occupancy in this session). Each entry is a small MapSet.

---

## 7. Non-data invariants

- **No event sourcing for tick state**. Schedulers, scope, and last-fire timestamps are all volatile.
- **Restart safety**: schedulers come back as players reconnect (FR-011) — no snapshot reconstruction.
- **Privacy / delivery invariance** (FR-013): tick-fired actions deliver via the same channels their event-triggered counterparts use; the only divergence is the recipient set for tick-fired room-source `:say`, which fans out to ALL live occupants (R-007).
