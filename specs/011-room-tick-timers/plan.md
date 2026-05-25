# Implementation Plan: Room-Scoped Tick Timers

**Branch**: `011-room-tick-timers` | **Date**: 2026-05-24 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/011-room-tick-timers/spec.md`

## Summary

Adds a `tick` trigger to the existing behavior substrate (feature 009) plus a per-room scheduler that drives it. Each active room (one with at least one live player session) owns a **`RoomTicks.Scheduler`** GenServer, registered cluster-wide in **`Horde.Registry`** by `room_id`, supervised by a **`Horde.DynamicSupervisor`**. The scheduler advances at a configurable base tick rate (default 1 s), maintains a per-behavior `last_fire_time` map with drift-free `next_fire = last_fire + interval_ms` semantics (clarification Q3), and on each beat dispatches any tick behavior whose interval has elapsed in the order: room → NPC (by serial) → object (by id), and within each target by authored list position (clarification Q4).

Lifecycle is presence-driven (clarification Q2). A small singleton **`RoomTicks.Lifecycle`** GenServer subscribes to the global `Phoenix.Presence` topic plus the per-room movement events already broadcast by features 003–008 (`RoomPlayerArrived`/`RoomPlayerLeft`/`PlayerCurrentRoomChanged` plus Presence join/leave diffs). It computes per-room live-session counts on each relevant event; transitions to ≥1 trigger a join-grace timer (default 250 ms) and then a scheduler start; transitions to 0 trigger a leave-grace timer (default 5 s) and then a scheduler stop. Re-occupancy within the leave grace cancels the stop, preserving the schedule.

**Object behaviors** ship as part of this feature (clarification Q1). The `objects` (read-side schema name: `world_objects`) table gains a `behaviors` JSONB column with the same shape as feature 009's room/NPC behaviors. The existing `PlaceObject` command and `ObjectPlacedInRoom` event are extended with a `behaviors` field, backward-compatible. Carry/drop/move semantics use the existing `ObjectTaken` / `ObjectDropped` events and `PlayerMoved` event — the scheduler's scope tracker picks up these events and refreshes its in-scope behavior set on each.

The behavior **validator** (feature 009's `Behaviors.Validator`) is extended to recognize `tick` as a valid trigger and to enforce the strict-reject rule from clarification Q5: `interval_ms` MUST be present, a positive integer, and a positive integer multiple of the base tick rate. Missing, null, non-numeric, non-positive, or non-multiple values all reject at load/dispatch time with a clear error.

No new event types are emitted by the scheduler — ticks are transient triggers; the actions they fire route through the existing feature 009 `ActionExecutor` and reuse the existing `BehaviorUtterance` + `RoomUtterance` delivery paths. There is no scheduler-level event sourcing; per-behavior `last_fire_time` is volatile and resets on restart (which matches the natural "schedulers come back as players reconnect" reality from FR-011).

## Technical Context

**Language/Version**: Elixir 1.15+ on OTP 26+ (existing project baseline).

**Primary Dependencies (existing, reused)**:
- `phoenix ~> 1.8`, `phoenix_live_view ~> 1.1.0`, `phoenix_pubsub` (transitive) — cluster-aware broadcast for movement / room events
- `commanded ~> 1.4` + `commanded_eventstore_adapter ~> 1.4` — used for the `behaviors` field plumbing on the Object events (same backward-compat pattern as feature 009)
- `horde ~> 0.9` (added in feature 010) — `Horde.Registry` + `Horde.DynamicSupervisor` for cluster-wide per-room scheduler discovery
- `dns_cluster ~> 0.2.0` — cluster node discovery (already wired)
- `phoenix.Presence` (via `AgenticRealmsWeb.Presence`) — drives the live-session occupancy signal that triggers the lifecycle

**No new dependencies**.

**Reused project infrastructure**:
- `AgenticRealms.World.Behaviors.Validator` — extended for `tick` + `interval_ms` strict-reject (clarification Q5)
- `AgenticRealms.World.Behaviors.ActionExecutor` — unchanged; dispatches `:say` (and any future actions) regardless of triggering event source
- `AgenticRealms.World.Behaviors.Interpreter` — unchanged; this feature ADDS a parallel tick path, does not modify `player_entered`/`player_left` paths
- `AgenticRealms.World.UIEvents` — reuses `BehaviorUtterance`, `RoomUtterance` paths
- `AgenticRealms.World.Queries` — `look_room/1`, `list_npc_clones_in_room_with_behaviors/1`, `other_occupants_of/2`; extended with `list_objects_in_room/1` (currently a private helper — promoted to public for use by the scope tracker) and `list_carried_objects_for_room/1` (new helper)
- `AgenticRealmsWeb.Presence` — drives the `connected_players` topic that `Lifecycle` subscribes to
- The cluster-wide registry / dynamic supervisor pattern from feature 010 (`NPCChat`) — same idiom; one new `Horde.Registry` and one new `Horde.DynamicSupervisor` under the existing application supervision tree

**Storage**:
- **Persistent**: new `behaviors` JSONB column on `world_objects` (`NOT NULL DEFAULT '[]'::jsonb`). Same shape and same atom-table preservation as features 009/010 (the atoms `:trigger`, `:actions`, `:type`, `:text` are already pre-declared in `Application.__behavior_atoms__/0`; we add `:interval_ms` to that list).
- **Volatile**: per-room `RoomTicks.Scheduler` state — in-scope behavior set, per-behavior `last_fire_time` map, leave-grace timer ref, base-rate beat timer ref. Not persisted; resets on restart.

**No new domain events emitted by the scheduler itself.** The `behaviors` field plumbing extends existing events (`ObjectPlacedInRoom`, plus the `CreateObject` / `PlaceObject` command shape) — same backward-compat pattern as features 009/010 (`behaviors`/`lore`).

**Testing**:
- `ExUnit` (existing) — unit + contract + integration
- The base tick rate and grace periods are configurable; test config (`config/test.exs`) overrides to small values (e.g., `base_tick_rate_ms: 50`, `join_grace_ms: 10`, `leave_grace_ms: 50`) so deterministic-cadence tests run quickly
- Live behavior tests use `Phoenix.PubSub.subscribe` to the chatting player's `player_topic` (for `:room_speech` ticks) or `room_topic` (for `:npc_speech` ticks) to assert dispatched actions
- LiveView integration test follows the feature 010 pattern: a single `@moduletag :integration` test that exercises US1, US2, US3, US4, US5 in sequence with a seeded room + ticking NPC + ticking object

**Target Platform**: Linux server BEAM cluster (production); macOS BEAM single-node (dev). Tests on developer machines and CI.

**Project Type**: Phoenix LiveView web application.

**Performance Goals**:
- Per-room beat work: O(B) per beat where B is the number of in-scope tick behaviors. Each beat is a few map lookups + a small comparison per behavior + dispatch of due actions. Expected microseconds of CPU per beat for rooms with single-digit behavior counts; sub-millisecond for rooms with tens of behaviors.
- Total cluster overhead: O(R) processes where R is the number of currently-occupied rooms (NOT all rooms). Empty rooms consume zero scheduler resources (FR-007).
- Per-beat dispatch: in-flight tick actions (long-running, e.g., future LLM-bound actions) MUST NOT pile up — FR-010 skip-stale semantics.

**Constraints**:
- **No global ticker** (FR-016 — explicit OUT OF SCOPE)
- **Cluster correctness** — `RoomTicks.Scheduler` for a given `room_id` lives on exactly one node (Horde uniform distribution). Cross-node access transparent via BEAM distribution.
- **Privacy / delivery invariance** (FR-013) — a tick that fires a `:say` from a room delivers exactly as `player_entered → :say` does today. The trigger source does NOT change visibility.
- **Backward compatibility** — old `ObjectPlacedInRoom` events without a `behaviors` key project to `behaviors = []`. Replay test mirrors features 009/010.

**Scale/Scope**:
- Expected concurrent active rooms: low tens in early playtest; design supports hundreds without strain.
- Per-room behaviors: low tens typical.
- Total tick behaviors across cluster: low hundreds typical.

## Constitution Check

**Constitution file**: `.specify/memory/constitution.md` remains at template defaults (no concrete ratified principles). There are no enumerated gates to evaluate. PASS by default.

## Project Structure

### Documentation (this feature)

```text
specs/011-room-tick-timers/
├── plan.md                    # This file
├── research.md                # Phase 0 — lifecycle detection, scope tracking, beat scheduling, validator extension
├── data-model.md              # Phase 1 — Scheduler state, scope set, Object behaviors field, event extensions
├── quickstart.md              # Phase 1 — manual smoke test
├── contracts/                 # Phase 1
│   ├── scheduler.md           #   RoomTicks.Scheduler GenServer
│   ├── lifecycle.md           #   RoomTicks.Lifecycle singleton
│   ├── scope.md               #   RoomTicks.Scope (pure scope-set computation)
│   ├── registry.md            #   RoomTicks.Registry + Supervisor
│   ├── validator.md           #   Behaviors.Validator additions for tick + interval_ms
│   └── events.md              #   Object event/command extensions for behaviors
├── checklists/
│   └── requirements.md        # From /speckit.specify (clarifications resolved)
└── tasks.md                   # Phase 2 — /speckit.tasks output
```

### Source Code (repository root)

Single Phoenix project, layout consistent with features 005–010. New files marked `+`; modified `M`.

```text
agenticrealms/
├── lib/
│   ├── agenticrealms/
│   │   ├── application.ex                                   M  Add `:interval_ms` to @_behavior_atoms; add RoomTicks.Registry, RoomTicks.Supervisor, RoomTicks.Lifecycle to supervision tree.
│   │   └── world/
│   │       ├── ticks/
│   │       │   ├── scheduler.ex                            + Per-room GenServer. Owns the beat timer, scope set, last_fire map, leave-grace timer. Subscribes to room_topic + presence diff events to keep scope fresh.
│   │       │   ├── lifecycle.ex                            + Singleton GenServer. Subscribes to Phoenix.Presence diff on "connected_players" + room-movement UIEvents. Computes per-room live-occupancy diffs; triggers scheduler start/stop with grace periods.
│   │       │   ├── scope.ex                                + Pure module. Given a room_id, returns the in-scope tick-behavior set: room behaviors, NPC behaviors (clones in room), object behaviors (objects in room or carried by any live occupant or NPC in room).
│   │       │   ├── registry.ex                             + Horde.Registry wrapper for the per-room schedulers. `via_tuple(room_id)`.
│   │       │   └── supervisor.ex                           + Horde.DynamicSupervisor wrapper. `find_or_start/1` with room_id.
│   │       ├── behaviors/
│   │       │   ├── validator.ex                              M  Extend valid-trigger set to include `tick`; validate `interval_ms` per FR-005 / clarification Q5 (present + positive integer + positive multiple of base rate).
│   │       │   ├── action_executor.ex                        # (no changes — action dispatch is trigger-agnostic)
│   │       │   └── interpreter.ex                            # (no changes — this feature ADDS a parallel tick path)
│   │       ├── commands/
│   │       │   └── place_object.ex                           M  Add `behaviors: []` default to defstruct (mirrors feature 009's pattern for rooms/NPCs).
│   │       ├── events/
│   │       │   └── object_placed_in_room.ex                  M  Add `behaviors: []` default to defstruct (backward-compatible; old events deserialize with `[]`).
│   │       ├── schemas/
│   │       │   └── object.ex                                 M  Add `field :behaviors, {:array, :map}, default: []`.
│   │       ├── projections/
│   │       │   └── world_projector.ex                        M  Include `:behaviors` in the Repo.insert!/2 keyword list for the `ObjectPlacedInRoom` handler.
│   │       ├── room.ex                                       # (no changes)
│   │       ├── seed.ex                                       M  Extend the Stone Atrium with a tick-narrate room behavior (interval ~30s, atmospheric line). Extend Garrick with a tick-emote behavior (interval ~20s, idle gesture). Add a ticking object (e.g., a brass lantern that flickers every ~10s) to validate the carry/drop path.
│   │       └── queries.ex                                    M  Promote `list_objects_in_room/1` from private to public (used by Scope). Add `list_carried_objects_in_room/2` — objects held by any player or NPC whose `current_room_id` equals the given room. Add `live_occupants_of/1` — players in the given room AND in Presence's online set.
│   ├── agenticrealms_web/
│   │   └── live/
│   │       └── game_live.ex                                  # (no changes expected — tick-fired actions reuse existing handle_info clauses for BehaviorUtterance + RoomUtterance)
├── priv/
│   ├── repo/
│   │   └── migrations/
│   │       └── YYYYMMDDHHMMSS_add_object_behaviors_column.exs + Adds `behaviors` JSONB column to `world_objects` with `NOT NULL DEFAULT '[]'::jsonb`.
├── config/
│   ├── config.exs                                            M  Add a `config :agenticrealms, AgenticRealms.World.Ticks, base_tick_rate_ms: 1_000, join_grace_ms: 250, leave_grace_ms: 5_000` block with documented defaults.
│   └── test.exs                                              M  Override the three values to small numbers (e.g., 50, 10, 50) for fast tests.
└── test/
    ├── agenticrealms/
    │   ├── world/
    │   │   ├── ticks/
    │   │   │   ├── scheduler_test.exs                       + GenServer state transitions, beat timing, scope refresh, last_fire drift, FR-010 skip-stale, FR-008a ordering, leave-grace cancellation.
    │   │   │   ├── lifecycle_test.exs                       + 0→1 / 1→0 detection from Presence diffs + movement events; grace-period absorbs reconnect bursts; multi-room concurrent transitions.
    │   │   │   ├── scope_test.exs                           + Pure scope computation; room + NPCs + in-room objects + carried objects; excludes NPCs that left mid-tick.
    │   │   │   └── registry_test.exs                        + Horde-registered scheduler lookup; pid returned per room_id.
    │   │   └── behaviors/
    │   │       └── validator_test.exs                         M  Add tests for tick validation: present, integer, positive, multiple-of-base; missing/null/non-numeric/zero/negative/non-multiple all reject per Q5.
    │   └── projections/
    │       └── world_projector_object_replay_test.exs       + Replay test for backward-compat: old `ObjectPlacedInRoom` events without `behaviors` project with `behaviors = []`.
    └── agenticrealms_web/
        └── live/
            └── game_live_ticks_test.exs                     + LiveView integration test (`@moduletag :integration`) covering US1–US5 in sequence. Uses test-config overridden rates (50 ms base, 10 ms join grace, 50 ms leave grace) so the test finishes in well under a second per US.
```

**Structure Decision**: New `lib/agenticrealms/world/ticks/` directory hosting the four runtime modules (scheduler, lifecycle, scope, registry/supervisor). Behaviors-layer changes are minimal: the validator gains tick validation; the existing interpreter and action executor are unchanged. Object behaviors plumb through the existing command/event/projector chain in the established backward-compatible way. The Application supervision tree gains three siblings (Registry, Supervisor, Lifecycle) next to the feature-010 `NPCChat` triad — same idiom, same neighbors.

## Complexity Tracking

> No constitution violations to justify. The Horde dependency was already added in feature 010; this feature consumes the same pattern. The new Object `behaviors` field is the natural completion of the feature-009 substrate (rooms ✓, NPC blueprints ✓, NPC clones ✓, objects ← now).

| Apparent complexity | Justification |
|---------------------|---------------|
| Singleton `Lifecycle` GenServer in addition to per-room schedulers | The 0↔1 transition signal requires watching Presence + movement at a level above any single room. A per-room scheduler can't observe its own start condition (it doesn't exist yet); something has to be the listener of last resort. A singleton on a known supervised name is simpler than embedding the detection in (a) every PubSub topic, (b) the Phoenix.Endpoint, or (c) `GameLive` itself. |
| Per-beat scope refresh on every event vs. event-driven scope updates | The scheduler caches its in-scope behavior set and refreshes incrementally on observed events (NPC arrived/despawned, object taken/dropped, player moved with carried object). A full requery on every beat would scale poorly with active rooms × in-scope behaviors. The cached approach is bounded-work per beat. |
