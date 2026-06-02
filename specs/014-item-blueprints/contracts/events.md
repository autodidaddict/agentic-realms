# Domain Event Contracts: Wizard-Created Object Blueprints (Milestone 1)

All events serialize to JSON via `Jason` and persist to the Commanded event store. Per the `event-log-destroyable-phase` project memory, the event log can be wiped at any time during this phase, so cross-milestone event-stream migrations are unnecessary.

## `ObjectBlueprintCreated`

Emitted by the `ObjectBlueprint` aggregate on successful `CreateObjectBlueprint`. Projected by `ObjectBlueprintProjector` into a new `object_blueprints` row. Also picked up by `UIEventBroadcaster` to fan out a `WizardBlueprintRegistryChanged` UI event.

```elixir
defmodule AgenticRealms.World.Events.ObjectBlueprintCreated do
  @derive Jason.Encoder
  @enforce_keys [:blueprint_id, :kind, :name, :short_description,
                 :long_description, :fixed, :revision]
  defstruct [:blueprint_id, :kind, :name, :short_description,
             :long_description, :fixed, :revision, version: 1]
end
```

| Field               | Type     | Notes                                              |
|---------------------|----------|----------------------------------------------------|
| `blueprint_id`      | `string` | The slug. Always present (mandatory operand).      |
| `kind`              | `string` | `"object"` in milestone 1.                         |
| `name`              | `string` |                                                    |
| `short_description` | `string` |                                                    |
| `long_description`  | `string` |                                                    |
| `fixed`             | `bool`   |                                                    |
| `revision`          | `int`    | Always `1` on this event.                          |
| `version`           | `int`    | Schema version; `1` for now.                       |

## `ObjectBlueprintEdited`

Emitted by the `ObjectBlueprint` aggregate on a field-changing `EditObjectBlueprint`. Projected by `ObjectBlueprintProjector` (updates the row + bumps `revision`).

```elixir
defmodule AgenticRealms.World.Events.ObjectBlueprintEdited do
  @derive Jason.Encoder
  @enforce_keys [:blueprint_id, :fields_changed, :revision]
  defstruct [:blueprint_id, :fields_changed, :revision, version: 1]
end
```

| Field             | Type     | Notes                                              |
|-------------------|----------|----------------------------------------------------|
| `blueprint_id`    | `string` | The slug. Always present.                          |
| `fields_changed`  | `map`    | Sparse diff. Keys ∈ `{:name, :short_description, :long_description, :fixed}`. Values are the new field values. |
| `revision`        | `int`    | The new revision (= previous + 1).                 |

## `ObjectSpawned`

Emitted by the `Room` aggregate on `SpawnObjectFromBlueprint` or `SpawnObjectFreeform`. **The same event shape covers both paths** — the projector and the broadcaster are path-agnostic. Projected by `WorldProjector` into a new `world_objects` row. Picked up by `UIEventBroadcaster` to fan out `RoomObjectArrived` to co-present players.

```elixir
defmodule AgenticRealms.World.Events.ObjectSpawned do
  @derive Jason.Encoder
  @enforce_keys [:object_id, :room_id, :name, :short_description,
                 :long_description, :fixed]
  defstruct [:object_id, :room_id, :name, :short_description,
             :long_description, :fixed, version: 1]
end
```

| Field               | Type        | Notes                                              |
|---------------------|-------------|----------------------------------------------------|
| `object_id`         | `binary_id` | UUID of the new world object.                      |
| `room_id`           | `binary_id` | Destination room.                                  |
| `name`              | `string`    | Denormalized.                                      |
| `short_description` | `string`    |                                                    |
| `long_description`  | `string`    |                                                    |
| `fixed`             | `bool`      |                                                    |

**Explicitly absent**: `blueprint_id`. Per FR-013 and FR-029, the event does not record where the object came from.

## `ObjectEdited`

Emitted by the `Room` aggregate on a field-changing `EditObject`. Projected by `WorldProjector` (updates the `world_objects` row in place). Picked up by `UIEventBroadcaster` to fan out a `RoomObjectEdited` UI event so any player who has the object in their current room view sees the updated examine output on next look.

```elixir
defmodule AgenticRealms.World.Events.ObjectEdited do
  @derive Jason.Encoder
  @enforce_keys [:object_id, :fields_changed]
  defstruct [:object_id, :fields_changed, version: 1]
end
```

| Field             | Type        | Notes                                              |
|-------------------|-------------|----------------------------------------------------|
| `object_id`       | `binary_id` | The object being edited.                           |
| `fields_changed`  | `map`       | Sparse diff. Same keys as `ObjectBlueprintEdited.fields_changed`. |

**Explicitly absent**: `blueprint_id` (FR-032).

## `WizardEnteredTrance` (transient — non-aggregate)

Emitted by `AgenticRealms.World.WizardTrance.enter/2` (a small helper module — see plan.md Source Code section). The event passes through the Commanded event store for ordering / projection purposes but does **not** mutate any aggregate state. The `UIEventBroadcaster` consumes it and emits a `RoomSystemLogEntry` on the wizard's current `room:<room_id>` topic with body `"<wizard display name> enters a trance."`.

```elixir
defmodule AgenticRealms.World.Events.WizardEnteredTrance do
  @derive Jason.Encoder
  @enforce_keys [:wizard_id, :room_id, :at]
  defstruct [:wizard_id, :room_id, :at, version: 1]
end
```

| Field         | Type            | Notes                                         |
|---------------|-----------------|-----------------------------------------------|
| `wizard_id`   | `bigint`        | `players.id` of the entering wizard.          |
| `room_id`     | `binary_id`     | Wizard's current room at the moment of entry. |
| `at`          | `utc_datetime`  | Timestamp.                                    |

## `WizardExitedTrance` (transient)

Same shape as `WizardEnteredTrance`. Produces log entry `"<wizard display name> appears to come out of a trance."`. Suppressed when the wizard disconnects without flipping the toggle (per FR-005).

```elixir
defmodule AgenticRealms.World.Events.WizardExitedTrance do
  @derive Jason.Encoder
  @enforce_keys [:wizard_id, :room_id, :at]
  defstruct [:wizard_id, :room_id, :at, version: 1]
end
```

## Idempotency & replay safety

| Event                       | Projection-side idempotency strategy                                       |
|-----------------------------|----------------------------------------------------------------------------|
| `ObjectBlueprintCreated`    | `Repo.insert!(... on_conflict: :nothing, conflict_target: :id)`            |
| `ObjectBlueprintEdited`     | `UPDATE WHERE id = $1 AND revision < $2` (only applies if newer)           |
| `ObjectSpawned`             | `Repo.insert!(... on_conflict: :nothing, conflict_target: :id)`            |
| `ObjectEdited`              | `UPDATE` is idempotent at the field level; replay re-applies the same diff |
| `WizardEnteredTrance`       | No projection; broadcaster fires PubSub each time, but PubSub is broadcast-only and re-delivery is harmless during replay (LiveView clients subscribe live, not historically) |
| `WizardExitedTrance`        | Same as above.                                                             |

## Cross-feature interactions

- **Existing `ObjectPlacedInRoom` / `ObjectTakenFromRoom` / `ObjectDroppedInRoom` events** (features 003 / 006) are untouched. Existing seed-time / take-drop paths continue to emit them. The new `ObjectSpawned` is the milestone-1 *wizard-driven* spawn path; the existing object-placement events stay valid for non-wizard paths.
- **`PlayerArrived`, `RoomLogEntry`**, etc. from feature 003 are untouched.
- **Spec 008's `NPCBlueprintCreated`, `NPCClonedFromBlueprint`** are untouched in milestone 1. Milestone 2 will rename `NPCClonedFromBlueprint` to `NPCSpawned` and align it with the no-`blueprint_id` pattern from this milestone.
- **Spec 013's `QuestAccepted`, `QuestItemsConsumed`, etc.** are untouched. Wizards cannot author quest-scoped objects in milestone 1; the `quest_player_id` / `quest_instance_id` fields on `world_objects` continue to be NULL for everything wizards create.
