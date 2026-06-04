# Phase 1 Data Model: Wizard-Created Object Blueprints (Milestone 1)

## 1. Read-model tables

### 1.1 `players` (extended)

| Column            | Type             | Constraints                                       | Notes                                          |
|-------------------|------------------|---------------------------------------------------|------------------------------------------------|
| `id`              | `bigserial`      | PK, NOT NULL                                      | Existing.                                      |
| `username`        | `string`         | NOT NULL, UNIQUE                                  | Existing.                                      |
| `hashed_password` | `string`         | NOT NULL                                          | Existing.                                      |
| `theme`           | `string`         | NOT NULL DEFAULT `"phosphor"`                     | Existing.                                      |
| `density`         | `string`         | NOT NULL DEFAULT `"comfortable"`                  | Existing.                                      |
| `is_wizard`       | `boolean`        | NOT NULL DEFAULT `false`                          | **NEW (FR-WIZ-1).** Backfilled `false`.        |
| `inserted_at`     | `utc_datetime`   | NOT NULL                                          | Existing.                                      |
| `updated_at`      | `utc_datetime`   | NOT NULL                                          | Existing.                                      |

**Migration `add_is_wizard_to_players`**: `ALTER TABLE players ADD COLUMN is_wizard boolean NOT NULL DEFAULT false`.

**Ecto schema** (`lib/agenticrealms/accounts/player.ex`, modified): add `field :is_wizard, :boolean, default: false`.

### 1.2 `object_blueprints` (new)

| Column              | Type             | Constraints                                                                                       | Notes                                                              |
|---------------------|------------------|---------------------------------------------------------------------------------------------------|--------------------------------------------------------------------|
| `id`                | `string`         | PK, NOT NULL, CHECK `id ~ '^[a-z][a-z0-9_]*$'`, CHECK `length(id) BETWEEN 1 AND 64`               | The slug (FR-007a). UUID-shaped strings forbidden by the regex.    |
| `kind`              | `string`         | NOT NULL, CHECK `kind = 'object'`                                                                 | Milestone 1 only. Milestone 2 adds `'npc'` to the CHECK list.      |
| `name`              | `string`         | NOT NULL                                                                                          | Human-readable name displayed in UI.                               |
| `short_description` | `string`         | NOT NULL                                                                                          | Single-line description denormalized into spawned objects.         |
| `long_description`  | `text`           | NOT NULL                                                                                          | Multi-line description shown on examine.                           |
| `fixed`             | `boolean`        | NOT NULL DEFAULT `false`                                                                          | Whether objects spawned from this are pickable.                    |
| `revision`          | `integer`        | NOT NULL DEFAULT 1, CHECK `revision > 0`                                                          | Monotonic counter (FR-008). Increments only on field-changing edits. |
| `inserted_at`       | `utc_datetime`   | NOT NULL                                                                                          | Creation time.                                                     |
| `updated_at`        | `utc_datetime`   | NOT NULL                                                                                          | Last edit time (matches revision change).                          |

**Indexes**:
- Implicit PK index on `id` — covers single-row reads, registry-list queries (`ORDER BY name LIMIT 200` is sub-millisecond at milestone-1 volumes).
- `CREATE INDEX object_blueprints_kind_idx ON object_blueprints (kind)` — supports milestone 2's mixed-kind queries.

**Migration `create_object_blueprints`** (sketch):

```sql
CREATE TABLE object_blueprints (
  id text PRIMARY KEY CHECK (id ~ '^[a-z][a-z0-9_]*$') CHECK (length(id) BETWEEN 1 AND 64),
  kind text NOT NULL CHECK (kind = 'object'),
  name text NOT NULL,
  short_description text NOT NULL,
  long_description text NOT NULL,
  fixed boolean NOT NULL DEFAULT false,
  revision integer NOT NULL DEFAULT 1 CHECK (revision > 0),
  inserted_at timestamp(0) without time zone NOT NULL,
  updated_at timestamp(0) without time zone NOT NULL
);
CREATE INDEX object_blueprints_kind_idx ON object_blueprints (kind);
```

**Ecto schema** (`lib/agenticrealms/world/schemas/object_blueprint.ex`, new):

```elixir
defmodule AgenticRealms.World.Schemas.ObjectBlueprint do
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  schema "object_blueprints" do
    field :kind, :string, default: "object"
    field :name, :string
    field :short_description, :string
    field :long_description, :string
    field :fixed, :boolean, default: false
    field :revision, :integer, default: 1
    timestamps(type: :utc_datetime)
  end
end
```

### 1.3 `world_objects` (unchanged)

The existing schema covers everything milestone 1 needs. **No** new columns. The schema is reproduced here for reference:

| Column                 | Type             | Notes                                              |
|------------------------|------------------|----------------------------------------------------|
| `id`                   | `binary_id`      | PK. Existing.                                      |
| `name`                 | `string`         | Denormalized at spawn from blueprint or prompt.    |
| `short_description`    | `string`         | Same.                                              |
| `long_description`     | `text`           | Same.                                              |
| `fixed`                | `boolean`        | Same.                                              |
| `behaviors`            | `{:array, :map}` | **Out of scope for milestone 1.** Stays `[]`.      |
| `room_id`              | `binary_id`      | Room location. Mutually exclusive with `player_id`.|
| `player_id`            | `bigint`         | Inventory location. Mutually exclusive with `room_id`. |
| `quest_player_id`      | `bigint`         | Quest-scoped (feature 013). Stays NULL here.       |
| `quest_instance_id`    | `binary_id`      | Quest-scoped (feature 013). Stays NULL here.       |
| `inserted_at`          | `utc_datetime`   | Existing.                                          |
| `updated_at`           | `utc_datetime`   | Bumped on `EditObject`.                            |

**Crucially: no `blueprint_id` column is added.** This is the load-bearing invariant from FR-013.

## 2. Commanded aggregates

### 2.1 `ObjectBlueprint` (new)

**Identification**: `identify(ObjectBlueprint, by: :blueprint_id, prefix: "object-blueprint-")`. The blueprint_id is the slug.

**State**:

```elixir
defstruct id: nil,                     # the slug, nil until created
          kind: "object",
          name: nil,
          short_description: nil,
          long_description: nil,
          fixed: false,
          revision: 0                   # 0 until creation event; 1+ thereafter
```

**Commands & handlers**:

- `CreateObjectBlueprint{blueprint_id, kind, name, short_description, long_description, fixed}` against `id: nil` → emits `ObjectBlueprintCreated{...payload, revision: 1}`. Against initialized state returns `{:error, :already_exists}`.
- `EditObjectBlueprint{blueprint_id, expected_revision, fields_changed}` against initialized state:
  - If `expected_revision != revision`, returns `{:error, :stale_revision, current_revision: revision}`.
  - If `fields_changed` is empty or every field equals current state, returns `:ok` (no event, FR-008).
  - Otherwise emits `ObjectBlueprintEdited{blueprint_id, fields_changed, revision: revision + 1}`.
- (No `DeleteObjectBlueprint` per Q2.)

**Events applied to state**:
- `ObjectBlueprintCreated` → sets all fields, `revision = 1`.
- `ObjectBlueprintEdited` → applies `fields_changed` over current state, `revision = new_revision`.

### 2.2 `Room` aggregate (extended)

The existing `World.Room` aggregate (which already owns object placement via spec 007 / 013) gains three commands:

- `SpawnObjectFromBlueprint{room_id, object_id, blueprint_id, name, short_description, long_description, fixed, wizard_id}` — the dispatcher reads the current blueprint payload and stamps it into the command before dispatching. The aggregate validates the destination room exists and emits `ObjectSpawned{object_id, room_id, name, short_description, long_description, fixed}`. **`blueprint_id` is NOT in the event** — only on the command (for audit purposes inside the aggregate's call path).
- `SpawnObjectFreeform{room_id, object_id, name, short_description, long_description, fixed, wizard_id}` — emits the same `ObjectSpawned{...}` event shape.
- `EditObject{room_id, object_id, fields_changed, wizard_id}` — emits `ObjectEdited{object_id, fields_changed}`. The Room aggregate looks up the object's current location (must be in this room) before accepting; if the object has moved, returns `{:error, :object_not_in_room}`.

The Room aggregate's state does not gain new fields. Object-presence is already tracked in the existing `Room` aggregate state via the spec 007 lineage.

## 3. Domain events

All payload field types are Elixir terms (atoms, strings, integers, maps); the underlying serialization is `Jason` JSONB per the existing convention.

### 3.1 `ObjectBlueprintCreated`

| Field               | Type     | Notes                                                  |
|---------------------|----------|--------------------------------------------------------|
| `blueprint_id`      | `string` | The slug. Mandatory operand identifier (per user feedback during clarification). |
| `kind`              | `string` | `"object"` in milestone 1.                             |
| `name`              | `string` |                                                        |
| `short_description` | `string` |                                                        |
| `long_description`  | `string` |                                                        |
| `fixed`             | `bool`   |                                                        |
| `revision`          | `int`    | Always `1` on this event.                              |

### 3.2 `ObjectBlueprintEdited`

| Field             | Type     | Notes                                                  |
|-------------------|----------|--------------------------------------------------------|
| `blueprint_id`    | `string` | The slug. Mandatory operand identifier.                |
| `fields_changed`  | `map`    | Sparse — only the fields the wizard actually changed.  |
| `revision`        | `int`    | The new revision (= previous + 1).                     |

### 3.3 `ObjectSpawned`

| Field               | Type        | Notes                                                  |
|---------------------|-------------|--------------------------------------------------------|
| `object_id`         | `binary_id` | New world-object UUID.                                 |
| `room_id`           | `binary_id` | Destination room.                                      |
| `name`              | `string`    | Denormalized payload.                                  |
| `short_description` | `string`    |                                                        |
| `long_description`  | `string`    |                                                        |
| `fixed`             | `bool`      |                                                        |

**Absent fields**: `blueprint_id` (FR-013 / FR-029).

### 3.4 `ObjectEdited`

| Field             | Type        | Notes                                                  |
|-------------------|-------------|--------------------------------------------------------|
| `object_id`       | `binary_id` | The world object being edited.                         |
| `fields_changed`  | `map`       | Sparse diff.                                           |

**Absent fields**: `blueprint_id` (FR-032).

### 3.5 `WizardEnteredTrance` (transient)

| Field          | Type           | Notes                                            |
|----------------|----------------|--------------------------------------------------|
| `wizard_id`    | `bigint`       | The `players.id` of the wizard whose mode flipped.|
| `room_id`      | `binary_id`    | The wizard's current room at the moment of flip. |
| `at`           | `utc_datetime` | Timestamp for ordering with other events.        |

### 3.6 `WizardExitedTrance` (transient)

Same shape as `WizardEnteredTrance`.

## 4. Lifecycle / state transitions

### 4.1 `ObjectBlueprint` aggregate lifecycle

```text
[no state] --CreateObjectBlueprint--> [revision: 1]
                                      |
                                      |--EditObjectBlueprint(expected=N, diff)-->
                                      |    if revision != N: stale, no event
                                      |    if diff is empty: ok, no event
                                      |    otherwise: emit ObjectBlueprintEdited, revision = N+1
                                      |
                                      |--CreateObjectBlueprint--> {:error, :already_exists}
```

There is no terminal state. Blueprints persist forever in milestone 1 (no delete per Q2).

### 4.2 World `Object` lifecycle (this milestone's slice)

```text
[no state] --SpawnObjectFromBlueprint or SpawnObjectFreeform-->
              [world_objects row exists, in some room]
              |
              |--EditObject(diff)--> world_objects row updated
              |
              |--(existing take/drop/quest paths from prior features)
```

The Object lifecycle from features 003/006/007/013 is unchanged. Edit-in-place via `EditObject` is the only new transition this milestone adds.

### 4.3 Wizard authoring mode (in-memory only)

```text
LiveView mount:
  if player.is_wizard: authoring_mode := :world
  else: no authoring_mode (player view only)

[:world] --toggle_authoring_mode--> [:blueprints]
                                    (emits WizardEnteredTrance)
[:blueprints] --toggle_authoring_mode--> [:world]
                                          (emits WizardExitedTrance)
[:world] --extract_essence--> [:blueprints]
                              (emits WizardEnteredTrance + opens draft)

LiveView terminate (disconnect):
  if authoring_mode == :blueprints: NO WizardExitedTrance event (per FR-005)
```

## 5. Validation rules summary

- **Blueprint id**: regex `^[a-z][a-z0-9_]*$`, length 1–64, globally unique (PK constraint). Auto-derived from `name` by lowercasing + non-alphanumeric → `_` + trimming leading/trailing `_`. Wizard-overridable before commit. Immutable after commit.
- **Blueprint revision**: starts at 1, monotonic, only bumps on field-changing commits.
- **Object spawn destination**: must be an existing `Room`. Enforced by the Room aggregate's existence check.
- **Object edit target**: must currently be in the wizard's current room. Enforced by the Room aggregate.
- **Wizard authorization**: checked in `Commands` wrapper (synchronous read of `players.is_wizard`); enforced at the aggregate boundary by inclusion of `wizard_id` in the command and assertion at dispatch time.
- **Optimistic lock**: `EditObjectBlueprint.expected_revision` MUST equal aggregate's `revision`. Refused otherwise.

## 6. Cross-references

- Spec FRs covered by this data model: FR-007, FR-007a, FR-007b, FR-008, FR-009, FR-010, FR-011, FR-012, FR-013, FR-014, FR-015, FR-016, FR-017, FR-018, FR-019, FR-020, FR-020a, FR-020b, FR-021, FR-029, FR-030, FR-031, FR-032, FR-033, FR-WIZ-1, FR-WIZ-2, FR-WIZ-5.
- LiveView-side authorization (FR-WIZ-3, FR-WIZ-4) is not a data-model concern — it lives in the LiveView event handlers; see `contracts/commands.md`.
- LLM tool surface (FR-022 through FR-025) is not a data-model concern — see `contracts/intent_tools.md`.
- Registry rendering (FR-026 through FR-028) is read-only against `object_blueprints` plus the `WizardBlueprintRegistryChanged` UI event — see `contracts/ui_events.md`.
