# Phase 0 Research — 003 Persisted World

**Date**: 2026-05-18
**Branch**: `003-persisted-world`

The Technical Context in `plan.md` contained no `NEEDS CLARIFICATION` markers — the user's planning input fixed the major choices (Commanded for event sourcing, single PlayerMoved event, look as query-only, two-tier event vocabulary). This document records the remaining technical decisions, the rationale behind each, and the alternatives considered, so that `/speckit-tasks` and the implementation phases have an unambiguous foundation.

---

## D1. Event store adapter

**Decision**: Use `commanded_eventstore_adapter` backed by the `eventstore` Elixir library, which persists events in PostgreSQL using a dedicated database (or schema) named `agenticrealms_eventstore`.

**Rationale**:

- The project already runs PostgreSQL for `agenticrealms_repo`; adding a second database on the same instance is operationally trivial (one connection string in `config/runtime.exs`, one `mix event_store.init` step in `setup`).
- `eventstore` is the canonical pairing with Commanded — first-party support, mature, used in most production Commanded apps. It supports stream-per-aggregate (one stream per room id, one per player id), which is exactly the granularity our aggregates need.
- Keeps every persisted byte inside Postgres → unified backup/restore story.

**Alternatives considered**:

- `commanded_extreme_adapter` (EventStoreDB / Kurrent): adds a separate database server with its own ops surface. Overkill for a starter-map-scale world.
- `commanded_eventstore_adapter` with the same Postgres database (sharing the agenticrealms_repo database, separate schema): the `eventstore` library supports this via the `:schema` config option. We may prefer a separate database for cleaner backup boundaries, but a shared DB with a dedicated schema is acceptable in dev. Decision deferred to `quickstart.md`; either works.
- `Commanded.EventStore.Adapters.InMemory`: only suitable for tests (state evaporates between BEAM restarts, violating FR-001 and SC-004). Used in test environment only.

---

## D2. Aggregate boundary choices

**Decision**: Two aggregate types:

- **`World.Room`** keyed by `room_id`. State: `id, name, description, exits, object_ids, occupant_player_ids`. Handles `CreateRoom`, `AddExit`, `PlaceObject`, `TakeObject`, `DropObject`.
- **`World.Player`** keyed by `player_id` (the `Accounts.Player` integer id, serialized to string for the aggregate identity). State: `id, current_room_id, inventory_object_ids`. Handles `SpawnPlayer`, `MovePlayer`.

**Rationale**:

- **Race safety on take/drop**: Commanded serializes commands per aggregate. The Room aggregate sees take/drop commands in order, so two concurrent `take same_object` from different players are processed sequentially. The first emits `ObjectTakenFromRoom`; the second's `execute/2` checks the post-applied state, sees the object is no longer present, and returns `{:error, :object_not_in_room}` — which the LiveView translates to the standard FR-011 message. This is exactly the Q1 clarification resolution.
- **Move is per-player and emits a single event**: `PlayerMoved{player_id, from_room_id, to_room_id, direction}` lives on the Player aggregate. The Player aggregate validates the move (the destination exists, an exit exists from `current_room` in that direction) by consulting the read model **before** dispatching — see D5. The single event keeps movement non-transactional across the two affected rooms, exactly as the user specified.
- **Read-model occupancy is derived**: the room's `occupant_player_ids` lives in the Room aggregate state for invariant enforcement convenience, but read queries (e.g., `look_room` → "who else is here?") go through the read model populated by the `PlayerStateProjector` reacting to `PlayerSpawned` and `PlayerMoved`. The aggregate's notion of occupancy is a defensive shadow, not the source of truth for queries.

**Alternatives considered**:

- **Single `World` aggregate**: simplest mental model, but a single command queue for the entire world is a scaling and contention non-starter even at small scale, and it discards Commanded's natural per-stream serialization.
- **Player aggregate owns take/drop**: tempting because the event name is "player takes…", but the room's contents are the contested resource — putting take on the Player aggregate breaks the race-safety story. Loser would only discover the race at projection time.
- **Three aggregates (Room, Player, Object)**: would let an object enforce its own "I'm in exactly one place" invariant. Cost is a third aggregate type + a process manager for every operation. Rejected as over-engineering for this feature's scope.

**Naming**: aggregate module path is `AgenticRealms.World.Player`. It coexists with `AgenticRealms.Accounts.Player`; modules that need both will use `alias AgenticRealms.Accounts.Player, as: AccountPlayer` (or alias the World one). The plan-phase rename to "PlayerActor" or "Avatar" was rejected because the spec and codebase already use the term Player consistently, and the aggregate is conceptually still "the player" — just from the world's point of view.

---

## D3. Domain events vs. UI events (the two-tier vocabulary)

**Decision**: Two distinct sets of event modules:

- **Domain events** under `AgenticRealms.World.Events.*`: `RoomCreated`, `ExitAdded`, `ObjectPlacedInRoom`, `ObjectTakenFromRoom`, `ObjectDroppedInRoom`, `PlayerSpawned`, `PlayerMoved`. These are Commanded events: persisted in the event store, immutable, versioned via the standard Commanded upcasting story (out of scope here — version 1 of every event).
- **UI events** under `AgenticRealms.World.UIEvents.*`: `RoomObjectTaken`, `RoomObjectDropped`, `RoomPlayerArrived`, `RoomPlayerLeft`. Plain Elixir structs broadcast via `Phoenix.PubSub`. Not persisted, not versioned — they are derived projections meant for live UI consumption.

**Rationale**:

- The user explicitly requested this separation: "we should maybe maintain two event types — one for the commanded library (the 'real' events) and a UIEvent that captures things like a 'player left' or 'player arrived' event."
- **PlayerMoved (one domain event) → 2 UI events (RoomPlayerLeft, RoomPlayerArrived)**: matches the user's "produces 2 witness notifications — a message to the inhabitants of the room being left and a message to the inhabitants of the room being entered."
- Keeping the persisted event log clean of presentation concerns means we can change the wording or surface of witness notifications later without writing a Commanded event migration.
- The `UIEventBroadcaster` is a `Commanded.Event.Handler` named `:ui_event_broadcaster`. Commanded tracks its position in the stream, so on restart it resumes from where it left off — but UI events are best-effort delivery (a tab that wasn't subscribed at broadcast time simply misses the entry; the next `look` reconciles), so re-broadcasting on resume is acceptable. The handler is idempotent in the sense that re-broadcast UI events will simply re-render entries; we mitigate duplicate-entry annoyance by storing the handler's last-seen position via Commanded's built-in `Commanded.EventStore.subscribe_to` machinery.

**Alternatives considered**:

- **Use domain events directly as PubSub payloads**: simpler, but couples persisted event shape to LiveView assigns. Rejected — UI iteration would require event migrations.
- **Two separate domain events for move (LeftRoom + EnteredRoom)**: would require a process manager to fire both atomically, or accept that the two events can interleave with other room events. Either path violates the user's "single moved event so we don't need moving to be transactional" directive. Rejected.

---

## D4. Read-model projection strategy

**Decision**: Three `Commanded.Event.Handler` projectors that update Ecto-backed read models in the existing `agenticrealms_repo`:

| Projector | Reacts to | Updates |
|---|---|---|
| `RoomProjector` | RoomCreated, ExitAdded, ObjectPlacedInRoom, ObjectTakenFromRoom, ObjectDroppedInRoom | `world_rooms`, `world_exits`, `world_objects.room_id` |
| `PlayerStateProjector` | PlayerSpawned, PlayerMoved | `player_state.current_room_id` |
| `ObjectLocationProjector` | ObjectPlacedInRoom, ObjectTakenFromRoom, ObjectDroppedInRoom | `world_objects.room_id` and `world_objects.player_id` (mutually exclusive) |

`RoomProjector` and `ObjectLocationProjector` overlap on object events; we collapse them into a single `WorldProjector` to keep all `world_*` table updates inside one transaction per event. Final list of projectors:

1. **`WorldProjector`** — every room/exit/object event → all `world_*` tables.
2. **`PlayerStateProjector`** — player events → `player_state`.
3. **`UIEventBroadcaster`** — every event → `Phoenix.PubSub` (see D3).

**Rationale**:

- Commanded's `Commanded.Event.Handler` provides at-least-once delivery with persisted subscription positions. Combined with Ecto transactions per event handler call, this gives us at-least-once + projection idempotence (the projector's update statements are deterministic given the event payload).
- One handler per logical responsibility makes restart and rebuild reasoning local.
- Read models live in the same Postgres DB as `players`, so a single `Ecto.Multi` can be used during seeding if needed.

**Alternatives considered**:

- **In-memory ETS read models**: faster, but lose state on BEAM restart → would need to rebuild from the event store on every boot, which works but adds startup time and complicates testing. PostgreSQL read models give us free durability for the cost we're already paying.
- **Eventual consistency via Phoenix.PubSub only (no Ecto read model)**: untenable. The `look` command (D6) is a read query that needs random access to room state; PubSub is a fan-out broadcaster, not a query substrate.

---

## D5. Command validation: where does it happen?

**Decision**: Validation happens in three concentric layers, each catching the failures it is best suited to:

1. **Parser layer** (`World.CommandParser`): syntax errors. Empty input → `{:empty}`. Unknown verb → `{:unknown, raw_text}`. Malformed args → `{:invalid, reason}`. No database or aggregate touched.
2. **Pre-dispatch layer** (`World.Commands` facade): cheap reads against the read model to construct the command's identifying ids. Example: `take/3` looks up the object id from the player's current room's contents by name. If the read model says the object isn't there, returns `{:error, :no_such_object_here}` without dispatching — same outcome as FR-011, no aggregate call.
3. **Aggregate layer** (`World.Room`, `World.Player`): authoritative invariants. The race winner from a concurrent take consults its own aggregate state in `execute/2`; the loser arrives second, finds the object missing, returns the same `:object_not_in_room` error.

**Rationale**:

- Layer 1 keeps invalid input from ever reaching the command bus. Cheap.
- Layer 2 catches the common case (player typed `take xyzzy` and there's no `xyzzy` here) without paying for an aggregate hydration round trip.
- Layer 3 is the only layer that can catch races, because it's the only layer with serialized access to the authoritative state.

The error vocabulary returned to the LiveView is uniform regardless of which layer caught it — the LiveView only needs to map error atoms to FR-aligned log messages.

**Alternatives considered**:

- **Aggregate-only validation**: cleaner in theory but pays an aggregate hydration round trip for every `take xyzzy` typo. Rejected for snappier UX.
- **Read-model-only validation**: cheap but unsafe under concurrency. Rejected.

---

## D6. `look` as a pure query

**Decision**: `look` does not produce a command, an event, or any read-model write. Implementation: `World.Queries.look_room/1` accepts a player_id, joins `player_state → world_rooms → world_exits` and `world_objects WHERE room_id = current_room_id` and `player_state WHERE current_room_id = … AND player_id <> :self`, and returns a `%RoomView{}` struct the LiveView wraps into a `:room` log entry.

**Rationale**:

- The user explicitly stated: "A player looking at a room does not produce an event, this is query only."
- Avoids polluting the event log with read activity (which would otherwise dominate the stream).
- The `:room` log entry only exists in the player's session-local log assign — it is never broadcast. Other players are not informed when someone looks. (This also resolves an unstated concern: no "Alice peers around" entry will spam the room.)

**Alternatives considered**:

- **Emit a `PlayerLooked` domain event for analytics**: deferred; not justified by any spec FR.

---

## D7. Direction normalization

**Decision**: A single `World.Direction` module canonicalizes any of `"north" | "n" | "go north" | "GO   NoRtH"` to the atom `:north`. The six canonical directions are `:north, :south, :east, :west, :up, :down`. The parser uses this module; aggregate state stores the atom; read-model `world_exits.direction` stores the string form for human-readable schema browsing.

**Rationale**:

- Concentrates the alias matrix in one tested module — FR-006 + FR-017 in one place.
- Atoms internally avoid string comparisons in hot paths and make pattern matches obvious.
- Storing the string in the DB keeps `psql`-driven debugging easy.

**Alternatives considered**:

- **Atoms in the DB via custom Ecto type**: works but obfuscates the schema. Rejected for readability.

---

## D8. Seed strategy and idempotency

**Decision**: `priv/repo/seeds.exs` calls `AgenticRealms.World.Seed.run/0`. The function checks the read model: if `world_rooms` is empty, dispatches the sequence of seed commands (`CreateRoom`, `AddExit`, `PlaceObject`); if non-empty, no-ops and logs a one-line "world already seeded" notice.

The starter map (subject to revision in implementation):

- **room_atrium** (starting room): "Stone Atrium" — wide pillared hall. Contains a **brass lantern** (takeable). Exits: north → corridor, east → library.
- **room_corridor**: "North Corridor" — narrow stone passage. Empty room (no objects). Exits: south → atrium.
- **room_library**: "Dusty Library" — shelves of crumbling tomes. Contains a **leather-bound journal** (takeable) and a **reading lectern** (fixed). Exits: west → atrium.

This satisfies FR-020: 3 rooms, all paired exits (atrium↔corridor, atrium↔library), one room with a takeable object (atrium has lantern, library has journal), one room with a fixed object (library has lectern), one empty room (corridor), one designated starting room (atrium).

**Rationale**:

- Idempotency by read-model presence check is cheaper than introspecting the event store and keeps `mix ecto.setup` and `mix world.seed` safe to rerun.
- The seed dispatches commands rather than writing to read models directly so that the event log is the single source of truth (D1) and reseeding after `ecto.reset` produces a consistent replayable history.

**Alternatives considered**:

- **Seed by direct Ecto inserts**: faster and simpler, but the world would exist in the read models without any underlying event stream — replay would not reconstruct it, breaking the event-sourcing invariant. Rejected.

---

## D9. Real-time UI delivery via Phoenix.PubSub topics

**Decision**: Two topic families on the existing `AgenticRealms.PubSub`:

- `"room:#{room_id}"` — receives `%RoomObjectTaken{}`, `%RoomObjectDropped{}`, `%RoomPlayerArrived{}`, `%RoomPlayerLeft{}` messages. Subscribed to by every `GameLive` whose mounted player's `current_room_id` equals the room id.
- `"player:#{player_id}"` — receives `%PlayerCurrentRoomChanged{}` (so other tabs know to switch their room subscription) and `%PlayerInventoryChanged{}` (so other tabs refresh their HUD card).

When `GameLive` receives a `RoomObjectTaken/Dropped/PlayerArrived/PlayerLeft` whose `actor_id == current_player.id`, it discards the message (per FR-029, FR-035). This is the simplest place to enforce the actor-exclusion rule because the LiveView already has the current player id in its socket.

When `GameLive` receives `PlayerCurrentRoomChanged`, it unsubscribes from the old room topic and subscribes to the new one — keeping the player's other tabs in sync (per FR-032, FR-033).

**Rationale**:

- Phoenix.PubSub is already in the supervision tree (`AgenticRealms.Application` line 14). Zero new infrastructure.
- Topics are room-scoped and player-scoped — the most natural fan-out boundaries given the spec.
- Actor-exclusion on the subscriber side (rather than at broadcast time) is simpler than maintaining per-session topic exclusions.

**Alternatives considered**:

- **Per-session topics**: each tab subscribes to a unique `"session:#{session_id}"` topic so the broadcaster can exclude the actor's session by topic. Adds session bookkeeping for marginal value over subscriber-side filtering.
- **Phoenix.Channels**: heavier than PubSub for a feature that lives entirely inside LiveView's WebSocket. Rejected.

---

## D10. Testing strategy

**Decision**:

- **Aggregate unit tests** under `test/agenticrealms/world/*_test.exs` using `Commanded.Aggregates.Aggregate` (or the lighter `Commanded.Aggregate.Multi` pattern). No event store, no Postgres — pure function tests on `execute/2` and `apply/2`.
- **Projection tests** drive each projector by hand: instantiate the projector module, hand-feed it `%RoomCreated{}` and downstream events, assert the read-model rows.
- **Parser tests** are pure unit tests over the input matrix (FR-006, FR-017, FR-018, FR-019).
- **Integration tests** spin up the full Commanded application against the in-memory event store adapter, dispatch real commands, and assert read-model state.
- **LiveView tests** (`test/agenticrealms_web/live/game_live_test.exs`) use `Phoenix.LiveViewTest`. Two-client tests (witness propagation, multi-session) instantiate two `live/2` calls and assert that one client's command produces the right UI updates in the other.

**Rationale**:

- Aggregate and parser tests are pure and fast — run on every keystroke.
- The in-memory event store adapter lets integration tests run without a per-test database reset of the eventstore Postgres DB (which is much more expensive than `Repo.checkout` for the read-model DB).
- LiveView tests are the only ones that can verify the actor-exclusion rule (FR-029/FR-035) end-to-end.

**Alternatives considered**:

- **Skip aggregate unit tests, rely on integration tests only**: would miss subtle apply/2 bugs and slow down feedback. Rejected.
- **Manual smoke testing in dev only**: insufficient for FR-022 (deleted-room recovery), FR-023 (objects return on account deletion), and the witness/multi-session matrix.

---

## Open items for `/speckit-tasks` and implementation

None of the following block planning; all are encoded as design decisions above and need only to be executed:

- The exact Commanded version (`~> 1.4` is the current stable line as of 2026-Q2; pin in `mix.exs` once installed).
- Whether `eventstore` runs in a dedicated database or a separate schema of the existing one — decided at `quickstart.md` time based on the developer's preference; either is fine.
- The exact starter-map content can be tweaked in `World.Seed` as long as it still satisfies FR-020.

No `NEEDS CLARIFICATION` markers remain. Ready for Phase 1 artifacts.
