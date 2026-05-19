# Data Model — 003 Persisted World

**Date**: 2026-05-18
**Branch**: `003-persisted-world`
**Companion docs**: [`plan.md`](plan.md), [`research.md`](research.md), [`contracts/commands.md`](contracts/commands.md)

This document defines the three data surfaces this feature introduces:

1. **Aggregate state** — the in-memory state of `World.Room` and `World.Player` aggregates, derived from their event streams. Authoritative for write-side invariants.
2. **Domain event payloads** — the persisted shape of every Commanded event in the world's event store.
3. **Read-model schemas** — Ecto-backed tables in `agenticrealms_repo` that back every `look`/`inventory`/HUD/admin query.

Note: domain events themselves are documented as payloads here (shape only); their full command→event mapping with invariants lives in `contracts/commands.md`. UI events are not persisted and live entirely in `contracts/ui_events.md`.

---

## 1. Aggregate state

### 1.1 `AgenticRealms.World.Room`

Identified by `room_id` (a UUID-v4 string assigned at `CreateRoom` time and used as the Commanded stream identity `"room-<uuid>"`).

```elixir
defstruct id: nil,
          name: nil,
          description: nil,
          exits: %{},           # %{:north => target_room_id, :east => target_room_id, ...}
          object_ids: MapSet.new(),   # objects currently in the room
          occupant_player_ids: MapSet.new(),  # players currently in the room
          known_objects: %{}    # %{object_id => %{name, short_description, long_description, fixed}} — populated by ObjectPlacedInRoom
```

**Invariants enforced by `execute/2`:**

- An exit cannot be added for a direction that already has an exit on this room.
- An object cannot be placed in this room if it is already in `object_ids`.
- `TakeObject{object_id}` requires `object_id ∈ object_ids` AND `known_objects[object_id].fixed == false`.
- `DropObject{object_id}` requires `object_id ∉ object_ids` (i.e., the object is held by some player, not already here).

**State transitions** (applied by `apply/2`):

| Event | State change |
|---|---|
| `RoomCreated{id, name, description}` | initializes the struct |
| `ExitAdded{room_id, direction, target_room_id}` | `exits[direction] = target_room_id` |
| `ObjectPlacedInRoom{room_id, object_id, name, short_description, long_description, fixed}` | `object_ids ← object_ids ∪ {object_id}`; `known_objects[object_id] = {name, …}` |
| `ObjectTakenFromRoom{room_id, player_id, object_id}` | `object_ids ← object_ids \ {object_id}` |
| `ObjectDroppedInRoom{room_id, player_id, object_id}` | `object_ids ← object_ids ∪ {object_id}` |

`occupant_player_ids` is NOT mutated by Room aggregate events — it is a derived projection elsewhere. Rationale: the Player aggregate is the source of truth for "where is this player," and the Room aggregate does not need a transactional join with player movement (per the user's "single moved event" directive).

### 1.2 `AgenticRealms.World.Player`

Identified by `player_id` — the integer primary key of the existing `Accounts.Player` record, stringified to form the Commanded stream identity `"player-<id>"`.

```elixir
defstruct id: nil,
          current_room_id: nil,
          inventory_object_ids: MapSet.new(),
          known_objects: %{}     # %{object_id => %{name, short_description, long_description}} — populated when an object enters inventory
```

**Invariants enforced by `execute/2`:**

- `SpawnPlayer{starting_room_id}` requires `current_room_id == nil` (the aggregate is fresh — i.e., the player has never spawned before). Replays of SpawnPlayer on a hydrated aggregate are rejected at the command layer (`World.Commands.spawn/2` short-circuits via a read-model presence check first).
- `MovePlayer{direction}` requires `current_room_id != nil` AND the resolved exit (passed in as `target_room_id`) is non-nil. Direction-to-target resolution happens at the command layer using the read model; the aggregate only checks that the resolved target id is provided.

**State transitions:**

| Event | State change |
|---|---|
| `PlayerSpawned{player_id, room_id}` | `current_room_id = room_id` |
| `PlayerMoved{player_id, from_room_id, to_room_id, direction}` | `current_room_id = to_room_id` |
| `ObjectTakenFromRoom{room_id, player_id, object_id}` | `inventory_object_ids ← ∪ {object_id}` — only when `player_id == self.id`. Object metadata is fetched from read model and stored in `known_objects` projection-side; aggregate does not need full metadata. |
| `ObjectDroppedInRoom{room_id, player_id, object_id}` | `inventory_object_ids ← \ {object_id}` |

Note that `ObjectTakenFromRoom` and `ObjectDroppedInRoom` are emitted by the **Room** aggregate but the **Player** aggregate also subscribes to them via Commanded's `consistency: :strong` event handler mechanism for self-referential events — or alternatively, the Player aggregate apply/2 is invoked only on its own events and inventory state is rebuilt from a read-model rollup. Implementation detail: prefer the simpler approach of letting `inventory_object_ids` live only in the **read model** (`world_objects WHERE player_id = self.id`) and not in the Player aggregate state, since the aggregate's only enforced invariant about inventory is "is this object currently mine?", which the read model can answer. Final decision (binding for tasks): **Player aggregate does NOT track inventory; inventory lives only in `world_objects.player_id`.** `inventory_object_ids` is removed from the Player aggregate struct.

Revised `World.Player` aggregate struct:

```elixir
defstruct id: nil,
          current_room_id: nil
```

The Player aggregate is intentionally tiny — just enough to enforce "I have exactly one current room" and produce `PlayerMoved` events.

---

## 2. Domain event payloads

All event modules live under `AgenticRealms.World.Events`. Every event includes a `version: 1` field (reserved for future Commanded upcasting); the field is omitted from the shape diagrams below for brevity.

| Event | Fields | Emitted by | Triggered by command |
|---|---|---|---|
| `RoomCreated` | `room_id, name, description` | Room aggregate | `CreateRoom` |
| `ExitAdded` | `room_id, direction, target_room_id` | Room aggregate | `AddExit` |
| `ObjectPlacedInRoom` | `room_id, object_id, name, short_description, long_description, fixed` | Room aggregate | `PlaceObject` |
| `ObjectTakenFromRoom` | `room_id, player_id, object_id` | Room aggregate | `TakeObject` |
| `ObjectDroppedInRoom` | `room_id, player_id, object_id` | Room aggregate | `DropObject` |
| `PlayerSpawned` | `player_id, room_id` | Player aggregate | `SpawnPlayer` |
| `PlayerMoved` | `player_id, from_room_id, to_room_id, direction` | Player aggregate | `MovePlayer` |

**Type notes:**

- `room_id` and `object_id` are UUID strings.
- `player_id` is an integer (the `accounts.players.id`).
- `direction` is a lowercase atom: `:north | :south | :east | :west | :up | :down`. Stored as the atom; serialized by the event store as the string `"north"` etc. via Commanded's default JSON serializer.
- `fixed` is a boolean.

**Stream layout:**

- One stream per Room aggregate: `"room-<uuid>"` — receives all events whose first field is this room's id.
- One stream per Player aggregate: `"player-<integer>"` — receives `PlayerSpawned` and `PlayerMoved` for this player.

`ObjectTakenFromRoom` and `ObjectDroppedInRoom` are emitted on the **Room** stream only (since they are Room aggregate events). The `WorldProjector` updates `world_objects.player_id` from those events; the `PlayerStateProjector` ignores them. Subscribers wanting "this player's inventory just changed" listen via `Phoenix.PubSub` (`PlayerInventoryChanged` UI event in `contracts/ui_events.md`).

---

## 3. Read-model schemas

All read-model tables live in the existing `agenticrealms` PostgreSQL database (the same one as `players`), introduced by a single migration `<TIMESTAMP>_create_world_read_models.exs`. UUID primary keys are stored as PostgreSQL `uuid` columns.

### 3.1 `world_rooms`

```
+--------------------+--------------------+----------------+
| column             | type               | notes          |
+--------------------+--------------------+----------------+
| id                 | uuid PRIMARY KEY   | matches the    |
|                    |                    | aggregate id   |
| name               | varchar NOT NULL   | display name   |
| description        | text NOT NULL      | shown on look  |
| inserted_at        | utc_datetime       | (Ecto std)     |
| updated_at         | utc_datetime       | (Ecto std)     |
+--------------------+--------------------+----------------+
```

**Ecto schema**: `AgenticRealms.World.Schemas.Room`, primary key type `:binary_id`.

### 3.2 `world_exits`

```
+--------------------+--------------------+--------------------------------+
| column             | type               | notes                          |
+--------------------+--------------------+--------------------------------+
| id                 | uuid PRIMARY KEY   |                                |
| source_room_id     | uuid NOT NULL FK   | → world_rooms.id ON DELETE CASCADE |
| direction          | varchar NOT NULL   | "north" | "south" | … | "down" |
| target_room_id     | uuid NOT NULL FK   | → world_rooms.id ON DELETE RESTRICT |
| inserted_at        | utc_datetime       |                                |
| updated_at         | utc_datetime       |                                |
+--------------------+--------------------+--------------------------------+
```

**Indexes / constraints:**

- `UNIQUE(source_room_id, direction)` — each room has at most one exit per direction (FR-006 implies it; the aggregate enforces it).
- `CHECK (direction IN ('north','south','east','west','up','down'))` — defense in depth against bad seed data.

**Ecto schema**: `AgenticRealms.World.Schemas.Exit` with `belongs_to :source_room, Room` and `belongs_to :target_room, Room`.

**Why no "reverse" denormalization**: the spec's Q4 clarification establishes that exits are uniformly one-way. Paired exits are stored as two independent rows; queries that want "is there a way back?" simply look for the reverse-direction row on the target room (used by the seed validator, not by the runtime).

### 3.3 `world_objects`

```
+--------------------+--------------------+---------------------------------------+
| column             | type               | notes                                 |
+--------------------+--------------------+---------------------------------------+
| id                 | uuid PRIMARY KEY   |                                       |
| name               | varchar NOT NULL   | matched case-insensitively by parser  |
| short_description  | varchar NOT NULL   | shown in inventory + look entity row  |
| long_description   | text NOT NULL      | shown when listed in look's object detail |
| fixed              | boolean NOT NULL DEFAULT false |                             |
| room_id            | uuid NULL FK       | → world_rooms.id ON DELETE RESTRICT   |
| player_id          | bigint NULL FK     | → players.id ON DELETE SET NULL       |
| inserted_at        | utc_datetime       |                                       |
| updated_at         | utc_datetime       |                                       |
+--------------------+--------------------+---------------------------------------+
```

**Constraints:**

- `CHECK ((room_id IS NOT NULL) <> (player_id IS NOT NULL))` — exactly one of `room_id` and `player_id` is set. Encodes "an object is in exactly one place" (Game Object key-entity invariant in spec).
- Index on `room_id` (for `look_room` lookups).
- Index on `player_id` (for `list_inventory` lookups).
- Index on `LOWER(name)` (for case-insensitive name matching in the pre-dispatch validation layer, D5).

**FR-023 (account deletion returns objects to room)**: the `player_id` foreign key uses `ON DELETE SET NULL`, but the `CHECK` constraint forbids both columns being null. The Accounts context's `delete_player/1` therefore runs inside an `Ecto.Multi` that: (a) reads the deleted player's `current_room_id` from `player_state`; (b) `UPDATE world_objects SET player_id = NULL, room_id = <that_room_id> WHERE player_id = <deleted>`; (c) deletes the player. This is documented as a behavior addition on the existing `Accounts` context, not as a World concern.

### 3.4 `player_state`

```
+--------------------+--------------------+----------------------------------+
| column             | type               | notes                            |
+--------------------+--------------------+----------------------------------+
| player_id          | bigint PRIMARY KEY | → players.id ON DELETE CASCADE   |
| current_room_id    | uuid NULL FK       | → world_rooms.id ON DELETE RESTRICT |
| inserted_at        | utc_datetime       |                                  |
| updated_at         | utc_datetime       |                                  |
+--------------------+--------------------+----------------------------------+
```

**Notes:**

- One row per player. The row is created by the `PlayerStateProjector` reacting to `PlayerSpawned`; before spawning, a player has no `player_state` row.
- `current_room_id` is nullable specifically to support FR-022 (deleted room recovery): if a `PlayerMoved` event references a room that has been removed from the world, the projector sets `current_room_id = NULL` and the next Play view entry triggers a fresh `SpawnPlayer` into the designated starting room.
- Index on `current_room_id` (for "who else is in this room?" lookups in `look_room`).

### 3.5 Entity relationship summary

```
players (existing)
   │
   │ 1 ─── 1  (player_state.player_id)
   ▼
player_state ─── N → 1 ─── world_rooms ──┐
   (current_room_id NULLable)             │
                                          │ 1 ─── N
                                          │     (world_exits.source_room_id)
                                          ▼
                                       world_exits ─── N → 1 ─── world_rooms
                                                            (target_room_id)

world_objects ─── N → 1 ─── world_rooms  (room_id NULLable)
              \
               ─── N → 1 ─── players   (player_id NULLable; XOR room_id)
```

---

## 4. Query surface (read-side API)

The `AgenticRealms.World.Queries` module exposes the only read functions that LiveView and other contexts should call. All queries are pure Ecto reads against the read models above and return plain structs.

```elixir
@spec look_room(player_id :: integer()) ::
        {:ok, %RoomView{
           id: room_id,
           name: String.t(),
           description: String.t(),
           exits: [%{direction: atom(), target_name: String.t()}],
           objects: [%{id: object_id, name: String.t(), short_description: String.t()}],
           other_players: [%{id: integer(), username: String.t()}]
         }} | {:error, :no_current_room}

@spec list_inventory(player_id :: integer()) ::
        [%{id: object_id, name: String.t(), short_description: String.t()}]

@spec current_room_of(player_id :: integer()) ::
        {:ok, room_id} | {:error, :no_current_room}

@spec occupants_of(room_id :: room_id) :: [%{id: integer(), username: String.t()}]

@spec resolve_object_in_room(room_id :: room_id, name :: String.t()) ::
        {:ok, object_id} | {:error, :no_such_object | :ambiguous}

@spec resolve_object_in_inventory(player_id :: integer(), name :: String.t()) ::
        {:ok, object_id} | {:error, :no_such_object | :ambiguous}
```

The two `resolve_*` helpers implement FR-017 (case-insensitive name matching) and FR-024 (ambiguity detection) at the pre-dispatch validation layer (D5). All other functions are pure projections.

---

## 5. Migration plan

Single migration file `priv/repo/migrations/<TIMESTAMP>_create_world_read_models.exs`. It runs after the existing 002 migrations; no destructive operations and no data movement (this feature adds tables but does not modify `players`).

Sketch:

```elixir
defmodule AgenticRealms.Repo.Migrations.CreateWorldReadModels do
  use Ecto.Migration

  def change do
    create table(:world_rooms, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text, null: false
      timestamps(type: :utc_datetime)
    end

    create table(:world_exits, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :source_room_id, references(:world_rooms, type: :binary_id, on_delete: :delete_all), null: false
      add :direction, :string, null: false
      add :target_room_id, references(:world_rooms, type: :binary_id, on_delete: :restrict), null: false
      timestamps(type: :utc_datetime)
    end
    create unique_index(:world_exits, [:source_room_id, :direction])
    create constraint(:world_exits, :valid_direction,
             check: "direction IN ('north','south','east','west','up','down')")

    create table(:world_objects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :short_description, :string, null: false
      add :long_description, :text, null: false
      add :fixed, :boolean, null: false, default: false
      add :room_id, references(:world_rooms, type: :binary_id, on_delete: :restrict)
      add :player_id, references(:players, on_delete: :nilify_all)
      timestamps(type: :utc_datetime)
    end
    create index(:world_objects, [:room_id])
    create index(:world_objects, [:player_id])
    create index(:world_objects, ["LOWER(name)"], name: :world_objects_lower_name_index)
    create constraint(:world_objects, :exactly_one_location,
             check: "(room_id IS NOT NULL) <> (player_id IS NOT NULL)")

    create table(:player_state, primary_key: false) do
      add :player_id, references(:players, on_delete: :delete_all), primary_key: true
      add :current_room_id, references(:world_rooms, type: :binary_id, on_delete: :restrict)
      timestamps(type: :utc_datetime)
    end
    create index(:player_state, [:current_room_id])
  end
end
```

The event store has its own migrations under `priv/event_store/migrations/`, generated by `mix event_store.init`.
