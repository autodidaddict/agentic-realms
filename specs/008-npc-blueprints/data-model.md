# Phase 1 Data Model: NPC Blueprints

## 1. Read-model schema: `npc_blueprints`

New table. One row per authored or synthetic blueprint.

| Column            | Type      | Constraints                                                  | Notes                                                          |
|-------------------|-----------|--------------------------------------------------------------|----------------------------------------------------------------|
| `id`              | `string`  | PK, NOT NULL                                                 | Slug for authored (`"garrick_the_innkeeper"`) or UUID5 string for synthetic. |
| `name`            | `string`  | NOT NULL                                                     | Display name. Case preserved. Not unique.                       |
| `short_description` | `string`| NOT NULL                                                     | Short description (room-view rendering for clones).            |
| `long_description`  | `text`  | NOT NULL                                                     | Long description (examination rendering for clones). Non-empty (FR-004). |
| `is_synthetic`    | `boolean` | NOT NULL, DEFAULT false                                      | True for blueprints created via the legacy-event replay path (R3). Future wizard tools may surface this. |
| `inserted_at`     | `utc_datetime` | NOT NULL                                                |                                                                |
| `updated_at`      | `utc_datetime` | NOT NULL                                                |                                                                |

**Indexes**: none beyond PK. Blueprint queries are rare and small-cardinality.

**Why `string` for `id` instead of `binary_id`**: blueprints have human-readable slugs (`garrick_the_innkeeper`) for authored content and deterministic UUID5 strings for synthetic content. Mixing both into a single `string` column is simpler than coercing slugs into UUIDs. Storage cost is negligible (~30 bytes per row).

**Why no `next_serial` column**: the serial counter is owned by the `NPCBlueprint` aggregate, not the read model. The projector computes the next serial for the synthetic-blueprint path via `MAX(serial)` query (see §5).

**Ecto schema** (`lib/agenticrealms/world/schemas/npc_blueprint.ex`):

```elixir
defmodule AgenticRealms.World.Schemas.NPCBlueprint do
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  schema "npc_blueprints" do
    field :name, :string
    field :short_description, :string
    field :long_description, :string
    field :is_synthetic, :boolean, default: false

    has_many :clones, AgenticRealms.World.Schemas.NPCClone, foreign_key: :blueprint_id
    timestamps(type: :utc_datetime)
  end
end
```

## 2. Read-model schema: `npc_clones` (replaces `world_npcs`)

| Column              | Type        | Constraints                                                  | Notes                                                  |
|---------------------|-------------|--------------------------------------------------------------|--------------------------------------------------------|
| `id`                | `binary_id` | PK, NOT NULL                                                 | Clone UUID. Matches the `clone_id` in events.          |
| `blueprint_id`      | `string`    | NOT NULL, FK → `npc_blueprints.id` `on_delete: :restrict`    | Lineage only. Never consulted at render time.          |
| `serial`            | `integer`   | NOT NULL                                                     | Per-blueprint serial. Starts at 1.                     |
| `name`              | `string`    | NOT NULL                                                     | Denormalized from blueprint at clone time (FR-007).    |
| `short_description` | `string`    | NOT NULL                                                     | Denormalized.                                          |
| `long_description`  | `text`      | NOT NULL                                                     | Denormalized.                                          |
| `room_id`           | `binary_id` | NOT NULL, FK → `world_rooms.id` `on_delete: :restrict`       | Location (FR-002).                                     |
| `inserted_at`       | `utc_datetime` | NOT NULL                                                |                                                        |
| `updated_at`        | `utc_datetime` | NOT NULL                                                |                                                        |

**Indexes**:
- `npc_clones(room_id)` — supports `list_npcs_in_room/1`.
- `npc_clones(blueprint_id)` — supports blueprint-lineage queries and FK enforcement.
- UNIQUE `(blueprint_id, serial)` — FR-010.
- UNIQUE `(room_id, LOWER(name))` — FR-015. Replaces feature 007's aggregate-state enforcement; same contract.

**Ecto schema** (`lib/agenticrealms/world/schemas/npc_clone.ex`, formerly `npc.ex`):

```elixir
defmodule AgenticRealms.World.Schemas.NPCClone do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "npc_clones" do
    field :serial, :integer
    field :name, :string
    field :short_description, :string
    field :long_description, :string

    belongs_to :blueprint, AgenticRealms.World.Schemas.NPCBlueprint,
      foreign_key: :blueprint_id,
      type: :string,
      references: :id
    belongs_to :room, AgenticRealms.World.Schemas.Room, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  LPMud-style debug identity. Renders as `<name>#<serial>` (e.g.,
  `Garrick the Innkeeper#1`). For admin / debug / telemetry consumption ONLY.
  Never used in player-facing surfaces (FR-011).
  """
  @spec debug_id(t()) :: String.t()
  def debug_id(%__MODULE__{name: name, serial: serial}) do
    "#{name}##{serial}"
  end
end
```

## 3. Aggregate: `World.NPCBlueprint`

Commanded aggregate identified by `:blueprint_id` (prefix `"npc-blueprint-"`).

```elixir
defstruct id: nil,
          name: nil,
          short_description: nil,
          long_description: nil,
          next_serial: 1,
          clone_ids: MapSet.new()
```

**State semantics**:
- `id == nil` means the blueprint has not been created. All `execute/2` clauses for `SpawnNPCClone` against this state refuse with `{:error, :blueprint_not_found}`.
- `next_serial` is the value to assign to the NEXT spawn. After each `NPCClonedFromBlueprint` is applied, `next_serial` increments by 1.
- `clone_ids` tracks every `clone_id` ever emitted by this blueprint. Used to refuse duplicate `clone_id` dispatches (`{:error, :clone_id_already_used}`).

**Commands**:
- `CreateNPCBlueprint{blueprint_id, name, short_description, long_description}` — only valid against `id == nil`. Validates non-empty descriptions, emits `NPCBlueprintCreated`.
- `SpawnNPCClone{blueprint_id, clone_id, room_id}` — only valid against an initialized blueprint. Validates `clone_id` not in `clone_ids`. Emits `NPCClonedFromBlueprint` with the aggregate's *current* `name`, `short_description`, `long_description`, and `next_serial` materialized into the event payload.

**Events applied to state**:
- `NPCBlueprintCreated` — sets `id`, `name`, `short_description`, `long_description`. `next_serial` stays at 1; `clone_ids` stays empty.
- `NPCClonedFromBlueprint` — `next_serial += 1`; `clone_ids = MapSet.put(clone_ids, clone_id)`.

**Why both `clone_ids` MapSet AND `next_serial` counter**: they protect different invariants. `clone_ids` protects against duplicate dispatch (idempotency / replay safety). `next_serial` is the actual user-facing serial number, monotonic per blueprint. Conceivably you could derive `next_serial` as `MapSet.size(clone_ids) + 1`, but that fails the moment we add per-blueprint clone removal in a future feature (the serial counter must keep moving forward even if clones are deleted). Keeping them separate is forward-compatible.

## 4. Domain events

### `NPCBlueprintCreated`

```elixir
defmodule AgenticRealms.World.Events.NPCBlueprintCreated do
  @derive Jason.Encoder
  @enforce_keys [:blueprint_id, :name, :short_description, :long_description]
  defstruct [:blueprint_id, :name, :short_description, :long_description, version: 1]
end
```

Emitted by `NPCBlueprint` aggregate on a successful `CreateNPCBlueprint` command. Projected into `npc_blueprints` by the `WorldProjector` (upsert, `on_conflict: :nothing`).

### `NPCClonedFromBlueprint`

```elixir
defmodule AgenticRealms.World.Events.NPCClonedFromBlueprint do
  @derive Jason.Encoder
  @enforce_keys [
    :blueprint_id,
    :clone_id,
    :room_id,
    :serial,
    :name,
    :short_description,
    :long_description
  ]
  defstruct [
    :blueprint_id,
    :clone_id,
    :room_id,
    :serial,
    :name,
    :short_description,
    :long_description,
    version: 1
  ]
end
```

Emitted by `NPCBlueprint` aggregate on a successful `SpawnNPCClone`. **Full-copy semantics live here** — the name / short / long fields are stamped into the event from the aggregate's *current* state. The clone row is built from this payload alone; the `blueprint_id` is FK-only (lineage), never read at render time.

Projected into `npc_clones` by the `WorldProjector` (insert). Also picked up by the `UIEventBroadcaster` to broadcast `RoomNPCArrived` on the destination room topic.

### Legacy event: `NPCSpawnedInRoom` (feature 007)

Unchanged on disk. Still in the event store. The `WorldProjector` keeps a handler for it that:
1. Derives a deterministic synthetic blueprint id (UUID5 of `(name, short_description, long_description)`).
2. Upserts a `npc_blueprints` row with `is_synthetic: true`.
3. Computes the next serial as `SELECT COALESCE(MAX(serial), 0) + 1 FROM npc_clones WHERE blueprint_id = ?`.
4. Inserts the `npc_clones` row with the computed serial and the event's denormalized payload.

`UIEventBroadcaster` also keeps its `NPCSpawnedInRoom` handler so legacy events continue to broadcast `RoomNPCArrived` correctly.

## 5. Synthetic blueprint id derivation

A single helper in the projector (or in a dedicated `World.Projections.SyntheticBlueprintId` module):

```elixir
@namespace UUID.uuid5(:nil, "agenticrealms:legacy-npc-spawn")

@spec synthetic_blueprint_id(String.t(), String.t(), String.t()) :: String.t()
def synthetic_blueprint_id(name, short_description, long_description) do
  UUID.uuid5(@namespace, "#{name}|#{short_description}|#{long_description}")
end
```

The result is a 36-character UUID string (e.g., `"7c9f...a1b2"`). It is stored directly in `npc_blueprints.id` (which is a string column), distinguishable from authored slugs by visual inspection.

## 6. Full-copy invariants summary

| ID  | Invariant                                                                                                            | Enforced by                                                                          |
|-----|----------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------|
| I-1 | Every clone has exactly one blueprint at spawn time.                                                                  | `npc_clones.blueprint_id NOT NULL` + FK to `npc_blueprints`.                          |
| I-2 | A clone's data fields are immutable once set by the projector (post-spawn).                                          | Conventional: no code path updates `npc_clones` rows except via the spawn projection. |
| I-3 | A clone's `name`, `short_description`, `long_description` reflect the blueprint's values *at the moment of cloning*.  | Aggregate's `execute/2` stamps current state into the emitted event.                  |
| I-4 | Subsequent blueprint edits do NOT propagate to existing clones.                                                       | No `UpdateBlueprint` command exists (FR-005a). Tests use direct DB writes to verify.  |
| I-5 | Per-blueprint serial is monotonic across clones.                                                                      | Aggregate's `next_serial` + DB unique index on `(blueprint_id, serial)`.              |
| I-6 | Per-room display name uniqueness preserved (FR-015).                                                                  | DB unique index `npc_clones(room_id, LOWER(name))` + pre-dispatch read-model check.   |
| I-7 | Blueprints cannot be deleted while clones reference them (FR-016).                                                    | FK `on_delete: :restrict` on `npc_clones.blueprint_id`.                               |
| I-8 | Synthetic-blueprint creation is idempotent under replay.                                                              | UUID5 derivation + `on_conflict: :nothing` upsert.                                    |
| I-9 | Player-facing surfaces never render `#serial`.                                                                        | No call sites of `Schemas.NPCClone.debug_id/1` exist in any LiveView / component module. Enforced by a test that greps for `debug_id` references. |
