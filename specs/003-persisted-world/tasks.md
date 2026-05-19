# Tasks: Persisted Interactive World — Rooms, Objects & Inventory

**Input**: Design documents from `/specs/003-persisted-world/`
**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: The spec did not request TDD, but `plan.md` (project structure) and `research.md` (D10) explicitly enumerate test files that must exist. Test tasks are included alongside implementation in each phase — they need not be written first, but they must exist before a story is considered complete.

**Organization**: Tasks are grouped by user story so each story can be implemented, tested, and demoed as an independent increment.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4, US5)
- All file paths are repository-relative

## Path Conventions

This is a **Phoenix LiveView web application** (single Elixir project). Code under `lib/`, tests under `test/`, migrations under `priv/repo/migrations/`, seed under `priv/repo/seeds.exs`, configuration under `config/`. The new bounded context lives at `lib/agenticrealms/world/`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Add Commanded and EventStore dependencies, configure them for each Mix environment, and wire the supervision tree.

- [ ] T001 Add `{:commanded, "~> 1.4"}`, `{:commanded_eventstore_adapter, "~> 1.4"}`, and `{:eventstore, "~> 1.4"}` to the deps list in `mix.exs`; run `mix deps.get` to install.
- [ ] T002 Configure the Commanded application and the EventStore adapter for dev in `config/dev.exs`: set `config :agenticrealms, AgenticRealms.World.Application, event_store: [adapter: Commanded.EventStore.Adapters.EventStore, event_store: AgenticRealms.EventStore]` and add `config :agenticrealms, AgenticRealms.EventStore, serializer: EventStore.JsonSerializer, username/password/database/hostname: …` pointing at `agenticrealms_eventstore_dev`. Mirror the structure (with appropriate URLs) in `config/test.exs` (using `Commanded.EventStore.Adapters.InMemory`) and `config/runtime.exs` (reading `EVENTSTORE_URL`).
- [ ] T003 Add the `event_store` aliases to `mix.exs`: extend the `setup` alias to `["deps.get", "event_store.init", "ecto.setup", "assets.setup", "assets.build"]` so a fresh checkout bootstraps the event store DB in one command. Also add `"event_store.setup": ["event_store.create", "event_store.init"]` as a convenience.
- [ ] T004 [P] Create `lib/agenticrealms/event_store.ex` defining `AgenticRealms.EventStore` using `EventStore` and `otp_app: :agenticrealms` so the `eventstore` library has a configured module.

**Checkpoint**: `mix deps.get` succeeds; `mix event_store.init` creates the new database; `iex -S mix` boots without supervision errors.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Everything that must exist before any user-story slice can be implemented — read-model migration, Ecto schemas, aggregate skeletons, the Commanded application module, the router skeleton, the projector skeletons, the UIEvent struct file, and the supervision wiring. No story can begin until this phase is complete.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [ ] T005 Generate the read-model migration: `mix ecto.gen.migration create_world_read_models`. Fill the generated file in `priv/repo/migrations/<TIMESTAMP>_create_world_read_models.exs` with the four tables and constraints exactly as defined in `data-model.md` §5: `world_rooms`, `world_exits` (with `UNIQUE(source_room_id, direction)` and `CHECK direction IN …`), `world_objects` (with `CHECK exactly_one_location` and the `LOWER(name)` functional index), and `player_state` (PK is `player_id`).
- [ ] T006 [P] Create the `AgenticRealms.World.Schemas.Room` Ecto schema in `lib/agenticrealms/world/schemas/room.ex` per `data-model.md` §3.1 (primary key type `:binary_id`, fields `name`, `description`, timestamps).
- [ ] T007 [P] Create the `AgenticRealms.World.Schemas.Exit` Ecto schema in `lib/agenticrealms/world/schemas/exit.ex` per `data-model.md` §3.2 (binary_id PK, `belongs_to :source_room, Room`, `belongs_to :target_room, Room`, `direction` string).
- [ ] T008 [P] Create the `AgenticRealms.World.Schemas.Object` Ecto schema in `lib/agenticrealms/world/schemas/object.ex` per `data-model.md` §3.3 (binary_id PK, `name`, `short_description`, `long_description`, `fixed`, nullable `room_id` and `player_id`).
- [ ] T009 [P] Create the `AgenticRealms.World.Schemas.PlayerState` Ecto schema in `lib/agenticrealms/world/schemas/player_state.ex` per `data-model.md` §3.4 (PK = `player_id` referencing `players`, `current_room_id` referencing `world_rooms`, nullable).
- [ ] T010 [P] Create `lib/agenticrealms/world/direction.ex` with `parse/1` (string/atom → `{:ok, :north | … | :down} | :error`, handles `"north"`, `"n"`, `"go north"`, `"GO   NORTH"`, etc.), `opposite/1` (`:north ↔ :south`, etc.), `canonical/0` returning the six-atom list, and `to_string/1`. Use literal pattern matching only — never `String.to_atom/1` on user input.
- [ ] T011 [P] Create `lib/agenticrealms/world.ex` exposing `player_stream_id(player_id)` returning `"player-#{player_id}"` and `room_stream_id(room_id)` returning `"room-#{room_id}"`. Document at the module-doc level that the world bounded context lives under this namespace.
- [ ] T012 Create `lib/agenticrealms/world/application.ex` as `use Commanded.Application, otp_app: :agenticrealms, event_store: …` per `config/*.exs`. Implements `Commanded.Application` behavior with the router referenced below.
- [ ] T013 Create `lib/agenticrealms/world/router.ex` as `use Commanded.Commands.Router`. Body left empty for now (commands and `dispatch …, to: …, identity: …` clauses added per-story in Phases 3–6).
- [ ] T014 [P] Create the `AgenticRealms.World.Room` aggregate skeleton in `lib/agenticrealms/world/room.ex` per `data-model.md` §1.1: defstruct with `id`, `name`, `description`, `exits`, `object_ids`, `occupant_player_ids` (always empty in this feature — kept for future), `known_objects`. No `execute/2` or `apply/2` clauses yet; module compiles cleanly.
- [ ] T015 [P] Create the `AgenticRealms.World.Player` aggregate skeleton in `lib/agenticrealms/world/player.ex` per `data-model.md` §1.2 final decision: defstruct with `id` and `current_room_id` only (NO inventory tracking on aggregate). No clauses yet.
- [ ] T016 [P] Create `lib/agenticrealms/world/ui_events.ex` defining all six UI event structs in one module under nested module names `AgenticRealms.World.UIEvents.{RoomObjectTaken, RoomObjectDropped, RoomPlayerArrived, RoomPlayerLeft, PlayerCurrentRoomChanged, PlayerInventoryChanged}`, with the exact fields from `contracts/ui_events.md` §U1–U6.
- [ ] T017 [P] Create the projector skeletons:
   - `lib/agenticrealms/world/projections/world_projector.ex` (`use Commanded.Event.Handler, application: AgenticRealms.World.Application, name: "WorldProjector", consistency: :eventual`) with empty handler clauses for now.
   - `lib/agenticrealms/world/projections/player_state_projector.ex` with the same shape and `name: "PlayerStateProjector"`.
   - `lib/agenticrealms/world/ui_event_broadcaster.ex` with `name: "UIEventBroadcaster"`. Empty `handle/2` clauses for now.
- [ ] T018 Add the Commanded application and the three event handlers to `lib/agenticrealms/application.ex` supervision tree, placed AFTER `AgenticRealms.Repo` and `Phoenix.PubSub`: append `AgenticRealms.EventStore`, `AgenticRealms.World.Application`, `AgenticRealms.World.Projections.WorldProjector`, `AgenticRealms.World.Projections.PlayerStateProjector`, `AgenticRealms.World.UIEventBroadcaster`.
- [ ] T019 Run the migration locally (`mix ecto.migrate`) and `iex -S mix` to confirm the supervision tree boots cleanly with the new children and no Commanded warnings.

**Checkpoint**: Foundation ready — the app boots with Commanded running, the read-model tables exist, and every aggregate/projector/event module compiles. User stories can now begin.

---

## Phase 3: User Story 5 - Seeded Starter Map Exists (Priority: P1)

**Goal**: A small persisted starter map exists in the database after `mix ecto.setup`. The map satisfies FR-020: at least three rooms all reachable from a designated starting room, every connection realized as a pair of one-way exits, at least one takeable object, at least one fixed object, at least one empty room.

**Independent Test**: After `mix ecto.reset && mix event_store.drop && mix event_store.setup && mix ecto.setup`, query the read models from `iex` and verify the world state matches the acceptance scenarios in spec US5. (No UI involvement.)

> US5 is implemented BEFORE US1–US4 because every other story requires a populated world to act on. Per spec §"Why this priority": "Without a seeded map there is nothing for any of the other commands to operate on."

### Implementation

- [ ] T020 [P] [US5] Create the `CreateRoom` command struct in `lib/agenticrealms/world/commands/create_room.ex` with fields `room_id`, `name`, `description` (per `contracts/commands.md` §C1).
- [ ] T021 [P] [US5] Create the `AddExit` command struct in `lib/agenticrealms/world/commands/add_exit.ex` with fields `room_id`, `direction`, `target_room_id` (per §C2).
- [ ] T022 [P] [US5] Create the `PlaceObject` command struct in `lib/agenticrealms/world/commands/place_object.ex` with fields `room_id`, `object_id`, `name`, `short_description`, `long_description`, `fixed` (per §C3).
- [ ] T023 [P] [US5] Create the `RoomCreated` event struct in `lib/agenticrealms/world/events/room_created.ex` with fields `room_id`, `name`, `description` (per `data-model.md` §2).
- [ ] T024 [P] [US5] Create the `ExitAdded` event struct in `lib/agenticrealms/world/events/exit_added.ex` with fields `room_id`, `direction`, `target_room_id`.
- [ ] T025 [P] [US5] Create the `ObjectPlacedInRoom` event struct in `lib/agenticrealms/world/events/object_placed_in_room.ex` with fields `room_id`, `object_id`, `name`, `short_description`, `long_description`, `fixed`.
- [ ] T026 [US5] Implement `execute/2` and `apply/2` clauses on `AgenticRealms.World.Room` for the three seed commands in `lib/agenticrealms/world/room.ex`. Preconditions and state transitions match `contracts/commands.md` §C1–C3 and `data-model.md` §1.1 (e.g., `AddExit` rejects when `Map.has_key?(state.exits, direction)`).
- [ ] T027 [US5] Register the three commands in `lib/agenticrealms/world/router.ex`: `dispatch [CreateRoom, AddExit, PlaceObject], to: AgenticRealms.World.Room, identity: :room_id, identity_prefix: "room-"`.
- [ ] T028 [US5] Implement `handle/2` clauses on `AgenticRealms.World.Projections.WorldProjector` (in `lib/agenticrealms/world/projections/world_projector.ex`) for `RoomCreated`, `ExitAdded`, and `ObjectPlacedInRoom`, inserting rows into `world_rooms`, `world_exits`, and `world_objects` respectively (with `room_id` set, `player_id = nil`).
- [ ] T029 [US5] Create `lib/agenticrealms/world/seed.ex` with `run/0` that: (a) returns `:already_seeded` if `Repo.aggregate(World.Schemas.Room, :count) > 0`; (b) otherwise dispatches the seven `CreateRoom`/`AddExit`/`PlaceObject` commands defined in `research.md` §D8 (three rooms — atrium/corridor/library — paired exits atrium↔corridor and atrium↔library, brass lantern in atrium, leather-bound journal AND reading lectern in library, corridor empty). Use UUID v4 for each entity id, but pin the starting room ID in module-level config so it can be referenced by `World.Seed.starting_room_id/0`.
- [ ] T030 [US5] Add `AgenticRealms.World.Seed.starting_room_id/0` that returns the seeded atrium's UUID — used by US1's `SpawnPlayer` and US2's FR-022 recovery path. Store the canonical id either as a module attribute or in a tiny `world_config` table; module attribute is simpler.
- [ ] T031 [US5] Modify `priv/repo/seeds.exs` to call `AgenticRealms.World.Seed.run/0` after any existing seed activity. Add `Logger.info/1` for both the "seeded" and "already seeded" branches.
- [ ] T032 [US5] Add `test/agenticrealms/world/seed_test.exs` with two cases: (a) calling `Seed.run/0` against an empty world creates the expected rows in all three read-model tables and produces the expected event stream contents (assert via `EventStore.read_all_streams_forward/0` or similar); (b) calling `Seed.run/0` a second time is a no-op and returns `:already_seeded`.
- [ ] T033 [P] [US5] Add `test/agenticrealms/world/room_test.exs` aggregate unit tests for `CreateRoom` (creates), `CreateRoom` second time (rejects), `AddExit` (adds), `AddExit` duplicate direction (rejects), `PlaceObject` (places), `PlaceObject` duplicate object id (rejects). Use `Commanded.Aggregate.Multi` test helpers or hand-call `execute/2` and `apply/2` on the struct.

**Checkpoint**: Running `mix ecto.setup` populates the read models with the seeded map; running it again is idempotent. The world is observable in `psql` and `iex` even though no UI command can yet interact with it.

---

## Phase 4: User Story 1 - Player Looks at Their Surroundings (Priority: P1) 🎯 MVP slice

**Goal**: A newly registered player who navigates to `/play` for the first time is spawned in the starter map's designated starting room and sees a `:room` log entry rendered from persisted state. They can issue `look` at any time to refresh that entry.

**Independent Test**: Run the quickstart §3 single-player happy-path steps 1–2 (mount in atrium, `look`, see real room data). FR-005, FR-016, partial FR-002, FR-003.

### Implementation

- [ ] T034 [P] [US1] Create the `SpawnPlayer` command struct in `lib/agenticrealms/world/commands/spawn_player.ex` with `player_id` and `starting_room_id` (per `contracts/commands.md` §C6).
- [ ] T035 [P] [US1] Create the `PlayerSpawned` event struct in `lib/agenticrealms/world/events/player_spawned.ex` with `player_id` and `room_id`.
- [ ] T036 [US1] Implement `execute/2` and `apply/2` clauses on `AgenticRealms.World.Player` for `SpawnPlayer` in `lib/agenticrealms/world/player.ex`. Reject when `state.current_room_id != nil` with `{:error, :already_spawned}`.
- [ ] T037 [US1] Register `SpawnPlayer` in `lib/agenticrealms/world/router.ex`: `dispatch SpawnPlayer, to: AgenticRealms.World.Player, identity: :player_id, identity_prefix: "player-"`.
- [ ] T038 [US1] Implement `handle/2` clause on `AgenticRealms.World.Projections.PlayerStateProjector` for `PlayerSpawned`: `upsert` a `player_state` row with `player_id` and `current_room_id` = `room_id`.
- [ ] T039 [US1] Implement `handle/2` clause on `AgenticRealms.World.UIEventBroadcaster` for `PlayerSpawned`: broadcast `RoomPlayerArrived{room_id, actor_id, actor_username, from_direction: nil}` on `"room:#{room_id}"` AND `PlayerCurrentRoomChanged{player_id, from_room_id: nil, to_room_id: room_id}` on `"player:#{player_id}"`. Resolve `actor_username` from `Accounts.get_player!/1`.
- [ ] T040 [P] [US1] Create the `RoomView` struct module in `lib/agenticrealms/world/room_view.ex` with fields `id`, `name`, `description`, `exits` (list of `%{direction, target_name}`), `objects` (list of `%{id, name, short_description}`), `other_players` (list of `%{id, username}`).
- [ ] T041 [US1] Create `lib/agenticrealms/world/queries.ex` with `look_room/1` (joins `player_state → world_rooms`, `world_exits → target rooms`, `world_objects WHERE room_id = current`, `player_state WHERE current_room_id = … AND player_id != self` JOIN `players`) returning `{:ok, %RoomView{}} | {:error, :no_current_room}`. Also stub `current_room_of/1` and `occupants_of/1` for use by later stories.
- [ ] T042 [US1] Create `lib/agenticrealms/world/commands.ex` write-side facade with `spawn/2(player_id, starting_room_id)` that pre-checks `player_state` and dispatches `SpawnPlayer` only when absent or `current_room_id == nil`.
- [ ] T043 [US1] Create `lib/agenticrealms/world/command_parser.ex` with `parse/1` returning `{:empty}`, `{:unknown, raw}`, or `{:look}` for now (per `contracts/parser.md` rows 1–7). Other verbs return `{:unknown, raw}` until later stories extend the verb table.
- [ ] T044 [US1] Add a `log_entry/1` clause for `%{kind: :room, room: %RoomView{}}` in `lib/agenticrealms_web/components/game_components.ex` rendering name, description, exit chips (clickable, phx-click=`"submit_command"` phx-value-text=`"<direction>"`), object listings (entity styling), and other-player listings. Replace the existing `:room` clause that depends on `GameData` shape — the new clause must match the new `%RoomView{}` shape.
- [ ] T045 [US1] Modify `lib/agenticrealms_web/live/game_live.ex` `mount/3`: on first mount, query `World.Queries.current_room_of/1`; if `:error`, call `World.Commands.spawn/2` with the seed's starting room id and re-query; subscribe to `"player:#{player_id}"` and `"room:#{current_room_id}"` via `Phoenix.PubSub`; seed the `:log` assign with an initial `:room` entry from `World.Queries.look_room/1` (NOT `GameData.starting_log()` anymore).
- [ ] T046 [US1] Extend `lib/agenticrealms_web/live/game_live.ex` `handle_event("submit_command", …)` to call `CommandParser.parse/1`; for `{:look}`, query `World.Queries.look_room/1` and append a `:room` log entry. For `{:empty}` → no-op. For `{:unknown, raw}` → append a `:system` entry. (Other parser results still fall through to existing 001 mock behavior or to "unknown" until later stories extend.)
- [ ] T047 [P] [US1] Add `test/agenticrealms/world/command_parser_test.exs` covering rows 1–7 of the parser test matrix in `contracts/parser.md` (empty/whitespace inputs, `look`, `l`, `LOOK`, `look around`).
- [ ] T048 [P] [US1] Add `test/agenticrealms/world/queries_test.exs` with a `look_room/1` test: seed a tiny world via direct command dispatch, spawn a player, assert the returned `%RoomView{}` matches.
- [ ] T049 [US1] Add `test/agenticrealms_web/live/game_live_test.exs` (new file) with two cases: (a) a freshly registered player mounting `/play` sees a `:room` log entry whose name matches the seeded atrium; (b) typing `look` appends a fresh `:room` entry.

**Checkpoint**: A new player can log in, click Play, and see the Stone Atrium's real description rendered from the database. `look` produces a fresh entry. No movement, no take/drop yet.

---

## Phase 5: User Story 2 - Player Moves Between Rooms (Priority: P1)

**Goal**: A player can move between adjacent rooms via `go <dir>`, `<dir>`, or single-letter directional shortcuts. Movement updates the player's `current_room_id`, appends an arrival entry, and produces `RoomPlayerLeft` + `RoomPlayerArrived` UI events for any same-room witnesses. Invalid directions produce the FR-007 "you can't go that way" message. FR-022 recovery is wired up.

**Independent Test**: Run quickstart §3 single-player steps 8, 11, 14, 16 (cross every seeded edge in both directions) plus quickstart §3 two-player steps 20, 26, 27 (witness arrival + departure messages).

### Implementation

- [ ] T050 [P] [US2] Create the `MovePlayer` command struct in `lib/agenticrealms/world/commands/move_player.ex` with `player_id`, `from_room_id`, `to_room_id`, `direction`.
- [ ] T051 [P] [US2] Create the `PlayerMoved` event struct in `lib/agenticrealms/world/events/player_moved.ex` with `player_id`, `from_room_id`, `to_room_id`, `direction`.
- [ ] T052 [US2] Implement `execute/2` and `apply/2` clauses on `AgenticRealms.World.Player` for `MovePlayer`: reject with `{:error, :stale_from_room}` if `state.current_room_id != cmd.from_room_id`; emit `PlayerMoved` otherwise; apply sets `current_room_id = to_room_id`.
- [ ] T053 [US2] Register `MovePlayer` in the router under the existing Player dispatch block.
- [ ] T054 [US2] Implement `handle/2` clause on `PlayerStateProjector` for `PlayerMoved`: update `player_state.current_room_id = to_room_id`. Handle the FR-022 case in the same projector clause: if `to_room_id` row no longer exists in `world_rooms`, set `current_room_id = nil` instead (catch `Ecto.ConstraintError` from the FK and convert).
- [ ] T055 [US2] Implement `handle/2` clause on `UIEventBroadcaster` for `PlayerMoved`: broadcast `RoomPlayerLeft{room_id: from_room_id, actor_id, actor_username, to_direction: direction}` on `"room:#{from_room_id}"`; broadcast `RoomPlayerArrived{room_id: to_room_id, actor_id, actor_username, from_direction: World.Direction.opposite(direction)}` on `"room:#{to_room_id}"`; broadcast `PlayerCurrentRoomChanged{player_id, from_room_id, to_room_id}` on `"player:#{player_id}"`.
- [ ] T056 [US2] Extend `World.Commands` with `move/2(player_id, direction)`: read `current_room_id` from `player_state`; read `world_exits WHERE source_room_id = current AND direction = direction`; if no row, return `{:error, :no_exit_in_direction}` without dispatching; otherwise dispatch `MovePlayer`. Return `{:ok, to_room_id}` on success.
- [ ] T057 [US2] Extend `World.CommandParser` to handle direction inputs per `contracts/parser.md` rows 9–17 (`north`/`n`, ..., `down`/`d`, `go <dir>`, `go` alone → unknown). Use `World.Direction.parse/1`.
- [ ] T058 [US2] Extend `GameLive.handle_event("submit_command", ...)` to dispatch parser `{:move, dir}` results to `World.Commands.move/2`. On `{:ok, to_room_id}`: append a fresh `:room` log entry by calling `World.Queries.look_room/1` AND set `:awaiting_room_change_ack` in socket assigns so the matching `PlayerCurrentRoomChanged` broadcast is discarded by this tab (per `contracts/ui_events.md` §U5 origin-tab rule). On `{:error, :no_exit_in_direction}`: append `%{kind: :system, text: "You can't go that way."}`.
- [ ] T059 [US2] Implement `handle_info/2` clauses in `GameLive` for the four room-scoped UI events (`RoomPlayerLeft`, `RoomPlayerArrived`, `RoomObjectTaken` [stub for now], `RoomObjectDropped` [stub for now]) and the two player-scoped events (`PlayerCurrentRoomChanged`, `PlayerInventoryChanged` [stub for now]). For `RoomPlayerArrived`/`RoomPlayerLeft`: pattern-guard on `actor_id == current_player.id` → `{:noreply, socket}` (discard per FR-029); otherwise append the appropriate `:system` entry. For `PlayerCurrentRoomChanged`: if `:awaiting_room_change_ack` is set in socket assigns → clear it and discard; else unsubscribe from old room topic, subscribe to new room topic, update assigns, append a fresh `:room` entry via `look_room/1`.
- [ ] T060 [US2] Extend `GameLive.mount/3` FR-022 recovery: after the `current_room_of/1` query in T045, if `player_state` row exists but `current_room_id == nil` (i.e., the projector NULLed it because the room is gone), dispatch a fresh `SpawnPlayer` to the starting room AND append a `:system` log entry: `"Your previous location is no longer reachable. You find yourself back at the start."`.
- [ ] T061 [P] [US2] Extend `test/agenticrealms/world/command_parser_test.exs` to cover rows 9–17 (every direction + `go` ambiguities).
- [ ] T062 [P] [US2] Add `test/agenticrealms/world/player_test.exs` aggregate tests: `SpawnPlayer` then `MovePlayer` succeeds; `MovePlayer` with stale `from_room_id` rejects; `MovePlayer` updates `current_room_id` correctly via `apply/2`.
- [ ] T063 [P] [US2] Add `test/agenticrealms/world/direction_test.exs` covering `parse/1` (every alias including whitespace/case variations) and `opposite/1` (all six pairings).
- [ ] T064 [US2] Extend `test/agenticrealms_web/live/game_live_test.exs` with: (a) movement happy path (player in atrium types `north`, sees corridor); (b) FR-007 case (player in corridor tries `north`, sees "You can't go that way"); (c) two-client witness propagation (`Phoenix.LiveViewTest.live/2` for two players, one moves, the other receives an arrival/departure entry in their log); (d) FR-022 recovery (manually delete the room from `world_rooms`, re-mount, assert spawn-to-atrium + system message).

**Checkpoint**: A player can traverse the full seeded map in both directions. Witnesses see arrival and departure messages in real time. Deleted-room recovery works.

---

## Phase 6: User Story 3 - Player Takes and Drops Objects (Priority: P1)

**Goal**: A player can `take <object>` to move a room's object into their inventory and `drop <object>` to do the reverse. Fixed objects refuse take. Same-room witnesses see `RoomObjectTaken`/`RoomObjectDropped` log entries in real time. The concurrent take race (Q1) is resolved by Room aggregate serialization. FR-023 (objects return to room on account deletion) is wired.

**Independent Test**: Run quickstart §3 single-player steps 4–7, 9–12 (full take/drop cycle including fixed-object refusal), two-player steps 22–25 (witness propagation), and the race scenario step 28.

### Implementation

- [ ] T065 [P] [US3] Create the `TakeObject` command struct in `lib/agenticrealms/world/commands/take_object.ex` with `room_id`, `player_id`, `object_id`.
- [ ] T066 [P] [US3] Create the `DropObject` command struct in `lib/agenticrealms/world/commands/drop_object.ex` with `room_id`, `player_id`, `object_id`.
- [ ] T067 [P] [US3] Create the `ObjectTakenFromRoom` event struct in `lib/agenticrealms/world/events/object_taken_from_room.ex` with `room_id`, `player_id`, `object_id`.
- [ ] T068 [P] [US3] Create the `ObjectDroppedInRoom` event struct in `lib/agenticrealms/world/events/object_dropped_in_room.ex` with `room_id`, `player_id`, `object_id`.
- [ ] T069 [US3] Implement `execute/2` and `apply/2` clauses on `AgenticRealms.World.Room` for `TakeObject` and `DropObject` per `contracts/commands.md` §C4–C5. `TakeObject` returns `{:error, :object_not_in_room}` when `object_id ∉ object_ids` (the FR-011 / Q1 race-loser path) and `{:error, :object_is_fixed}` when `known_objects[object_id].fixed == true`. `DropObject` returns `{:error, :object_already_in_room}` when `object_id ∈ object_ids`.
- [ ] T070 [US3] Register `TakeObject` and `DropObject` in the router under the existing Room dispatch block.
- [ ] T071 [US3] Implement `handle/2` clauses on `WorldProjector` for `ObjectTakenFromRoom` (UPDATE `world_objects` SET `room_id = NULL`, `player_id = event.player_id` WHERE `id = event.object_id`) and `ObjectDroppedInRoom` (UPDATE … SET `room_id = event.room_id`, `player_id = NULL` WHERE `id = event.object_id`). Use a single `Ecto.Repo` transaction per event.
- [ ] T072 [US3] Implement `handle/2` clauses on `UIEventBroadcaster` for `ObjectTakenFromRoom` (broadcast `RoomObjectTaken` on `"room:#{room_id}"` and `PlayerInventoryChanged{change: :added}` on `"player:#{player_id}"`) and `ObjectDroppedInRoom` (symmetric, `change: :removed`). Resolve `actor_username` and `object_name` via the read models inside the handler.
- [ ] T073 [US3] Extend `World.Queries` with `resolve_object_in_room/2(room_id, name)` and `resolve_object_in_inventory/2(player_id, name)` returning `{:ok, object_id} | {:error, :no_such_object | :ambiguous}` (per `data-model.md` §4). Use `LOWER(name) = LOWER(?)` and collapse internal whitespace before matching.
- [ ] T074 [US3] Extend `World.Commands` with `take/2(player_id, name)` and `drop/2(player_id, name)`. Both look up the player's current room first; `take` then calls `resolve_object_in_room/2`; `drop` calls `resolve_object_in_inventory/2`. Pre-dispatch errors return `{:error, :no_such_object | :ambiguous | :not_in_inventory}` without touching the aggregate. Otherwise dispatch the command and translate aggregate errors per the contract.
- [ ] T075 [US3] Extend `World.CommandParser` to handle `take`/`get`/`pick` and `drop`/`put` verbs per `contracts/parser.md` rows 18–25. Empty target → `{:invalid_take_target}` / `{:invalid_drop_target}`.
- [ ] T076 [US3] Extend `GameLive.handle_event("submit_command", ...)` to dispatch `{:take, name}` / `{:drop, name}` results to `World.Commands.take/2` / `drop/2`. Map every error atom from the spec's contract table in `commands.md` § "Command → log-entry mapping" to the prescribed log entry. Successful take/drop also updates a cached `:current_room_objects` socket assign so the room block UI updates immediately for the actor (the actor does not receive their own `RoomObjectTaken`/`Dropped` broadcast, per FR-029, so the assign must be mutated locally).
- [ ] T077 [US3] Implement the `handle_info/2` clauses for `RoomObjectTaken` and `RoomObjectDropped` in `GameLive` (replacing the stubs added in T059). Same actor-exclusion guard. On accept: append `:system` entry "<actor_username> takes the <object_name>." or "<actor_username> drops the <object_name>." and mutate the cached `:current_room_objects` assign.
- [ ] T078 [US3] Implement the `handle_info/2` clause for `PlayerInventoryChanged` (replacing the stub from T059): update the cached inventory list in the socket assigns. Do NOT append a log entry (per `contracts/ui_events.md` §U6). The Inventory HUD card re-renders from the updated assign on the next render.
- [ ] T079 [US3] FR-023: extend `AgenticRealms.Accounts.delete_player/1` (or whatever name exists in `lib/agenticrealms/accounts.ex`) to wrap the player deletion in an `Ecto.Multi` that first reads `player_state.current_room_id` for the deleting player, then `UPDATE world_objects SET player_id = NULL, room_id = ? WHERE player_id = ?`, then deletes the player. If `current_room_id` is `nil` (player has no current room), update objects to set `room_id` to the seeded starting room instead — never leave objects with both columns nil.
- [ ] T080 [P] [US3] Extend `test/agenticrealms/world/command_parser_test.exs` with rows 18–25 + 29–30 (take/drop variants including case and trailing whitespace).
- [ ] T081 [P] [US3] Extend `test/agenticrealms/world/room_test.exs` aggregate tests with: take success; take fixed → `:object_is_fixed`; take when object absent → `:object_not_in_room`; drop success; drop when object already in room → `:object_already_in_room`; the race scenario (two takes in sequence on the same aggregate state — the second sees `:object_not_in_room`).
- [ ] T082 [P] [US3] Add `test/agenticrealms/world/projections_test.exs` covering: `ObjectPlacedInRoom` → object row with `room_id` set; `ObjectTakenFromRoom` → `room_id NULL`, `player_id` set; `ObjectDroppedInRoom` → `room_id` set, `player_id NULL`; `PlayerSpawned` and `PlayerMoved` → `player_state` updates including the FR-022 nilify case.
- [ ] T083 [P] [US3] Add `test/agenticrealms/world/ui_event_broadcaster_test.exs`: subscribe a test process to a room topic, dispatch a TakeObject, assert the right `RoomObjectTaken` payload arrives. Subscribe to a player topic, assert `PlayerInventoryChanged{change: :added}` is delivered.
- [ ] T084 [US3] Extend `test/agenticrealms_web/live/game_live_test.exs` with: (a) take happy path; (b) take fixed → system message; (c) take missing object → system message; (d) drop in same room → object returns; (e) drop in different room → object moves; (f) two-client witness propagation for both take and drop; (g) concurrent-take race (use `Task.async`/`await` to dispatch two `take` calls from two players against the same object, assert exactly one succeeds and the other gets `:object_not_in_room`); (h) FR-023 account-deletion test (player A in atrium with brass lantern, delete A's account, query atrium contents and assert brass lantern is present).

**Checkpoint**: The full take/drop loop works for one and multiple players. The race condition is provably handled. Account deletion returns inventory to the world.

---

## Phase 7: User Story 4 - Player Inspects Inventory (Priority: P2)

**Goal**: The `inventory` command (with aliases `inv` and `i`) emits a `:system` log entry listing all carried objects. The Inventory HUD card is wired to the same data and the 001 mock affordances (equipped marker, carried/worn status, quantity badge, filter input) are removed per FR-031 / Q3.

**Independent Test**: Run quickstart §3 single-player steps 3, 6 (inventory empty + after take). Open the Inventory HUD card and confirm name + short description columns only.

### Implementation

- [ ] T085 [US4] Extend `World.Queries` with `list_inventory/1(player_id)` returning a list of `%{id, name, short_description}` from `world_objects WHERE player_id = ? ORDER BY name` (per `data-model.md` §4).
- [ ] T086 [US4] Extend `World.CommandParser` to recognize `inventory`, `inv`, `i` and return `{:inventory}` (per `contracts/parser.md` row 8).
- [ ] T087 [US4] Extend `GameLive.handle_event("submit_command", ...)` to handle `{:inventory}`: call `World.Queries.list_inventory/1`; append a `:system` log entry. When empty: "You aren't carrying anything." When non-empty: a multi-line entry listing each object's name and short description (one line per object).
- [ ] T088 [US4] FR-031: modify the Inventory HUD card render in `lib/agenticrealms_web/components/game_components.ex` and `lib/agenticrealms_web/live/game_live.html.heex` (wherever the inventory modal/card markup lives — likely both a HUD card variant and a modal variant). REMOVE: equipped marker, carried/worn status badge, quantity badge, filter input. KEEP: a single tile/row per object showing only the object's name and short description. Replace the data source from `GameData.inventory()` to the `:inventory` socket assign populated from `World.Queries.list_inventory/1` (or directly from `PlayerInventoryChanged` events). The `:inventory` socket assign should be initialized in `GameLive.mount/3` and updated by the `handle_info/2` for `PlayerInventoryChanged`.
- [ ] T089 [US4] Extend `GameLive.mount/3` to assign `:inventory` from `World.Queries.list_inventory/1` for the current player at mount time. Replace `assign(:inventory, GameData.inventory())` from the 001 mount.
- [ ] T090 [P] [US4] Extend `test/agenticrealms/world/command_parser_test.exs` with row 8 (`inventory` / `inv` / `i` / `INV`).
- [ ] T091 [P] [US4] Extend `test/agenticrealms/world/queries_test.exs` with `list_inventory/1` tests: empty inventory, single-object inventory, ordering.
- [ ] T092 [US4] Extend `test/agenticrealms_web/live/game_live_test.exs` with: (a) `inventory` empty case; (b) `inventory` after take case; (c) HUD card matches `inventory` command output (SC-006); (d) HUD card does NOT contain the removed 001 affordances (assert by `refute render(view) =~ "equipped"`, etc.).

**Checkpoint**: The inventory command works and the HUD card is downgraded to match the data this feature actually models. Every story (US1–US5) is now independently functional and observable.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Final clean-up, full quickstart pass, and removal of obsolete 001 mock data from the player view path.

- [ ] T093 Run `mix precommit` and fix all warnings (compile, format, deps.unlock --unused).
- [ ] T094 Walk through `quickstart.md` §3 end to end in two browsers (alice + bob) plus a third tab as alice, recording any deviations. Fix any regressions discovered.
- [ ] T095 [P] Remove references to `GameData.rooms`, `GameData.starting_log`, `GameData.inventory`, and `GameData.presence` from `lib/agenticrealms_web/live/game_live.ex` and its template. The `GameData` module remains in place (it's still used by the wizard mock view), but it must no longer drive the player-side `:log`, `:inventory`, or room rendering.
- [ ] T096 [P] Update `AGENTS.md` ONLY if any of the existing Phoenix/Ecto/HEEx guidelines need a corollary for Commanded usage (e.g., aggregate identity is always a string). Skip if no new project-wide rules emerge.
- [ ] T097 [P] Add a short `lib/agenticrealms/world/README.md` (3–5 paragraphs) summarizing the bounded context's structure, the two-tier event vocabulary, and where to look for what. Optional but recommended for future contributors.
- [ ] T098 Run the full test suite (`mix test`) and confirm green. Investigate and fix any flakiness in the multi-client LiveView tests (typical culprit: missing `_ = :sys.get_state(...)` synchronization between dispatch and assertion).
- [ ] T099 [P] Sanity-check the migration sequence (`mix ecto.reset && mix event_store.drop && mix event_store.setup && mix ecto.setup`) on a fresh DB; verify the seed runs and the world is browsable from `iex`.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: no dependencies — can start immediately.
- **Phase 2 (Foundational)**: depends on Phase 1; BLOCKS every user-story phase.
- **Phase 3 (US5 Seed)**: depends on Phase 2.
- **Phase 4 (US1 Look)**: depends on Phase 2 AND Phase 3 (look requires seeded world).
- **Phase 5 (US2 Move)**: depends on Phase 2 AND Phase 3 (movement requires a target room to exist); independent of Phase 4 as a code change, but shares LiveView edits with Phase 4 (T058 modifies the same `handle_event` extended by T046).
- **Phase 6 (US3 Take/Drop)**: depends on Phase 2 AND Phase 3 AND Phase 4 (the `handle_info` stubs in T059 are filled in by T077/T078).
- **Phase 7 (US4 Inventory)**: depends on Phase 6 (the inventory data only becomes interesting once take/drop exists).
- **Phase 8 (Polish)**: depends on every prior phase.

### User Story Independence

US5 (seed) is the only story strictly required by every other story. Within Phases 4–7, US1, US2, US3, and US4 are each individually testable but they share LiveView surfaces — in particular, `GameLive.handle_event/3` and `GameLive.handle_info/2` accumulate clauses across phases. The phases are ordered so that the shared surfaces accept additions rather than rewrites.

### Within Each User Story

- Command + event struct files are independent → can be developed in parallel ([P]).
- Aggregate clauses depend on command/event modules being defined.
- Projector and broadcaster clauses depend on event modules.
- Query / facade / parser layers depend on the underlying read models and events being live.
- LiveView edits depend on every layer beneath them.
- Tests can be written in parallel with their target implementation (no TDD requirement), but they are listed at the END of each story phase to mark "story complete when these pass."

### Parallel Opportunities

- **Phase 1**: T004 is parallel to T001–T003 (different file).
- **Phase 2**: T006, T007, T008, T009, T010, T011, T014, T015, T016, T017 are all independent file creations — parallelize all of them after T005 (migration) completes.
- **Phase 3**: T020–T025 (command + event struct files) are all parallel; T033 (room aggregate test) is parallel to T029–T031 (seed runner / seeds.exs).
- **Phase 4**: T034–T035 (command + event), T040 (RoomView struct), T043 (parser), T047 (parser tests), T048 (queries tests) all parallel.
- **Phase 5**: T050–T051 (cmd + event) parallel; T061, T062, T063 (test files) parallel.
- **Phase 6**: T065–T068 (cmd + event files) parallel; T080, T081, T082, T083 (test files) parallel.
- **Phase 7**: T090, T091 (test files) parallel.
- **Phase 8**: T095, T096, T097, T099 parallel.

---

## Parallel Example: Phase 3 (US5 Seed)

```bash
# After Phase 2 checkpoint, launch the six command/event struct files together:
Task: "Create CreateRoom command struct in lib/agenticrealms/world/commands/create_room.ex"
Task: "Create AddExit command struct in lib/agenticrealms/world/commands/add_exit.ex"
Task: "Create PlaceObject command struct in lib/agenticrealms/world/commands/place_object.ex"
Task: "Create RoomCreated event struct in lib/agenticrealms/world/events/room_created.ex"
Task: "Create ExitAdded event struct in lib/agenticrealms/world/events/exit_added.ex"
Task: "Create ObjectPlacedInRoom event struct in lib/agenticrealms/world/events/object_placed_in_room.ex"

# Then sequentially (each depends on the previous):
# T026 (Room aggregate clauses), T027 (router), T028 (projector clauses), T029 (Seed.run/0), …
```

---

## Implementation Strategy

### MVP First (Phase 3 + Phase 4)

1. Complete Phase 1: Setup.
2. Complete Phase 2: Foundational (CRITICAL — blocks all stories).
3. Complete Phase 3: US5 — world is seeded but no UI interaction yet.
4. Complete Phase 4: US1 — players can spawn into the seeded atrium and `look`.
5. **STOP and VALIDATE**: at this point you have an MVP — a persisted world that players can perceive but not yet manipulate. Demoable.

### Incremental Delivery

1. Setup → Foundational → US5 → US1: persisted world + look. **MVP.**
2. + US2: movement. World becomes navigable.
3. + US3: take/drop. World becomes interactive. Two-player witnesses light up.
4. + US4: `inventory` command + HUD card downgrade. Feature complete.
5. + Polish: green test suite + clean quickstart pass.

### Parallel Team Strategy

With multiple developers:

1. Whole team completes Phase 1 + Phase 2 together (~12 file creations, mostly parallel within Phase 2).
2. Once Phase 2 checkpoint is hit:
   - One developer drives Phase 3 (Seed). Short, sequential.
3. Once Phase 3 checkpoint is hit:
   - Developer A: Phase 4 (Look).
   - Developer B: Phase 5 (Move) — coordinate LiveView edits with Dev A (T046 vs T058).
   - Developer C: Phase 6 (Take/Drop) — depends on Phase 4 LiveView handle_info stubs (T059) being merged.
4. Phase 7 + Phase 8: any developer.

---

## Notes

- [P] tasks = different files, no dependencies on other incomplete tasks. LiveView edits within the same story are NOT parallelizable across tasks (they touch the same file).
- [Story] label maps each task to its user story for traceability.
- Tests are listed at the end of each story phase, not the start. TDD was not requested; the project's `mix precommit` alias gates merge.
- Commit after each task or each logical group of [P] tasks.
- Stop at every Checkpoint to validate the story independently before moving on.
- Aggregate identities MUST be strings — use `AgenticRealms.World.player_stream_id/1` and `room_stream_id/1` everywhere; don't hand-format ids inline.
- Never call `String.to_atom/1` on parser input (AGENTS.md + memory leak risk). The parser uses literal atom pattern matches only.
- The `World.Player` aggregate has NO inventory state. Inventory lives only in `world_objects.player_id` (read model). Don't add it back to the aggregate during implementation — it was deliberately removed in `data-model.md` §1.2.
- Subscriber-side actor exclusion (FR-029) is enforced in `GameLive.handle_info/2`, NOT in the broadcaster. Don't try to filter on the broadcast side.
