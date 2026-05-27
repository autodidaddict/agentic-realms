# Data Model: Quest System (v1, FetchQuest)

This document captures every piece of persistent and in-flight state the quest feature introduces, plus the contracts between aggregates, events, projectors, and the read model. Entities are grouped by where they live (aggregate state, event payload, DB table, ephemeral struct). Field types are the Elixir/Ecto types that will appear in the actual schemas.

## 1. `Quest` aggregate

**Identity**: `quest_id` (binary_id). The router identifies via `prefix: "quest-"`.

**State**: a single struct, replayed from events.

```elixir
defmodule AgenticRealms.World.Quest do
  defstruct [
    :quest_id,                # binary_id — primary identity
    :player_id,               # integer (bigint) — who accepted
    :npc_blueprint_id,        # string — who offered
    :slug,                    # string — slug within the NPC's catalog
    :state,                   # :initial | :active | :completed
    :definition_snapshot,     # map — full FetchQuest definition as of accept time (see § 3)
    :accepted_at,             # DateTime | nil
    :completed_at             # DateTime | nil
  ]
end
```

**State machine**:

```text
:initial ──AcceptQuest──▶ :active ──FinalizeQuest──▶ :completed
                              │
                              └─(no other transitions in v1)
```

Each transition is driven by one command + one or more emitted events; see § 4 below.

## 2. `quest_instances` read-model table

Authoritative read-side projection of every `Quest` aggregate. One row per accepted quest.

| Column | Type | Constraints | Source event |
|---|---|---|---|
| `id` | binary_id | PK | `QuestAccepted.quest_id` |
| `player_id` | bigint | FK → `players.id`, NOT NULL | `QuestAccepted.player_id` |
| `npc_blueprint_id` | string | FK → `npc_blueprints.id`, NOT NULL | `QuestAccepted.npc_blueprint_id` |
| `slug` | string | NOT NULL | `QuestAccepted.slug` |
| `state` | string | NOT NULL, in (`"active"`, `"completed"`) | `QuestAccepted` → `"active"`; `QuestCompleted` → `"completed"` |
| `accepted_at` | utc_datetime | NOT NULL | `QuestAccepted.accepted_at` |
| `completed_at` | utc_datetime | NULL | `QuestCompleted.completed_at` |
| `definition_snapshot` | jsonb | NOT NULL | `QuestAccepted.definition_snapshot` |
| `reward_object_id` | binary_id | NULL (set on `QuestRewardMinted`) | `QuestRewardMinted.reward_object_id` |
| `inserted_at` / `updated_at` | timestamps | NOT NULL | projector-managed |

**Indexes**:
- Partial unique index on `(player_id, npc_blueprint_id, slug) WHERE state = 'completed'` — enforces FR-012 at the DB layer.
- Index on `(player_id, state)` — supports fast "active quests for this player" lookups.
- Index on `(npc_blueprint_id, slug)` — supports authoring sanity queries.

**Ecto schema**: new `AgenticRealms.World.QuestInstance` in `lib/agenticrealms/world/schemas/quest_instance.ex`. Mirrors the table 1:1. `has_many :scoped_objects, AgenticRealms.World.Object, foreign_key: :quest_instance_id`.

## 3. `definition_snapshot` shape

The FetchQuest definition is snapshotted into `quest_instances.definition_snapshot` at accept time. It is the source of truth for that instance's criteria, narrative, spawn rooms, and reward for the rest of the quest's life — later edits to the NPC's catalog never affect in-flight quests.

```json
{
  "slug": "golden_apples",
  "title": "The Orchard Keeper's Errand",
  "narrative": "Three golden apples have rolled away from my orchard. Bring them back.",
  "criteria": [
    {
      "name": "Golden Apples",
      "quest_tag": "quest.013-quest-system.orchard.golden_apple",
      "target_count": 3,
      "spawn_room_ids": [
        "<room_id_1>",
        "<room_id_2>",
        "<room_id_3>"
      ]
    }
  ],
  "reward": {
    "name": "bigger golden apple",
    "description": "An impossibly large golden apple, warm to the touch."
  }
}
```

**Field rules**:
- `slug` — unique within the NPC's catalog; must match the slug passed to `accept_quest`.
- `title` — display string shown in the quest log.
- `narrative` — short summary shown in the quest log + the modal detail view.
- `criteria` — ≥ 1 entries. Each criterion's `spawn_room_ids` is a list of distinct existing room ids; `length(spawn_room_ids) == target_count` (one item per spawn room — this keeps spawn placement unambiguous and lets the wizard place each apple in a specific room).
- `quest_tag` — lowercase dot-segmented. Author-supplied at the template level (e.g. `quest.orchard.golden_apple`); at acceptance time the wrapper rewrites it into an **instance-scoped tag** of the form `quest.<feature_slug>.<author_path>.<quest_id_short>` to prevent cross-instance collision (FR-004). The snapshot stores the instance-scoped form.
- `reward.name` / `reward.description` — used to mint the reward object at finalize. No item template required (matches FR-006).

## 4. Quest events

All five events are stored in the existing Commanded event store. Each event has corresponding Elixir struct + projector handler.

### 4.1 `QuestAccepted`

```elixir
defmodule AgenticRealms.World.Events.QuestAccepted do
  @derive Jason.Encoder
  defstruct [
    :quest_id,
    :player_id,
    :npc_blueprint_id,
    :slug,
    :definition_snapshot,
    :accepted_at
  ]
end
```

- Emitted by `Quest.execute/2` from `:initial` state on `AcceptQuest` command.
- `definition_snapshot` carries the snapshot described in § 3 (instance-scoped tags already substituted).
- `WorldProjector` handler: inserts a `quest_instances` row with `state="active"`; for each criterion, dispatches one `PlaceObject` command per item in `spawn_room_ids` (target_count items total per criterion) targeting the respective Room aggregates, with `quest_player_id` and `quest_instance_id` carried through.

### 4.2 `QuestItemsConsumed`

```elixir
defmodule AgenticRealms.World.Events.QuestItemsConsumed do
  @derive Jason.Encoder
  defstruct [
    :quest_id,
    :player_id,
    :consumed_object_ids        # list of binary_id
  ]
end
```

- Emitted by `Quest.execute/2` from `:active` on `FinalizeQuest`, as the first of the four-event finalize bundle.
- `consumed_object_ids` was captured by `Commands.finalize_quest/2` at pre-dispatch time and passed in as part of the `FinalizeQuest` command (see § 5.3).
- `QuestProjector` handler: `Repo.delete_all/2` on `Object` where `id IN ^consumed_object_ids`.

### 4.3 `QuestRewardMinted`

```elixir
defmodule AgenticRealms.World.Events.QuestRewardMinted do
  @derive Jason.Encoder
  defstruct [
    :quest_id,
    :player_id,
    :reward_object_id,
    :reward_name,
    :reward_description
  ]
end
```

- Emitted by `Quest.execute/2` on `FinalizeQuest`, second of the four.
- `QuestProjector` handler: `INSERT INTO objects (id, name, short_description, long_description, fixed, behaviors, player_id, room_id, quest_player_id, quest_instance_id)` with `player_id = ^player_id`, `room_id = nil`, `quest_player_id = nil`, `quest_instance_id = nil`. The reward is a *normal* item, not a quest-scoped one.
- `reward_object_id` is pre-generated by the wrapper (via `Ecto.UUID.generate/0`) so the projector has no nondeterminism.

### 4.4 `QuestCompleted`

```elixir
defmodule AgenticRealms.World.Events.QuestCompleted do
  @derive Jason.Encoder
  defstruct [
    :quest_id,
    :player_id,
    :completed_at
  ]
end
```

- Emitted by `Quest.execute/2` on `FinalizeQuest`, third of the four.
- `QuestProjector` handler: `UPDATE quest_instances SET state='completed', completed_at = ^completed_at WHERE id = ^quest_id`.

### 4.5 `QuestItemsCleanedUp`

```elixir
defmodule AgenticRealms.World.Events.QuestItemsCleanedUp do
  @derive Jason.Encoder
  defstruct [
    :quest_id,
    :remaining_quest_object_ids   # list of binary_id; may be []
  ]
end
```

- Emitted by `Quest.execute/2` on `FinalizeQuest`, fourth of the four.
- Carries the ids of any objects with `quest_instance_id = ^quest_id` that were NOT part of `consumed_object_ids` (e.g., the player picked extras, dropped some in rooms, etc., or — in the more typical case — the criterion target was 3 and there were exactly 3 items, so this list is empty).
- `QuestProjector` handler: `Repo.delete_all/2` on `Object` where `id IN ^remaining_quest_object_ids`.

## 5. Commands

### 5.1 `AcceptQuest`

```elixir
defmodule AgenticRealms.World.Commands.AcceptQuest do
  defstruct [
    :quest_id,
    :player_id,
    :npc_blueprint_id,
    :slug,
    :definition_snapshot,
    :accepted_at
  ]
end
```

- Dispatched only by `World.Commands.accept_quest/3` (the wrapper). All pre-dispatch validation (FR-009) is in the wrapper:
  - Look up the NPC blueprint, locate the catalog entry by slug → `{:error, :unknown_slug}` if missing.
  - Read `quest_instances` for `(player_id, npc_blueprint_id, slug)` → `{:error, :already_completed}` if any row has `state="completed"`; `{:error, :already_active}` if any row has `state="active"`.
  - Generate a fresh `quest_id` (`Ecto.UUID.generate/0`).
  - Build the instance-scoped `definition_snapshot` (rewrite template-level quest tags into instance-scoped tags using the new `quest_id`).
  - Dispatch.
- `Quest.execute/2` on `:initial` state emits `QuestAccepted`.

### 5.2 `CheckProgress` (no dispatched command — pure read)

There is no `CheckProgress` command in the Commanded sense. `Commands.check_progress/2` is a pure read against the read model:

```elixir
def check_progress(player_id, quest_id) do
  case Quests.quest_instance(quest_id) do
    %{state: "active", player_id: ^player_id} = instance ->
      {:ok, progress_for(instance)}
    %{} -> {:error, :unknown_instance}
    nil -> {:error, :unknown_instance}
  end
end
```

`progress_for/1` (in `AgenticRealms.World.Quests`) reads the player's inventory and matches against the instance's snapshot criteria, returning `[%{name, count, target}]`.

### 5.3 `FinalizeQuest`

```elixir
defmodule AgenticRealms.World.Commands.FinalizeQuest do
  defstruct [
    :quest_id,
    :consumed_object_ids,
    :reward_object_id,
    :reward_name,
    :reward_description,
    :remaining_quest_object_ids,
    :completed_at
  ]
end
```

- Dispatched only by `World.Commands.finalize_quest/2`. Wrapper logic:
  1. Look up the quest instance → `{:error, :unknown_instance}` on miss or wrong player or non-active state.
  2. Read the player's inventory restricted to objects whose `quest_instance_id = ^quest_id` (i.e., the spawned quest items they're carrying).
  3. Match against `definition_snapshot.criteria`: for each criterion, pick `target_count` matching objects. If any criterion is short, return `{:error, :criteria_unmet, missing: [%{name, count, target}, ...]}` without dispatching.
  4. Capture the selected object ids as `consumed_object_ids`. Compute `remaining_quest_object_ids` as `all_objects_with_this_quest_instance_id -- consumed_object_ids`.
  5. Generate `reward_object_id = Ecto.UUID.generate/0`.
  6. Dispatch.
- `Quest.execute/2` on `:active` state emits the four events in order: `QuestItemsConsumed`, `QuestRewardMinted`, `QuestCompleted`, `QuestItemsCleanedUp`.

## 6. `world_objects` schema extension

Add two nullable columns to the existing `world_objects` table (mirror of `Object` schema, `lib/agenticrealms/world/schemas/object.ex`).

| Column | Type | Constraints |
|---|---|---|
| `quest_player_id` | bigint | NULL, FK → `players.id` |
| `quest_instance_id` | binary_id | NULL, FK → `quest_instances.id` |

**Check constraint**: `(quest_player_id IS NULL) = (quest_instance_id IS NULL)` — they're set together or not at all.

**Index**: on `quest_instance_id` to support bulk cleanup at finalize.

**Ecto schema additions**:

```elixir
field :quest_player_id, :integer       # belongs_to is also defined for the FK association
field :quest_instance_id, :binary_id
belongs_to :quest_player, AgenticRealms.Accounts.Player, foreign_key: :quest_player_id, define_field: false
belongs_to :quest_instance, AgenticRealms.World.QuestInstance, foreign_key: :quest_instance_id, define_field: false
```

**Semantics**:
- For all pre-existing objects, both fields are NULL → behavior unchanged.
- For objects spawned by `accept_quest`, both fields are set: `quest_player_id` to the accepting player, `quest_instance_id` to the `Quest`'s id.
- The reward object minted by `finalize_quest` has both NULL — it's a normal item.

## 7. `PlaceObject` command + `ObjectPlacedInRoom` event extension

Both gain two nullable fields that the projector persists onto the new `world_objects` columns:

```elixir
# PlaceObject command struct extension
field :quest_player_id, :integer | nil
field :quest_instance_id, :binary_id | nil

# ObjectPlacedInRoom event struct extension
field :quest_player_id, :integer | nil
field :quest_instance_id, :binary_id | nil
```

- For all existing call sites (seed, wizard authoring), both fields default to nil. Behavior unchanged.
- The `WorldProjector` handler for `QuestAccepted` dispatches `PlaceObject` with both fields set.
- The `WorldProjector` handler for `ObjectPlacedInRoom` reads both fields off the event and persists them onto the inserted row.
- Legacy `ObjectPlacedInRoom` events without these fields default both to nil at apply time.

## 8. `npc_blueprints` schema extension

Add one column to the existing `npc_blueprints` table.

| Column | Type | Constraints |
|---|---|---|
| `quests` | jsonb | NOT NULL DEFAULT `'[]'::jsonb` |

**Shape**: list of FetchQuest definitions (the *template-level* shape — quest tags here are author-supplied template tags, NOT instance-scoped; the instance-scoped tags are derived at acceptance time).

```json
[
  {
    "slug": "golden_apples",
    "title": "The Orchard Keeper's Errand",
    "narrative": "...",
    "criteria": [
      {
        "name": "Golden Apples",
        "quest_tag": "quest.orchard.golden_apple",
        "target_count": 3,
        "spawn_room_ids": ["<room_id_1>", "<room_id_2>", "<room_id_3>"]
      }
    ],
    "reward": {
      "name": "bigger golden apple",
      "description": "..."
    }
  }
]
```

**Ecto schema additions** (on `AgenticRealms.World.NPCBlueprint`):

```elixir
field :quests, {:array, :map}, default: []
```

**Validation** (in `Commands.create_npc_blueprint/*`):
- Each entry has non-empty `slug`, unique among the blueprint's quests.
- Each entry has ≥ 1 criterion.
- Each criterion has non-empty `quest_tag`, `target_count >= 1`, and `length(spawn_room_ids) == target_count`.
- Each `spawn_room_id` references an existing room (validated against the read model at command time, not at replay).

## 9. `NPCBlueprintCreated` event extension

The existing `NPCBlueprintCreated` event gains a `quests` field of the same shape as the schema column. Legacy events without this field default to `[]` at apply time.

```elixir
defstruct [
  :blueprint_id,
  :name,
  :short_description,
  :long_description,
  :lore,
  :behaviors,
  :quests           # NEW; default []
]
```

`AgenticRealms.World.NPCBlueprint.apply/2` reads the field with `Map.get(event, :quests, [])` to support legacy events.

`WorldProjector` projects the field into the new `npc_blueprints.quests` column.

## 10. PubSub UI events (broadcast on `player:<player_id>`)

The existing `AgenticRealmsWeb.Topics.player_topic/1` is reused. Three new structs broadcast over it:

```elixir
defmodule AgenticRealmsWeb.Events.PlayerQuestAccepted do
  @enforce_keys [:quest_id, :title, :narrative, :criteria]
  defstruct [:quest_id, :title, :narrative, :criteria]
  # criteria: [%{name: string, count: 0, target: integer}]
end

defmodule AgenticRealmsWeb.Events.PlayerQuestProgress do
  @enforce_keys [:quest_id, :criteria]
  defstruct [:quest_id, :criteria]
  # criteria: [%{name: string, count: integer, target: integer}]
end

defmodule AgenticRealmsWeb.Events.PlayerQuestFinalized do
  @enforce_keys [:quest_id, :title, :reward_name, :completed_at]
  defstruct [:quest_id, :title, :reward_name, :completed_at]
end
```

**Emission rules** (in `AgenticRealms.UIEventBroadcaster`):

| Triggering Commanded event | UI broadcast |
|---|---|
| `QuestAccepted` | `PlayerQuestAccepted` (with criteria all at `count=0`) |
| `ObjectTakenFromRoom` for an object whose tag matches one of the player's active quest criteria | `PlayerQuestProgress` (recomputed counts for that quest) |
| `ObjectDroppedInRoom` for the same | `PlayerQuestProgress` (recomputed) |
| `QuestCompleted` | `PlayerQuestFinalized` |

Note: `ObjectTakenFromRoom` / `ObjectDroppedInRoom` already trigger an existing `PlayerInventoryChanged` broadcast. The quest broadcast is *additional*, in the same handler, after the inventory broadcast.

## 11. Quest reader API (`AgenticRealms.World.Quests`)

A new top-level read module (peer to `Queries`, `MapView`, `Examine`):

```elixir
defmodule AgenticRealms.World.Quests do
  @spec active_for(player_id :: integer()) :: [active_quest_summary()]
  @spec history_for(player_id :: integer()) :: [completed_quest_summary()]
  @spec quest_instance(quest_id :: binary()) :: QuestInstance.t() | nil
  @spec progress_for(QuestInstance.t()) :: [criterion_progress()]
end

# Shapes:
@type active_quest_summary :: %{quest_id: binary, title: string, narrative: string, criteria: [criterion_progress]}
@type completed_quest_summary :: %{quest_id: binary, title: string, completed_at: DateTime.t(), reward_name: string}
@type criterion_progress :: %{name: string, count: non_neg_integer, target: pos_integer}
```

`progress_for/1` is the canonical "count items in inventory that match each criterion's instance-scoped quest_tag" function. Called by `check_progress/2`, by `active_for/1`, and by `UIEventBroadcaster` when assembling `PlayerQuestProgress` events.

## 12. State transition summary (full happy path)

```text
                                      ┌────────────────────────┐
   LLM intent: "I'll do it"           │ Commands.accept_quest/3│
   ────────────────────────────────▶  │ - validate slug        │
                                      │ - check sticky+active  │
                                      │ - generate quest_id    │
                                      │ - snapshot definition  │
                                      │ - dispatch AcceptQuest │
                                      └───────────┬────────────┘
                                                  ▼
                                       Quest aggregate (:initial)
                                                  │ emit
                                                  ▼
                                          QuestAccepted
                                                  │
                                                  ▼
                                       WorldProjector
                                       - insert quest_instances row (state=active)
                                       - dispatch PlaceObject per spawn room (with quest_player_id, quest_instance_id)
                                       UIEventBroadcaster → PlayerQuestAccepted on player:<id>

   player picks up apple in room
                                       ObjectTakenFromRoom (existing)
                                                  │
                                                  ▼
                                       UIEventBroadcaster
                                       - existing PlayerInventoryChanged
                                       - NEW: recompute progress for active quests
                                              touching this tag, broadcast PlayerQuestProgress

   LLM intent: "here you go"
                                      ┌────────────────────────────┐
                                      │ Commands.finalize_quest/2  │
                                      │ - validate instance        │
                                      │ - read inventory           │
                                      │ - match criteria           │
                                      │ - if ok: capture ids,      │
                                      │   gen reward_object_id     │
                                      │ - dispatch FinalizeQuest   │
                                      └────────────┬───────────────┘
                                                   ▼
                                       Quest aggregate (:active)
                                                  │ emit 4 events
                                                  ▼
                                  QuestItemsConsumed
                                  QuestRewardMinted
                                  QuestCompleted
                                  QuestItemsCleanedUp
                                                  │
                                                  ▼
                                       QuestProjector (single Repo transaction)
                                       - delete objects in consumed_object_ids
                                       - insert reward object (player_id set)
                                       - update quest_instances.state=completed
                                       - delete objects in remaining_quest_object_ids
                                       UIEventBroadcaster → PlayerQuestFinalized on player:<id>
```

## 13. Validation & invariants summary

| Invariant | Enforced by |
|---|---|
| One `quest_instances` row per `(player_id, npc_blueprint_id, slug)` with `state=completed` | Partial unique index (DB) + `Commands.accept_quest/3` pre-check |
| `quest_instance_id` and `quest_player_id` are set together on `world_objects` | DB check constraint |
| Active quest progress reflects current inventory | `Quests.progress_for/1` is pure-function over `world_objects`; no stored counts |
| Finalize is all-or-nothing | `Commands.finalize_quest/2` dispatches only after full validation; aggregate emits all 4 events together; projector applies in one transaction |
| Quest items visible/takeable only by owner | `Queries.list_objects_in_room_for_viewer/2` + `Queries.resolve_object_in_room/2` apply the WHERE filter at every read path |
| Quest catalog edits never affect in-flight quests | `definition_snapshot` is taken at accept time and stored on the row |
| Process restart preserves quest state | All state lives in `quest_instances` + `world_objects` (Postgres-backed); replay reconstructs `Quest` aggregates |
