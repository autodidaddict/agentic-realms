# Contract: Domain Event Extensions

This feature does NOT introduce new domain event types. It extends three existing events with an optional `:behaviors` field defaulting to `[]`.

## Extended event: `RoomCreated` (feature 003)

```elixir
defmodule AgenticRealms.World.Events.RoomCreated do
  @derive Jason.Encoder
  @enforce_keys [:room_id, :name, :description]
  defstruct [
    :room_id,
    :name,
    :description,
    behaviors: [],          # NEW — optional, default []
    version: 1
  ]
end
```

### Producer

`World.Room` aggregate on a successful `CreateRoom` command. The aggregate's `execute/2` reads the optional `:behaviors` field from the command and passes it through to the emitted event.

### Consumers

1. **`Room` aggregate `apply/2`** — sets `state.behaviors` from the event.
2. **`WorldProjector`** — `handle(%RoomCreated{behaviors: behaviors}, ...)` inserts the row with `behaviors: behaviors` (defaults to `[]` for legacy events).

### Backward compatibility

Feature 003/008 RoomCreated events in the event store deserialize with `behaviors: []`. The projector inserts the room with no behaviors. Developers running `mix event_store.reset && mix ecto.reset` get a fresh world where the Stone Atrium's RoomCreated event carries the atmospheric narration behavior.

## Extended event: `NPCBlueprintCreated` (feature 008)

```elixir
defmodule AgenticRealms.World.Events.NPCBlueprintCreated do
  @derive Jason.Encoder
  @enforce_keys [:blueprint_id, :name, :short_description, :long_description]
  defstruct [
    :blueprint_id,
    :name,
    :short_description,
    :long_description,
    behaviors: [],          # NEW — optional, default []
    version: 1
  ]
end
```

### Producer

`World.NPCBlueprint` aggregate on a successful `CreateNPCBlueprint` command. Reads optional `:behaviors` from the command.

### Consumers

1. **`NPCBlueprint` aggregate `apply/2`** — sets `state.behaviors` from the event. Subsequent `SpawnNPCClone` commands stamp this list into `NPCClonedFromBlueprint` events (full-copy at clone time).
2. **`WorldProjector`** — `handle(%NPCBlueprintCreated{}, ...)` inserts the blueprint row with `behaviors: behaviors`.

### Backward compatibility

Feature 008 NPCBlueprintCreated events deserialize with `behaviors: []`. Pre-feature-009 blueprints rebuild with empty behavior lists.

## Extended event: `NPCClonedFromBlueprint` (feature 008)

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
    behaviors: [],          # NEW — optional, default []
    version: 1
  ]
end
```

### Producer

`NPCBlueprint` aggregate on `SpawnNPCClone`. The aggregate's `execute/2` clause stamps `state.behaviors` (the blueprint's current behavior list) into the emitted event payload — this is the **full-copy materialization point** for behaviors (parallel to feature 008's full-copy for name/short/long).

### Consumer

**`WorldProjector`** — `handle(%NPCClonedFromBlueprint{}, ...)` inserts the clone row with `behaviors: behaviors`. The clone owns its own behavior list from this moment forward; subsequent blueprint edits do NOT propagate.

### Backward compatibility

Feature 008 NPCClonedFromBlueprint events deserialize with `behaviors: []`. The projector inserts the clone with no behaviors. Garrick's clone — currently in the event store from feature 008 — rebuilds with empty behaviors on existing systems. A `mix event_store.reset && mix ecto.reset` re-runs the seed, which now stamps behaviors into the new event payloads.

## Legacy event: `NPCSpawnedInRoom` (feature 007)

Unchanged. This event was never emitted from feature 008 onward; it only exists in event stores of developers who used feature 007 directly. The projector's synthetic-blueprint replay path inserts behaviors as `[]` for any clones materialized from this legacy event.

## Non-events

This feature does NOT introduce:
- `BehaviorAdded` / `BehaviorRemoved` / `RoomBehaviorsSet` / `BlueprintBehaviorsUpdated` — no mutation events. Behaviors are set ONLY at entity creation; no edit path in this feature.
- `BehaviorFired` / `NPCSpoke` / `RoomNarrated` — no firing events. Behavior firings are non-event-sourced (FR-016). They produce only transient `BehaviorUtterance` UI events on `player_topic`.

These non-events are deliberate scope decisions. The wizard tab feature will introduce mutation events when wizards gain the ability to edit existing entities' behaviors.

## Replay implications

- **Behavior data flows correctly through replay**: the three extended events carry `:behaviors` in their payloads. Replaying the event store reconstructs the read-model `behaviors` columns deterministically.
- **Behavior firings do NOT replay**: per FR-016a, the `World.Behaviors.Interpreter` uses `start_from: :current` and never sees historical events.

## Event-schema versioning

All three extended events keep `version: 1`. The field-addition pattern (default `[]` on a new optional field) is backward-compatible without a version bump. If a future feature changes the SHAPE of behavior data (e.g., adds a `conditions` field per behavior), THAT would bump version. Per-field additions don't.
