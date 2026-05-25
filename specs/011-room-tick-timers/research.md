# Research: Room-Scoped Tick Timers (Feature 011)

Resolves the open technical questions raised by the spec and planning input. Each decision records rationale + rejected alternatives.

## R-001: Lifecycle detection — how does the system detect 0↔1 live-occupancy transitions per room?

**Context**: Per clarification Q2, "occupant" means a player with an active Phoenix.Presence entry currently in the room (live session). The naive options:

- (a) Subscribe to Presence diffs on a per-room topic (each player tracks themselves in `room:<id>` topic on mount)
- (b) Subscribe to the existing `connected_players` global Presence topic, plus listen for movement events; recompute affected rooms' live-counts on each event
- (c) Subscribe to per-room movement events (`RoomPlayerArrived`, `RoomPlayerLeft`, `PlayerCurrentRoomChanged`) plus disconnect signals; do not use Presence diffs directly

**Decision**: **(b)** — Single `Lifecycle` GenServer subscribes to (i) `Phoenix.Presence` on `"connected_players"` and (ii) the per-room movement UI events that GameLive already broadcasts on `room_topic`. On each relevant event, it consults a small in-memory map `%{room_id => MapSet.of(player_ids)}` of "live players currently in this room" and detects 0↔1 transitions.

**Rationale**:
- The `connected_players` Presence topic already drives feature 003b's offline-filter (only online players appear in look output). Reusing it means lifecycle and "who's visible in look" agree by construction — no new source of truth.
- Per-room presence (option a) would require every player to track themselves on a separate per-room topic, plus untrack/re-track on every move. That's another LiveView-side responsibility and more state to keep coherent.
- Movement-event-only (option c) misses disconnects that don't fire a movement event (a player just closes the tab — they ARE still in their last room per `PlayerState`, but their Presence entry vanishes). We need both signals.
- The single-singleton supervisor pattern matches Phoenix.Tracker / Phoenix.PubSub idioms.

**Alternatives considered**:
- **Phoenix.Tracker** with per-room topics — feature-similar to (a), heavier per-LiveView-mount work.
- **PlayerState-only** (option c without Presence) — would require synthesizing disconnect events from elsewhere; we already have the Presence signal for free.

**Implementation notes**:
- `RoomTicks.Lifecycle` is a singleton GenServer (started under the application supervisor with a known name).
- Subscribes on init to `Phoenix.PubSub.subscribe(AgenticRealms.PubSub, "connected_players")` and to every existing room_topic that has potentially-relevant events (room subscriptions are added on demand, see implementation notes for R-002).
- Holds state: `%{room_id => MapSet.t(player_id)}` of live occupants per room, plus a `%{room_id => grace_timer_ref}` for leave-grace timers, plus an indicator of "scheduler started for this room yet?" boolean.
- On 0→1 (room's live-count transitions to ≥1): sets a `Process.send_after(self(), {:start_scheduler, room_id}, join_grace_ms)`; on the timer fire, calls `RoomTicks.Supervisor.find_or_start(room_id)`.
- On 1→0 (room's live-count drops to 0): sets a `Process.send_after(self(), {:stop_scheduler, room_id}, leave_grace_ms)`; on the timer fire, re-checks count, if still 0 calls `Horde.DynamicSupervisor.terminate_child` on the scheduler.
- Re-entry within the leave grace: cancel the pending `:stop_scheduler` timer; scheduler stays alive.

---

## R-002: Scope tracking — when does the scheduler refresh its in-scope behavior set?

**Context**: The scheduler's "in-scope" set is the union of: the room's behaviors, all NPCs currently in the room's behaviors, all objects in the room's behaviors, and all objects carried by live occupants OR by NPCs currently in the room's behaviors. This set CHANGES as players come and go, NPCs spawn/despawn, objects are taken/dropped, and players move rooms while carrying objects.

Two strategies:
- (a) Query the read-side database at every beat to recompute the scope set
- (b) Cache the scope set in scheduler state and refresh incrementally on observed events

**Decision**: **(b)** — Maintain a cached scope set; refresh incrementally on subscribed events.

**Rationale**:
- A 1-second base tick rate means up to 1 scope query per active room per second. For active player counts > 50 with several active rooms, that's a noisy database load for data that changes ~rarely.
- Event-driven cache invalidation is the established pattern for Phoenix projects (Presence, projections, etc.) and reuses the existing UIEvents emitted on `room_topic`.
- The events that matter are already emitted: `RoomPlayerArrived` / `RoomPlayerLeft`, `RoomNPCArrived`, `RoomObjectTaken` / `RoomObjectDropped`, `PlayerCurrentRoomChanged`. New events for NPC despawn and carried-object-moves-room are minor extensions.

**Alternatives considered**:
- **(a) Query per beat**: simpler code, but burns DB ops scaling with active rooms × base rate. Rejected on perf.
- **Hybrid (query every N beats, event-driven in between)**: complexity without clear benefit; the event-driven cache is exact when events are complete.

**Implementation notes**:
- `RoomTicks.Scheduler` builds its initial scope set on `init/1` by calling `RoomTicks.Scope.compute(room_id)` (one query against the read side).
- After init, the scheduler subscribes to its `room_topic` and to a small set of cross-room events that affect carried-object scope:
  - `RoomPlayerArrived` / `RoomPlayerLeft` — refresh live-occupant set and the carried-object subset
  - `RoomNPCArrived` — add NPC behaviors to scope
  - (new) `RoomNPCLeft` — remove NPC behaviors from scope (emitted from the existing despawn path)
  - `RoomObjectTaken` — object's behaviors move with the carrier; if carrier is in this room, scope unchanged
  - `RoomObjectDropped` — same
  - `PlayerCurrentRoomChanged` — if player is carrying ticking objects and leaves this room, drop those behaviors from scope; if player enters this room with ticking objects, add them
- The scheduler exposes a `:refresh` cast for emergency full-recompute (used by tests and as a safety net if any event is missed).
- Scope set shape: a list of `{target_kind, target_id, behavior_index, behavior_map}` tuples. The `behavior_index` (list position) plus `target_id` give the deterministic ordering of FR-008a.

---

## R-003: Beat scheduling — how does the scheduler advance time?

**Context**: Per FR-008 / clarification Q3, the scheduler uses `next_fire = last_fire_time + interval_ms`. We need a periodic mechanism to wake the scheduler and let it evaluate due behaviors. Standard options:

- (a) `Process.send_after(self(), :beat, base_tick_rate_ms)` — re-armed at the end of each beat
- (b) `:timer.send_interval/2` — fires repeatedly at the configured rate
- (c) A `Process.send_after` keyed per behavior to the behavior's NEXT due time — no shared base beat, each behavior schedules itself

**Decision**: **(a)** — A single shared base-rate beat timer per scheduler, re-armed in `handle_info(:beat, ...)`.

**Rationale**:
- The base tick rate IS the minimum granularity of the system per FR-004 / FR-005. There's no need to fire more often than once per base beat; on each beat we evaluate all in-scope behaviors and fire any that are due.
- Re-arming via `Process.send_after` (option a) gives the scheduler natural backpressure: if a beat's work takes longer than the base rate, the next beat is scheduled from the end of the current handler, so we don't pile up. This dovetails naturally with FR-010's skip-stale rule.
- `:timer.send_interval` (option b) is fire-and-forget and CAN queue messages if the handler is slow — exactly the pile-up FR-010 forbids.
- Per-behavior `send_after` (option c) is more complex (every behavior owns its own timer; cancellation on scope change is fiddly) and gains nothing because we already need to wake on every base beat for FR-008's "evaluate all due behaviors" semantics.

**Alternatives considered**:
- **`:timer.send_interval`**: simpler at first; rejected for the queue-on-slowness behavior that violates FR-010.
- **Per-behavior `send_after`**: more granular but conflicts with the shared-beat clarification (FR-004 — the base rate IS the cadence).

**Implementation notes**:
- `init/1` schedules the first beat via `Process.send_after(self(), :beat, base_tick_rate_ms)`. The scheduler's `last_fire_time` map is empty at init.
- `handle_info(:beat, state)`:
  1. Capture `now = System.monotonic_time(:millisecond)`.
  2. For each in-scope tick behavior, if `now - (last_fire_time[behavior_key] || scheduler_start_time) >= interval_ms`, mark it as due.
  3. Sort due behaviors by FR-008a ordering (target_kind → target_serial/id → list_position).
  4. For each due behavior, dispatch its actions via `Behaviors.ActionExecutor` AND update `last_fire_time[behavior_key] = now`.
  5. Re-arm the next beat: `Process.send_after(self(), :beat, base_tick_rate_ms)`.
  6. Return `{:noreply, new_state}`.
- The `scheduler_start_time` field serves as the "never-fired" fallback in step 2 so behaviors fire on `scheduler_start + interval_ms`, not on `scheduler_start + base_rate_ms` (their interval might be a multiple > 1 of the base rate).

---

## R-004: Validator extension — extend the existing `Behaviors.Validator` or add a new tick-aware validator?

**Context**: Feature 009 introduced `AgenticRealms.World.Behaviors.Validator` with a closed vocabulary (`@valid_triggers ~w(player_entered player_left)`). This feature adds `tick` to the trigger set plus a new required field (`interval_ms`).

**Decision**: **Extend the existing validator**. Add `"tick"` to the valid-trigger set and add a new validation clause that runs only when `trigger == "tick"`, checking the `interval_ms` field per FR-005 / Q5.

**Rationale**:
- One source of truth for behavior validation across the project. A second validator would force every caller (seed, Object creation, NPCBlueprint creation, Room creation) to choose which validator to use.
- The trigger-specific validation is a small clause inside the existing per-behavior loop. The validator's signature stays the same: `validate/1 :: :ok | {:error, atom | tuple}`.
- The base tick rate (needed to verify "positive multiple of base rate") is read from application config at validation time. This is consistent with how feature 009's max-text-length is currently a module constant — we make it config-driven.

**Implementation notes**:
- Update `@valid_triggers` to `~w(player_entered player_left tick)`.
- Add `validate_tick_interval/2` private helper invoked when `Map.get(behavior, "trigger") == "tick"`. Reads base rate via `Application.get_env(:agenticrealms, AgenticRealms.World.Ticks, [])[:base_tick_rate_ms] || 1_000`.
- Error tuple shape: `{:error, {:invalid_tick_interval, %{behavior: ..., reason: :missing | :non_integer | :non_positive | :non_multiple, value: ..., base_rate: ...}}}` so callers can format actionable error messages.
- Existing valid-trigger error tuple shape is reused for the unknown-trigger path; `tick` now joins the known set.

---

## R-005: Object schema extension — same plumbing as features 008/009/010, or anything different?

**Context**: Per clarification Q1 / FR-017, objects gain a `behaviors` JSONB field. The pattern is well-rehearsed: schema field, command field, event field, aggregate-or-direct-projection, validator integration, atom-table pre-declaration.

**Decision**: Same plumbing as `behaviors` for Room (feature 009) and `lore` for NPCs (feature 010), with the wrinkle that there's no aggregate for Objects — `PlaceObject` is dispatched directly and `ObjectPlacedInRoom` is the event.

**Rationale**: No new architecture; the smaller surface (no blueprint inheritance, no aggregate full-copy) actually makes Object's plumbing simpler than NPCs'.

**Implementation notes**:
- Migration: `add_object_behaviors_column.exs` adds `behaviors JSONB NOT NULL DEFAULT '[]'::jsonb` to `world_objects`.
- `lib/agenticrealms/world/commands/place_object.ex`: add `behaviors: []` to defstruct.
- `lib/agenticrealms/world/events/object_placed_in_room.ex`: add `behaviors: []` to defstruct (NOT in `@enforce_keys` — backward compat).
- Wherever `PlaceObject` is dispatched (the aggregate or direct dispatcher), the `behaviors` field is passed through into the event.
- `lib/agenticrealms/world/projections/world_projector.ex`: `handle/2` clause for `ObjectPlacedInRoom` adds `behaviors: behaviors || []` to the `%Object{}` insert.
- `lib/agenticrealms/world/schemas/object.ex`: `field :behaviors, {:array, :map}, default: []`.
- Application's `@_behavior_atoms` already includes `:trigger, :actions, :type, :text`; we add `:interval_ms` to that list since tick behaviors now use it.
- Backward-compat replay test mirrors feature 009/010's pattern.

**Note**: The aggregate-vs-direct-projection split: feature 003's PlaceObject path goes Aggregate (`AgenticRealms.World.Room` if present, or direct dispatch). The exact insertion site is determined by looking at how `behaviors` got plumbed in 009 for Room. We mirror that exactly.

---

## R-006: Cluster correctness — Horde reuse vs. anything new?

**Context**: Feature 010 added `Horde.Registry` (for `NPCChat.Conversation` per-player-NPC keys) and `Horde.DynamicSupervisor`. This feature adds another distributed registry (per-room) and another distributed supervisor (for room schedulers).

**Decision**: **Two new Horde processes**: `RoomTicks.Registry` (`keys: :unique`, `members: :auto`) and `RoomTicks.Supervisor` (`Horde.DynamicSupervisor`, `members: :auto`, `distribution_strategy: Horde.UniformDistribution`). They are siblings of the feature-010 NPCChat triad in the application supervision tree.

**Rationale**:
- Conceptually separate registries: one keys by `{player_id, npc_clone_id}` (conversation), the other by `room_id` (tick scheduler). Sharing a single registry would force conditional keying logic and risk collisions.
- Horde is already in the project — no new dep.
- `Lifecycle` is NOT under Horde — it's a singleton, not per-key. It runs under the normal Application supervisor with a fixed registered name. (Multi-node lifecycle is left as a future hardening; in a single-node deployment, one Lifecycle observes all rooms. For multi-node, a future feature can elect a leader or shard rooms across nodes.)

**Implementation notes**:
- `RoomTicks.Registry`, `RoomTicks.Supervisor`, `RoomTicks.Lifecycle` are the three new children added to `AgenticRealms.Application`.
- `RoomTicks.Supervisor.find_or_start(room_id)`: looks up the registry, returns the existing pid if registered; otherwise starts a child via `Horde.DynamicSupervisor.start_child/2`. Same shape as `NPCChat.Supervisor.find_or_start/2`.
- The Scheduler's `init/1` arg is `room_id` (a binary). The scheduler immediately queries the read side to populate scope and starts the beat timer.

---

## R-007: How are tick action dispatches wired into the existing `BehaviorUtterance` paths?

**Context**: Feature 009's `ActionExecutor.execute/4` takes `(speaker_ctx, action, room_id, triggering_player_id)`. For tick-triggered actions, there is **no triggering player** — the player_entered/player_left model doesn't apply.

**Decision**: Pass `triggering_player_id: nil` (or a new `:tick` atom) for tick-driven dispatches. Audit `ActionExecutor` and `Interpreter` for any code paths that assume a player id; ensure they degrade gracefully (e.g., room_speech currently goes to triggering_player_id only — for tick, room_speech should go to ALL live occupants).

**Rationale**:
- Per FR-013, ticks don't change action visibility — but feature 009's `:room_speech` was scoped to triggering_player_id specifically for player-entered narration ("you arrive; the room narrates AT you"). For a tick-fired room narration, there's no triggering player — every live occupant should see it (it's the room ambient layer for everyone present).
- This is a meaningful semantic divergence that needs to be encoded.

**Implementation notes**:
- Tick-fired `:say` from a **room** target → broadcast `BehaviorUtterance{kind: :room_speech}` to EVERY live occupant of the room (not just one player). The existing `:room_speech` rendering is unchanged.
- Tick-fired `:say` from an **NPC** target → broadcast `BehaviorUtterance{kind: :npc_speech}` exactly as today (room channel; everyone present sees it).
- Tick-fired `:say` from an **object** target → use the room channel as well, attributed by object name (e.g., "The brass lantern flickers and says, 'Hello.'"). NOTE: a future emote/narrate action will be the more natural fit for object ticks; `:say` is included for parity but wizards will typically pair object ticks with non-say actions when that vocabulary lands.
- `ActionExecutor` signature: extend to `execute(speaker_ctx, action, room_id, triggering_player_id_or_nil)`. The recipients-of-:room_speech rule fans out to live occupants when `triggering_player_id_or_nil == nil`.

This is the only behavior change to feature 009's substrate.

---

## R-008: Carried-object scope handoff on `PlayerMoved`

**Context**: US4 says when a player carrying a ticking object moves rooms, the object's tick behavior STOPS in the old room and STARTS in the new room. This means **two schedulers** are involved per player-move event.

**Decision**: Each scheduler subscribes to `PlayerCurrentRoomChanged` events globally (via the `connected_players`-side topic isn't right; we want a player-room-change broadcast). The existing `PlayerCurrentRoomChanged` UI event is broadcast on the chatting player's `player_topic` only, NOT broadcast cluster-wide. We need a separate signal.

**Decision (concrete)**:
- The Lifecycle module observes `PlayerCurrentRoomChanged` events (subscribing on init to the player_topic of every live player? Too noisy.) → BETTER: extend the existing `RoomPlayerArrived` / `RoomPlayerLeft` events to include `carried_object_ids` (the ids of objects the player is carrying at the time of the move). The destination room's scheduler sees `RoomPlayerArrived{carried_object_ids: [...]}` and adds those objects' behaviors to scope. The source room's scheduler sees `RoomPlayerLeft{carried_object_ids: [...]}` and removes them.
- Plumbing this through requires extending the two UIEvent structs with a `carried_object_ids: []` field. Backward-compatible: default empty list; current consumers ignore the field.

**Rationale**: Reuses the existing room-scoped event channel that schedulers already subscribe to. Avoids a new global "player moved" channel. Atomically pairs the move with the carried inventory at the time of move.

**Implementation notes**:
- Extend `RoomPlayerArrived` and `RoomPlayerLeft` structs with `carried_object_ids: []` (in `lib/agenticrealms/world/ui_events.ex`).
- The code that emits these (in `GameLive.handle_move/3` and the Movement command path) populates `carried_object_ids` by querying `Queries.list_inventory(player_id)` and mapping to ids. This is one DB query per move — negligible.
- Schedulers consume these on subscribe; `Scope.refresh_on_player_event/2` updates the in-scope set accordingly.

---

## R-009: NPC despawn / removal event

**Context**: US4 acceptance scenario "NPC despawn mid-tick" requires the scheduler to drop the NPC's behaviors from scope when the NPC is removed. Feature 007 added NPC spawn events but no despawn event yet (NPCs in the project don't yet despawn — they're persistent in the seeded room).

**Decision**: Add a `RoomNPCLeft` UI event (mirror of `RoomNPCArrived` from feature 007) and emit it when an NPC clone is deleted. For this feature, the despawn path is hypothetical — there's no command to despawn an NPC yet — so the event type is ADDED but the emission path is left for whichever feature actually adds despawn. The scheduler's subscription is in place from day one so when despawn does land, ticks automatically respect it.

**Rationale**: Future-proofing without speculative implementation. The scheduler's code path for "NPC left scope" is exercised by tests using a synthesized `RoomNPCLeft` event; production wiring can be added in the despawn feature.

**Implementation notes**:
- Add `AgenticRealms.World.UIEvents.RoomNPCLeft` struct with keys `:room_id`, `:npc_id`, `:npc_name`.
- The scheduler's `handle_info(%RoomNPCLeft{} = ev, state)` removes the NPC's behaviors from `state.in_scope`.
- A test in `scheduler_test.exs` synthesizes the event and asserts the NPC's tick behaviors stop firing.

---

## R-010: Test strategy — fast cadence overrides, deterministic dispatch

**Context**: Tick tests need to verify scheduled behavior firing without the test wall-clock duration becoming proportional to the production base rate.

**Decision**:
- `config/test.exs` overrides `base_tick_rate_ms: 50`, `join_grace_ms: 10`, `leave_grace_ms: 50`. A test asserting "fires every 100ms" runs in well under a second.
- Tests use `assert_receive` with reasonable timeouts (e.g., 500 ms) for tick-driven UI events broadcast on subscribed topics.
- For drift-free cadence tests: capture timestamps of each fired tick, assert that consecutive intervals are within a tolerance window (e.g., `interval ± 20ms`) — the system monotonic clock is well-behaved on test hardware.
- Action dispatch is verified by subscribing to the appropriate PubSub topic (room_topic or player_topic depending on the action's kind) and asserting the expected `BehaviorUtterance` / `RoomUtterance` arrives.
- Long-running action tests (FR-010 skip-stale) use a stub action that sleeps deliberately past the interval and assert that the next eligible fire happens AFTER the sleep returns (not concurrently).

**Rationale**: Reuses the test patterns established in features 009 (`interpreter_test.exs`) and 010 (`conversation_test.exs`). No new test infrastructure required.

**Implementation notes**:
- A small test helper `AgenticRealms.Test.TickHelpers.start_scheduler(room_id)` for unit tests that bypass `Lifecycle` and start a scheduler directly under a test-owned supervisor.
- The integration test follows feature 010's single comprehensive test pattern: one `@moduletag :integration` test that exercises US1–US5 in sequence on a seeded room.

---

## R-011: Backward compatibility for the Object `behaviors` field

**Context**: Same as features 009 and 010 — old events without the new field must project cleanly.

**Decision**: Same approach. `defstruct` default `[]`; old events deserialize with `[]`; projector reads from event payload with `behaviors || []`.

**Implementation notes**:
- Replay test mirrors feature 010's `world_projector_npc_replay_test.exs` pattern.
- No migration data backfill needed — existing rows take the column's `DEFAULT '[]'::jsonb` on the ALTER.
