# Phase 1 Data Model: NPC and Room Behaviors

## 1. Behavior storage shape

A **behavior list** is the value stored in the new `:behaviors` JSONB column on three tables. Its shape, when round-tripped through Postgres/Jason, is:

```text
[
  %{
    "trigger" => "player_entered" | "player_left",
    "actions" => [
      %{"type" => "say", "text" => "..."}
      # ... more actions ...
    ]
  }
  # ... more behaviors ...
]
```

**Notes**:
- The outer list is the behavior list. Each entry is a behavior (a `(trigger, [actions])` pair).
- Map keys are always strings (not atoms) because Jason produces string-keyed maps on decode. The interpreter pattern-matches on string-keyed maps to avoid the `String.to_existing_atom/1` footgun.
- Triggers and action types are STRINGS in storage. The interpreter converts them to atoms at dispatch time via a lookup table (never `String.to_atom/1`).
- Action params are flat string-keyed maps. `:say` requires `"text"`; future actions will introduce their own required fields.
- Empty behavior list (`[]`) means no behaviors. This is the default for every entity that doesn't have behaviors authored.

## 2. Schema changes

Three existing tables each gain one new column:

### `npc_blueprints`

| New column   | Type   | Constraints                            | Notes                                                            |
|--------------|--------|----------------------------------------|------------------------------------------------------------------|
| `behaviors`  | JSONB  | NOT NULL, DEFAULT `'[]'::jsonb`         | Behavior list on the blueprint. Inherited at clone spawn time.   |

### `npc_clones`

| New column   | Type   | Constraints                            | Notes                                                                                            |
|--------------|--------|----------------------------------------|--------------------------------------------------------------------------------------------------|
| `behaviors`  | JSONB  | NOT NULL, DEFAULT `'[]'::jsonb`         | Denormalized from blueprint at spawn time (full-copy, per feature 008). Owned by the clone row.  |

### `world_rooms`

| New column   | Type   | Constraints                            | Notes                                                                                              |
|--------------|--------|----------------------------------------|----------------------------------------------------------------------------------------------------|
| `behaviors`  | JSONB  | NOT NULL, DEFAULT `'[]'::jsonb`         | Behavior list on the room. Sourced from the `RoomCreated` event (event-sourced; replayable). Set at room-creation time only in this feature. |

## 3. Ecto schema field additions

```elixir
# lib/agenticrealms/world/schemas/npc_blueprint.ex
field :behaviors, {:array, :map}, default: []

# lib/agenticrealms/world/schemas/npc_clone.ex
field :behaviors, {:array, :map}, default: []

# lib/agenticrealms/world/schemas/room.ex
field :behaviors, {:array, :map}, default: []
```

Ecto's `{:array, :map}` field type maps cleanly to PostgreSQL `JSONB` storing a JSON array of objects. The default `[]` matches the database default.

## 4. Aggregate state extension: `NPCBlueprint`

The `World.NPCBlueprint` aggregate defstruct grows one field:

```elixir
defstruct id: nil,
          name: nil,
          short_description: nil,
          long_description: nil,
          behaviors: [],          # NEW — list of behavior maps
          next_serial: 1,
          clone_ids: MapSet.new()
```

**State transitions affecting behaviors**:

```text
CreateNPCBlueprint{blueprint_id, name, short, long, behaviors}
  ↓ (aggregate handler validates basics; behaviors pass through as-is)
NPCBlueprintCreated{blueprint_id, name, short, long, behaviors}
  ↓ (apply/2)
%NPCBlueprint{state | id: ..., behaviors: behaviors}

SpawnNPCClone{blueprint_id, clone_id, room_id}
  ↓ (aggregate handler stamps current state into event)
NPCClonedFromBlueprint{blueprint_id, clone_id, room_id, serial, name, short, long, behaviors}
  ↓ (apply/2)
%NPCBlueprint{state | next_serial: serial + 1, clone_ids: MapSet.put(...)}
```

The behaviors live on the blueprint state from creation and ride along into every clone spawn event. Future blueprint edits (deferred — no `UpdateBlueprint` command in this feature, per feature 008 FR-005a) would update `state.behaviors`, but NOT existing clones (full-copy semantics).

## 5. Domain event extensions

### `RoomCreated` (feature 003, extended)

```elixir
defmodule AgenticRealms.World.Events.RoomCreated do
  @derive Jason.Encoder
  @enforce_keys [:room_id, :name, :description]
  defstruct [
    :room_id,
    :name,
    :description,
    behaviors: [],          # NEW — optional field, default []
    version: 1
  ]
end
```

Backward compatibility: feature 003/008 RoomCreated events in the event store deserialize with `behaviors: []`. The projector inserts the room with an empty behavior list. Developers running `mix event_store.reset && mix ecto.reset` get a fresh world where the Stone Atrium's RoomCreated event carries the atmospheric narration behavior.

### `NPCBlueprintCreated` (feature 008, extended)

```elixir
defmodule AgenticRealms.World.Events.NPCBlueprintCreated do
  @derive Jason.Encoder
  @enforce_keys [:blueprint_id, :name, :short_description, :long_description]
  defstruct [
    :blueprint_id,
    :name,
    :short_description,
    :long_description,
    behaviors: [],          # NEW — optional field, default []
    version: 1
  ]
end
```

Backward compatibility: feature 008 events in the event store deserialize with `behaviors: []`. The projector treats that as "no behaviors" and inserts the blueprint with an empty behavior list.

### `NPCClonedFromBlueprint` (feature 008, extended)

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
    behaviors: [],          # NEW — optional field, default []
    version: 1
  ]
end
```

Same backward-compat story. Feature 008 events deserialize with `behaviors: []`.

### Non-events

This feature does NOT introduce new domain events. Behavior firings produce only transient `BehaviorUtterance` UIEvents (§7) — NOT Commanded events.

## 6. Command struct extensions

### `CreateRoom` (existing — feature 003, extended)

```elixir
defmodule AgenticRealms.World.Commands.CreateRoom do
  @enforce_keys [:room_id, :name, :description]
  defstruct [
    :room_id,
    :name,
    :description,
    behaviors: []           # NEW — optional, defaults to []
  ]
end
```

`@enforce_keys` is unchanged — feature 003/008 call sites that don't pass `:behaviors` still work, with the default `[]` applied. Feature 009 seed call sites pass `:behaviors` explicitly for the Stone Atrium's atmospheric line.

### `CreateNPCBlueprint` (existing — feature 008, extended)

```elixir
defmodule AgenticRealms.World.Commands.CreateNPCBlueprint do
  @enforce_keys [:blueprint_id, :name, :short_description, :long_description]
  defstruct [
    :blueprint_id,
    :name,
    :short_description,
    :long_description,
    behaviors: []           # NEW — optional, defaults to []
  ]
end
```

Same pattern. Feature 008 callers continue to work; feature 009 seed passes `:behaviors` for Garrick's `player_entered` and `player_left` behaviors.

## 7. UI event: `BehaviorUtterance`

New transient PubSub message. Never persisted. Lives only on `player:<player_id>` topics.

```elixir
defmodule AgenticRealms.World.UIEvents.BehaviorUtterance do
  @moduledoc """
  Transient utterance produced by a behavior's :say action. Broadcast on
  `player:<player_id>` topic, never on the room topic — see
  `specs/009-npc-behaviors/research.md` R2.
  """

  @enforce_keys [:kind, :text, :room_id, :triggering_player_id]
  defstruct [:kind, :actor_name, :text, :room_id, :triggering_player_id]
end
```

| Field                  | Type      | Notes                                                                |
|------------------------|-----------|----------------------------------------------------------------------|
| `kind`                 | atom      | `:npc_speech` or `:room_speech`.                                     |
| `actor_name`           | string \| nil | NPC clone's display name for `:npc_speech`; `nil` for `:room_speech`. |
| `text`                 | string    | The line spoken (or narrated).                                        |
| `room_id`              | `binary_id` | The room where the behavior fired. Diagnostic — not used in render.  |
| `triggering_player_id` | `integer` | The player whose movement triggered the behavior. Diagnostic / debug. |

**Producer**: `World.Behaviors.ActionExecutor` (called by `World.Behaviors.Interpreter`).
**Consumer**: `GameLive.handle_info/2`, which appends a `:npc_speech` or `:room_speech` log entry to the socket's `:log` assigns.

## 8. Log entry payload shapes

When `GameLive` receives a `BehaviorUtterance` message, it appends ONE log entry to `socket.assigns.log` whose shape depends on the kind:

### `:npc_speech` log entry

```elixir
%{
  kind: :npc_speech,
  actor_name: "Garrick the Innkeeper",
  text: "Welcome to the Stone Atrium."
}
```

Rendered as:
```html
<div class="log-entry speech speech-npc">
  <span class="who">Garrick the Innkeeper</span> says, &ldquo;Welcome to the Stone Atrium.&rdquo;
</div>
```

### `:room_speech` log entry

```elixir
%{
  kind: :room_speech,
  text: "The cool air carries the scent of rain."
}
```

Note: no `actor_name` field. The render template enforces the "no attribution" rule by not emitting any `<span class="who">` for this kind.

Rendered as:
```html
<div class="log-entry narrate narrate-room">
  The cool air carries the scent of rain.
</div>
```

## 9. Invariants summary

| ID  | Invariant                                                                                                                          | Enforced by                                                                                                |
|-----|------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------|
| I-1 | Every `behaviors` column defaults to `[]` — never null.                                                                            | DB-level `NOT NULL DEFAULT '[]'::jsonb` + Ecto schema default.                                              |
| I-2 | Behavior shape is validated at authoring time.                                                                                      | `World.Behaviors.Validator.validate/1` called by seed (and future authoring paths).                          |
| I-3 | The interpreter never re-fires historical events.                                                                                    | Commanded handler config `start_from: :current`.                                                            |
| I-4 | Blueprint behaviors are full-copied onto clones at spawn time.                                                                       | `NPCBlueprint.execute/2` for `SpawnNPCClone` stamps `state.behaviors` into the emitted event.               |
| I-5 | Blueprint behavior edits do NOT propagate to existing clones (matches feature 008 FR-012).                                          | No `UpdateBlueprint` command in this feature (FR-005a from 008 + FR-025 from 009).                          |
| I-6 | Behavior firings produce ZERO domain events.                                                                                         | `ActionExecutor` performs PubSub broadcasts only; no `WorldApp.dispatch` calls.                              |
| I-7 | `:room_speech` is delivered ONLY to the triggering player.                                                                            | `ActionExecutor` broadcasts on `player_topic(triggering_player_id)` only — never on room_topic.             |
| I-8 | `:npc_speech` is delivered to the triggering player + every other player in the speaker's room.                                       | `ActionExecutor` broadcasts on `player_topic(p)` for each recipient `p` in the computed recipient set.       |
| I-9 | Player-facing surfaces never render the LPMud `<name>#<serial>` debug identity for behavior speech.                                   | `:npc_speech` render clause uses `actor_name` (the bare display name), never `Schemas.NPCClone.debug_id/1`. |
| I-10 | Room behaviors fire BEFORE NPC behaviors for the same trigger event (FR-008a).                                                       | `Interpreter.process_event/1` walks room first, then clones.                                                |
