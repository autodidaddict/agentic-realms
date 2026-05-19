# Implementation Plan: Persisted Interactive World — Rooms, Objects & Inventory

**Branch**: `003-persisted-world` | **Date**: 2026-05-18 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/003-persisted-world/spec.md`

## Summary

Add a persisted, interactive game world to Agentic Realms on top of feature 001 (mocked UI) and 002 (player accounts). Players entering the Play view are placed in a real room from a seeded starter map and can issue text commands — `look`, `go <dir>`/`<dir>`/letter shortcuts, `take <object>`, `drop <object>`, `inventory` — that mutate persisted world state and produce confirmation, refusal, witness, and arrival/departure entries in the narrative log. Multiple concurrent sessions per player share a single underlying world state, and witness entries propagate in real time to every other player in the relevant room.

**Architectural approach (per user direction)**:

- **Event sourcing via [Commanded](https://github.com/commanded/commanded)**: every state-changing operation is dispatched as a command against a Commanded aggregate; the aggregate emits domain events that are appended to an event store and projected into Ecto read models. This naturally serializes contending operations (the FR-011 take race resolves itself: the second taker's command sees an aggregate whose room no longer contains the object).
- **Two aggregates**:
  - **`World.Room`** (one per room) — owns objects-in-room, occupants, exits. Handles take/drop and seeding operations.
  - **`World.Player`** (one per player) — owns current_room and inventory. Handles spawn and move.
- **Single `PlayerMoved` event** carrying `from_room_id`, `to_room_id`, `direction` — no separate enter/leave events at the domain level, so movement is not transactional across two aggregates. Read-model projectors update both rooms' occupancy from this one event.
- **Two-tier event vocabulary** (per user clarification):
  - **Domain events** (Commanded, persisted in event store): `RoomCreated`, `ExitAdded`, `ObjectPlacedInRoom`, `ObjectTakenFromRoom`, `ObjectDroppedInRoom`, `PlayerSpawned`, `PlayerMoved`.
  - **UI events** (transient, broadcast via `Phoenix.PubSub`): `RoomObjectTaken`, `RoomObjectDropped`, `RoomPlayerArrived`, `RoomPlayerLeft`. A single `UIEventBroadcaster` event handler subscribes to domain events and fans out the appropriate UI events to the affected room topics. LiveViews subscribe to their current-room topic and project UI events into log entries and HUD/state updates.
- **`look` is query-only**: it issues no command and emits no event. It reads room + occupants + contents from the read models and appends a `:room` log entry locally.

This design satisfies every clarification recorded in the spec:

- **Q1 (concurrent take race)**: serialized by the Room aggregate; loser sees standard FR-011.
- **Q2 (witness propagation)**: UIEventBroadcaster fans out RoomObjectTaken/Dropped/PlayerArrived/PlayerLeft to same-room subscribers in real time.
- **Q3 (Inventory HUD downgrade)**: the HUD now reads `World.Queries.list_inventory/1` returning `{name, short_description}` tuples — the equipped/quantity/filter columns are removed from the template.
- **Q4 (one-way exits)**: `World.Schemas.Exit` is uniformly directional (`source_room_id`, `direction`, `target_room_id`); the seed defines paired exits by convention.
- **Q5 (multi-session)**: aggregates are per-player (not per-session); LiveViews subscribe to `"player:#{player_id}"` and `"room:#{room_id}"` PubSub topics, so all of a player's tabs see the same authoritative state. Actor-side log entries are produced by the LiveView that handled the command and never broadcast; witness UI events are broadcast and reach all of the player's sessions in the relevant room except the actor's own.

## Technical Context

**Language/Version**: Elixir 1.15+ / Erlang OTP 26+
**Primary Dependencies**: Phoenix 1.8.5, Phoenix LiveView 1.1.0, Ecto 3.13, `commanded ~> 1.4`, `commanded_eventstore_adapter ~> 1.4`, `eventstore ~> 1.4` (PostgreSQL-backed event store), existing `bcrypt_elixir`
**Storage**: PostgreSQL — existing `agenticrealms_repo` for read models and accounts, plus a new `agenticrealms_eventstore` database (or schema) owned by the `eventstore` library for the append-only event log
**Testing**: ExUnit + Phoenix.ConnTest + Phoenix.LiveViewTest + `Commanded.Aggregates.Aggregate` test helpers; in-memory event store adapter via `:in_memory` for fast aggregate unit tests; full Postgres event store in integration tests
**Target Platform**: Web browser (desktop only, per 001/002 scope)
**Project Type**: Web application (Phoenix LiveView monolith)
**Performance Goals**: command dispatch latency under 50 ms p95 in dev (single-node); witness UI events delivered to a same-room subscriber within 100 ms of the originating command being acknowledged
**Constraints**: PostgreSQL is the single durable substrate; no external message broker; no real-time replication across nodes in this feature (DNSCluster is already wired but multi-node coordination is out of scope here); seed must be re-runnable safely
**Scale/Scope**: starter map ~5 rooms / ~5 objects / handful of concurrent players (developer + a few testers). Read-model tables and event-store partitioning are sized for this — no sharding or projection rebuilds in scope.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The project constitution file (`.specify/memory/constitution.md`) is the unfilled template — no concrete principles have been ratified for this project. There are no gates to enforce. Proceeding.

**Post-Phase 1 re-check**: No violations. The design introduces Commanded as a new architectural pattern, but the choice is directly mandated by the user's planning input and is the standard Elixir CQRS/ES stack. All other choices follow existing project conventions (Ecto read models in the same Postgres DB, Phoenix.PubSub already supervised, LiveView for the UI, AGENTS.md guidelines for HEEx).

## Project Structure

### Documentation (this feature)

```text
specs/003-persisted-world/
├── plan.md                  # This file (/speckit-plan output)
├── spec.md                  # Feature specification (already exists)
├── research.md              # Phase 0: technical decisions & alternatives considered
├── data-model.md            # Phase 1: aggregates, events, read-model schemas
├── quickstart.md            # Phase 1: dev setup, seed run, manual test walkthrough
├── contracts/
│   ├── commands.md          # Phase 1: command + event payload contracts
│   ├── ui_events.md         # Phase 1: PubSub topic + UI event payload contracts
│   └── parser.md            # Phase 1: text-input grammar → command struct
└── checklists/
    └── requirements.md      # Spec quality checklist (already exists)
```

### Source Code (repository root)

```text
lib/
├── agenticrealms/
│   ├── accounts/...                          # existing (unchanged)
│   ├── accounts.ex                           # existing (unchanged)
│   ├── game_data.ex                          # existing — kept for wizard mock; player-side use is replaced by World
│   ├── repo.ex                               # existing (unchanged)
│   ├── application.ex                        # MODIFIED — add Commanded app + EventStore + projectors to supervision tree
│   └── world/                                # NEW — the bounded context
│       ├── application.ex                    # Commanded application module (`use Commanded.Application`)
│       ├── router.ex                         # Commanded router (commands → aggregates)
│       ├── room.ex                           # Room aggregate (state + execute/2 + apply/2 clauses)
│       ├── player.ex                         # Player aggregate (state + execute/2 + apply/2 clauses)
│       ├── commands/
│       │   ├── create_room.ex
│       │   ├── add_exit.ex
│       │   ├── place_object.ex
│       │   ├── take_object.ex
│       │   ├── drop_object.ex
│       │   ├── spawn_player.ex
│       │   └── move_player.ex
│       ├── events/                           # domain events (persisted in event store)
│       │   ├── room_created.ex
│       │   ├── exit_added.ex
│       │   ├── object_placed_in_room.ex
│       │   ├── object_taken_from_room.ex
│       │   ├── object_dropped_in_room.ex
│       │   ├── player_spawned.ex
│       │   └── player_moved.ex
│       ├── projections/                      # `Commanded.Event.Handler` projectors → read models
│       │   ├── room_projector.ex             # RoomCreated, ExitAdded, ObjectPlacedInRoom, ObjectTaken, ObjectDropped → world_rooms, world_exits, world_objects
│       │   ├── player_state_projector.ex     # PlayerSpawned, PlayerMoved → player_state; ObjectTaken/Dropped → world_objects.player_id
│       │   └── README.md                     # short note on rebuild semantics
│       ├── ui_events.ex                      # UI event struct definitions (transient — Phoenix.PubSub only)
│       ├── ui_event_broadcaster.ex           # Commanded.Event.Handler → broadcasts UI events to "room:<id>" topics
│       ├── schemas/                          # Ecto schemas backing read models
│       │   ├── room.ex                       # world_rooms
│       │   ├── exit.ex                       # world_exits
│       │   ├── object.ex                     # world_objects (with nullable room_id / player_id)
│       │   └── player_state.ex               # player_state (current_room_id per player_id)
│       ├── queries.ex                        # read-side API: look_room/1, list_inventory/1, current_room_of/1, occupants_of/1
│       ├── command_parser.ex                 # parse trimmed text → {:ok, command_struct} | {:unknown, raw} | {:empty}
│       └── commands.ex                       # write-side API facade: `take/3`, `drop/3`, `move/3`, etc.
├── agenticrealms_web/
│   ├── components/
│   │   └── game_components.ex                # MODIFIED — Inventory HUD drops equipped/quantity/filter; new log_entry clauses for arrival/departure/witness
│   └── live/
│       ├── game_live.ex                      # MODIFIED — wire to World.Commands/Queries; subscribe to "player:<id>" + "room:<current>"; handle UI events
│       └── game_live.html.heex               # MODIFIED — log driven by persisted state for room/inventory
priv/
├── repo/
│   ├── migrations/
│   │   ├── 20260423222716_create_players.exs                 # existing
│   │   ├── 20260423225413_add_preferences_to_players.exs     # existing
│   │   └── <TIMESTAMP>_create_world_read_models.exs          # NEW — world_rooms, world_exits, world_objects, player_state
│   └── seeds.exs                             # MODIFIED — runs World.Seed.run/0 if world is empty
└── event_store/
    └── migrations/                           # generated by `mix event_store.init`; checked in
config/
├── config.exs                                # MODIFIED — Commanded app + EventStore adapter configuration
├── dev.exs                                   # MODIFIED — eventstore Postgres URL (or shared DB w/ separate schema)
├── test.exs                                  # MODIFIED — `Commanded.EventStore.Adapters.InMemory` for fast tests; or test-specific Postgres event store DB
└── runtime.exs                               # MODIFIED — production eventstore URL handling
test/
├── agenticrealms/
│   └── world/
│       ├── room_test.exs                     # NEW — aggregate behavior (creation, exits, place/take/drop, take-from-empty, take-fixed)
│       ├── player_test.exs                   # NEW — aggregate behavior (spawn, move, move-no-exit)
│       ├── command_parser_test.exs           # NEW — parsing matrix (look, look at, go N, n, take X, drop X, inv aliases, unknown, empty, ws)
│       ├── projections_test.exs              # NEW — projectors update read models correctly under event ordering
│       ├── queries_test.exs                  # NEW — look_room / list_inventory / current_room_of agree with state after a sequence of events
│       └── ui_event_broadcaster_test.exs     # NEW — UI events published on the right topics with the right payloads; actor excluded
└── agenticrealms_web/
    └── live/
        └── game_live_test.exs                # NEW — end-to-end LiveView tests: look, go, take, drop, inv, witness propagation across two LiveView processes, multi-session
```

**Structure Decision**: A new `lib/agenticrealms/world/` bounded context houses every CQRS/ES module (commands, events, aggregates, projections, queries, parser, UI events). The existing `Accounts` context is untouched. The web tier only needs surgical edits to `GameLive`, its template, and `GameComponents`. The `GameData` mock module remains in place for the wizard view (out of scope for this feature) but is no longer consulted by the player view.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No violations. (Constitution is a template; user has explicitly directed the Commanded/event-sourcing approach.)
