# Data Model: Maps

## 1. Entities and persistence

### 1.1 Region (NEW)

A first-class map area. Aggregate ID = a binary UUID. Display name is required and unique within the cluster.

**Aggregate state** (`AgenticRealms.World.Region`):

```elixir
defstruct id: nil, name: nil
```

**Read-model schema** (`AgenticRealms.World.Schemas.Region`, table `regions`):

| Column         | Type         | Constraints                          |
|----------------|--------------|--------------------------------------|
| `id`           | binary_id    | PK                                   |
| `name`         | string       | NOT NULL, UNIQUE                     |
| `inserted_at`  | utc_datetime | NOT NULL                             |
| `updated_at`   | utc_datetime | NOT NULL                             |

**Relationships**: has_many `:rooms`, AgenticRealms.World.Schemas.Room, foreign_key: :region_id

### 1.2 Room (EXTENDED)

Existing aggregate and schema gain five fields. The aggregate continues to own exits and object membership.

**Aggregate state additions** (`AgenticRealms.World.Room`):

```elixir
defstruct id: nil,
          name: nil,
          description: nil,
          exits: %{},
          object_ids: MapSet.new(),
          behaviors: [],
          # NEW for feature 012
          region_id: nil,
          map_visible: true,
          elevation: 0,
          map_x: nil,
          map_y: nil
```

**Read-model schema additions** (`AgenticRealms.World.Schemas.Room`, table `world_rooms`):

| Column          | Type        | Constraints                                                            |
|-----------------|-------------|------------------------------------------------------------------------|
| `region_id`     | binary_id   | NOT NULL, FK → `regions.id` ON DELETE RESTRICT                         |
| `map_visible`   | boolean     | NOT NULL DEFAULT TRUE                                                  |
| `elevation`     | integer     | NOT NULL DEFAULT 0                                                     |
| `map_x`         | integer     | NULL                                                                   |
| `map_y`         | integer     | NULL                                                                   |

**Indexes**:
- Partial unique index `world_rooms_unique_position`: `(region_id, elevation, map_x, map_y) WHERE map_x IS NOT NULL AND map_y IS NOT NULL` — enforces FR-022a.
- Btree index on `(region_id, elevation)` — accelerates `MapView` queries.

**Relationships**: belongs_to `:region`. Existing `has_many :exits`, `has_many :objects` unchanged.

### 1.3 Exit (UNCHANGED)

The existing schema and table are unchanged. The new `Exits.Validator` runs *before* command dispatch to enforce FR-024; no schema change is needed because the rule is a relation between two rooms' coordinates and the exit's direction, not a property of the exit row.

The existing unique constraint `(source_room_id, direction)` continues to enforce one-exit-per-direction-per-source. Direction is stored as a string (lowercased canonical form) via `Direction.to_string/1`. The four new directions (`"northeast"`, `"northwest"`, `"southeast"`, `"southwest"`) round-trip through this column transparently.

### 1.4 PlayerDiscoveredRoom (NEW)

A persisted fact: this player has personally entered this room at least once.

**Event** (`AgenticRealms.World.Events.PlayerDiscoveredRoom`):

```elixir
defstruct [:player_id, :room_id, :discovered_at, version: 1]
```

**Read-model schema** (`AgenticRealms.World.Schemas.PlayerDiscoveredRoom`, table `player_discovered_rooms`):

| Column           | Type          | Constraints                                            |
|------------------|---------------|--------------------------------------------------------|
| `player_id`      | bigint        | PK (composite), FK → `players.id` ON DELETE CASCADE    |
| `room_id`        | binary_id     | PK (composite), FK → `world_rooms.id` ON DELETE CASCADE |
| `discovered_at`  | utc_datetime  | NOT NULL                                               |

**Indexes**: PK alone is sufficient for the dominant queries:
- "Is room R discovered by player P?" — composite PK exact lookup.
- "What rooms has player P discovered in region X at elevation E?" — `JOIN world_rooms` filtered by region_id and elevation; the PK is the build side of the hash join. With a secondary index on `(room_id)` we'd accelerate the alternate query "who has discovered room R" — out of scope for v1.

**Lifecycle**:
- Inserted on first arrival via the projection of the `PlayerDiscoveredRoom` event.
- Never updated (discovery is a one-way flag — once discovered, always discovered; `discovered_at` reflects the first visit).
- Deleted only via player or room cascade. Map-visibility toggling does NOT delete discovery rows (FR-014).

## 2. Read-model: MapView

`World.MapView` is a transient, computed projection — not a persisted row. It is built per-request by `World.MapView.for_player/1` and assigned to the LiveView socket.

### 2.1 Struct shape

```elixir
defmodule AgenticRealms.World.MapView do
  defstruct [
    :region_id,            # binary_id of the region the player is currently in
    :region_name,          # display name for the header
    :current_room_id,      # binary_id of the player's current room (or nil if off-map)
    :off_map?,             # boolean — true if the current room is map-hidden OR has no coords
    :viewport_center,      # {x, y} — the (map_x, map_y) of the player's current room, OR {0, 0} when off-map
    :rooms,                # list of %MapView.Room{} — see 2.2
    :exits,                # list of %MapView.Exit{} — see 2.3
    :has_above_rooms?,     # boolean
    :has_below_rooms?      # boolean
  ]
end
```

### 2.2 MapView.Room (rendered room)

```elixir
defmodule AgenticRealms.World.MapView.Room do
  defstruct [
    :id,            # binary_id (used as DOM key only — NOT for fog stubs)
    :name,          # friendly name (used in tooltip)
    :x,             # map_x
    :y,             # map_y
    :is_current?,   # boolean — true for exactly one Room in the list
    :has_up?,       # boolean — true if the room has an Up exit
    :has_down?      # boolean — true if the room has a Down exit
  ]
end
```

**Filter rules** (computed inside `MapView.for_player/1`):
- Room is in the player's current region.
- Room's elevation equals the player's current room's elevation.
- Room has explicit `(map_x, map_y)` set (coords ≠ nil).
- Room is `map_visible: true`.
- Room is in the player's `player_discovered_rooms` set.
- Room is within the configured viewport window (default 11 × 11 cells centered on the player's `map_x`, `map_y`).

### 2.3 MapView.Exit (rendered line or stub)

```elixir
defmodule AgenticRealms.World.MapView.Exit do
  defstruct [
    :kind,           # :normal | :cross_region | :fog_stub
    :from_x,         # source room map_x
    :from_y,         # source room map_y
    :to_x,           # for :normal — target's map_x;
                     # for :fog_stub / :cross_region — one cell into the direction
    :to_y,           # same convention as to_x
    :direction       # atom; used by the renderer to angle fog stubs / cross-region terminators
                     # (NOT exposed to DOM for fog stubs in a way that leaks info — only the
                     # rendered line geometry comes from this field)
  ]
end
```

**Filter rules** (computed inside `MapView.for_player/1`):
- The source room is in the rendered set (see 2.2).
- The target room is NOT map-hidden AND has coords set. (Otherwise the exit is suppressed entirely per FR-006.)
- Cross-region exits emit a `:cross_region` entry (the target room is NOT in the rendered set; the affordance terminator is positioned one cell into the direction).
- Exits from rendered rooms to map-visible, coord-bearing, but UNDISCOVERED target rooms emit a `:fog_stub` entry.
- Exits from rendered rooms to map-visible, coord-bearing, discovered target rooms emit a `:normal` entry IF the target is also in the rendered set; otherwise (target is out of the viewport window) the exit is omitted entirely. (A separate "this exit leads off-screen" affordance is out of scope.)
- Reciprocal exits between the same room pair are deduplicated: only one `:normal` entry per unordered pair is emitted.

### 2.4 Off-map state (FR-003a)

When the player's current room is map-hidden OR has no coordinates set, the `MapView` is computed with:

```elixir
%MapView{
  region_id: region.id,
  region_name: region.name,
  current_room_id: current.id,
  off_map?: true,
  viewport_center: {0, 0},
  rooms: [],
  exits: [],
  has_above_rooms?: false,
  has_below_rooms?: false
}
```

The renderer detects `off_map?: true` and draws only the region-name header. No grid, no glyphs, no affordances.

## 3. Domain events

### 3.1 Existing events extended

**`RoomCreated`** gains fields:

```elixir
defstruct [
  :room_id,
  :name,
  :description,
  behaviors: [],
  # NEW for 012:
  :region_id,         # required at command time, required in event
  map_visible: true,
  elevation: 0,
  map_x: nil,
  map_y: nil,
  version: 1
]
```

The struct preserves the existing `@enforce_keys [:room_id, :name, :description]` and ADDS `:region_id` to the enforce list. Post-purge there are no historical RoomCreated events without `region_id` to worry about.

### 3.2 New events

**`RegionCreated`** (`AgenticRealms.World.Events.RegionCreated`):

```elixir
@derive Jason.Encoder
@enforce_keys [:region_id, :name]
defstruct [:region_id, :name, version: 1]
```

**`PlayerDiscoveredRoom`** (`AgenticRealms.World.Events.PlayerDiscoveredRoom`):

```elixir
@derive Jason.Encoder
@enforce_keys [:player_id, :room_id, :discovered_at]
defstruct [:player_id, :room_id, :discovered_at, version: 1]
```

## 4. State transitions

### 4.1 Region lifecycle

1. **Created**: `CreateRegion(region_id, name)` → `RegionCreated(region_id, name)`. Read-side: insert into `regions`.
2. **No mutation in v1.** No rename, no delete. (Region rename is mentioned only as a future affordance under the Region first-class clarification.)

### 4.2 Room lifecycle (post-purge)

1. **Created**: `CreateRoom(room_id, name, description, region_id, map_visible?, elevation?, map_x?, map_y?, behaviors?)` → `RoomCreated(...)`. Pre-dispatch validation: region exists, `(map_x, map_y)` not in use within `(region_id, elevation)` if non-nil.
2. **Exit added**: `AddExit(room_id, direction, target_room_id)` → `ExitAdded(...)`. Pre-dispatch validation: `Exits.Validator.consistent?/3` returns `:ok` per FR-024.
3. (Other existing room lifecycle — objects placed/taken/dropped — unchanged.)

### 4.3 Discovery lifecycle

1. **Player spawns**: existing `PlayerSpawned(player_id, room_id)` fires. The `PlayerStateProjector` upserts `player_state.current_room_id` as today, AND checks: does `player_discovered_rooms` contain `(player_id, room_id)`? If not, dispatch `RecordRoomDiscovery(player_id, room_id)` → emits `PlayerDiscoveredRoom(player_id, room_id, now)`.
2. **Player moves**: existing `PlayerMoved(player_id, from, to)` fires. Same discovery check against `(player_id, to_room_id)`. Idempotent — moves into already-discovered rooms emit no `PlayerDiscoveredRoom` event.
3. **Read-side projection**: the projector handles `PlayerDiscoveredRoom` by inserting `(player_id, room_id, discovered_at)` into `player_discovered_rooms` with `on_conflict: :nothing`.

## 5. Migration plan

Four migrations, run in order, each replay-safe:

1. **`<ts1>_reset_world_for_maps`**: `TRUNCATE world_rooms, world_exits, world_objects, npc_clones, npc_blueprints RESTART IDENTITY CASCADE; UPDATE player_state SET current_room_id = NULL;`. Paired with a documented one-time event-store reset (`mix do event_store.drop, event_store.create, event_store.init`) — see [quickstart.md](./quickstart.md).
2. **`<ts2>_create_regions`**: creates the `regions` table.
3. **`<ts3>_extend_world_rooms_with_map_fields`**: adds `region_id`, `map_visible`, `elevation`, `map_x`, `map_y` columns; creates the partial unique index; adds the `(region_id, elevation)` btree index. `region_id` is added NOT NULL because the truncate left zero rows.
4. **`<ts4>_create_player_discovered_rooms`**: creates the `player_discovered_rooms` table with the composite PK and the two FKs.

After all four migrations, the seed re-creates the Blackmire region + every seed room with explicit coords + the Atrium Loft (elev=1) + one hidden room + one cross-region exit to Hollowvale. See `lib/agenticrealms/world/seed.ex` for the full layout (specified in [quickstart.md](./quickstart.md) §3).

## 6. Field-by-field validation summary

| Field                            | Rule                                                                                                                             | Enforced by                                          |
|----------------------------------|----------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------|
| `Region.name`                    | Required, non-empty, unique within cluster                                                                                      | DB unique index + pre-dispatch check in commands.ex  |
| `Room.region_id`                 | Required, references existing region                                                                                            | FK + pre-dispatch existence check                    |
| `Room.map_visible`               | Boolean; default true                                                                                                            | NOT NULL DEFAULT in DB                               |
| `Room.elevation`                 | Integer; default 0                                                                                                               | NOT NULL DEFAULT in DB                               |
| `Room.map_x`, `Room.map_y`       | Both nil or both non-nil; integers (no float, no string)                                                                        | Aggregate validation in `execute/2`                  |
| `(region_id, elevation, map_x, map_y)` uniqueness | Partial unique index (only when coords are set) — FR-022a                                                  | DB partial unique index `world_rooms_unique_position`|
| Exit direction consistency       | FR-024 strict-axis match with flexible distance, when both rooms have coords                                                    | `Exits.Validator.consistent?/3` (pre-dispatch)       |
| Exit direction canonical form    | Must be one of the 10 atoms returned by `Direction.canonical/0`                                                                  | `Direction.parse/1` + aggregate execute/2 type check |
| `PlayerDiscoveredRoom` uniqueness| At most one row per (player_id, room_id)                                                                                        | Composite PK + `on_conflict: :nothing` on insert     |
