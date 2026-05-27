# Contract: projection handlers for quest events

Quest events split across two projectors:

- **`WorldProjector`** (existing module — `lib/agenticrealms/world/projections/world_projector.ex`) handles `QuestAccepted` and the extended `NPCBlueprintCreated` and `ObjectPlacedInRoom` events.
- **`QuestProjector`** (NEW — `lib/agenticrealms/world/projections/quest_projector.ex`) handles the four finalize events as a focused projector.

Both projectors run with `:eventual` consistency (consistent with `UIEventBroadcaster` and the other projectors in the codebase).

## `WorldProjector` extensions

### Handler: `QuestAccepted`

```elixir
def handle(%QuestAccepted{} = e, _meta) do
  Repo.transaction(fn ->
    # 1. Insert quest_instances row
    %QuestInstance{
      id: e.quest_id,
      player_id: e.player_id,
      npc_blueprint_id: e.npc_blueprint_id,
      slug: e.slug,
      state: "active",
      accepted_at: e.accepted_at,
      definition_snapshot: e.definition_snapshot
    }
    |> Repo.insert!(on_conflict: :nothing, conflict_target: :id)

    # 2. For each criterion, dispatch PlaceObject to each spawn_room_id
    for criterion <- e.definition_snapshot["criteria"],
        room_id <- criterion["spawn_room_ids"] do
      Commands.place_object(
        room_id,
        %{
          object_id: Ecto.UUID.generate(),
          name: criterion["name"] |> singularize(),
          short_description: short_desc_for(criterion),
          long_description: long_desc_for(criterion),
          fixed: false,
          behaviors: [%{type: "quest_tag", tag: criterion["quest_tag"]}],
          quest_player_id: e.player_id,
          quest_instance_id: e.quest_id
        }
      )
    end
  end)

  :ok
end
```

Notes:
- `Commands.place_object/2` is the existing wrapper for the `PlaceObject` command, extended to accept the two new fields.
- The quest_tag is stored as a behavior on the object (matches the existing behavior-bag pattern documented in feature 011). The projector that handles `ObjectPlacedInRoom` reads behaviors as part of the standard object insert; no new behavior interpreter is needed for v1 — the quest_tag is purely a lookup key for queries.
- One item per spawn_room_id (per § 3 of the data model: `length(spawn_room_ids) == target_count`).

### Handler: `NPCBlueprintCreated` (extended)

```elixir
def handle(%NPCBlueprintCreated{} = e, _meta) do
  %NPCBlueprint{
    id: e.blueprint_id,
    name: e.name,
    short_description: e.short_description,
    long_description: e.long_description,
    lore: Map.get(e, :lore, ""),
    behaviors: Map.get(e, :behaviors, []),
    quests: Map.get(e, :quests, [])   # NEW; legacy events default to []
  }
  |> Repo.insert(on_conflict: :replace_all, conflict_target: :id)
end
```

### Handler: `ObjectPlacedInRoom` (extended)

Persist the two new fields onto the inserted `world_objects` row:

```elixir
def handle(%ObjectPlacedInRoom{} = e, _meta) do
  %Object{
    id: e.object_id,
    name: e.name,
    short_description: e.short_description,
    long_description: e.long_description,
    fixed: e.fixed,
    behaviors: e.behaviors,
    room_id: e.room_id,
    player_id: nil,
    quest_player_id: Map.get(e, :quest_player_id),   # NEW
    quest_instance_id: Map.get(e, :quest_instance_id) # NEW
  }
  |> Repo.insert(on_conflict: :nothing, conflict_target: :id)
end
```

`Map.get/2` defaults legacy events to `nil`.

## `QuestProjector` (new module)

```elixir
defmodule AgenticRealms.World.Projections.QuestProjector do
  use Commanded.Event.Handler,
    application: AgenticRealms.World.Application,
    name: __MODULE__,
    consistency: :eventual

  alias AgenticRealms.Repo
  alias AgenticRealms.World.{Object, QuestInstance}
  alias AgenticRealms.World.Events.{
    QuestItemsConsumed,
    QuestRewardMinted,
    QuestCompleted,
    QuestItemsCleanedUp
  }

  import Ecto.Query, only: [from: 2]

  def handle(%QuestItemsConsumed{consumed_object_ids: ids}, _meta) do
    from(o in Object, where: o.id in ^ids)
    |> Repo.delete_all()

    :ok
  end

  def handle(%QuestRewardMinted{} = e, _meta) do
    %Object{
      id: e.reward_object_id,
      name: e.reward_name,
      short_description: e.reward_description,
      long_description: e.reward_description,
      fixed: false,
      behaviors: [],
      room_id: nil,
      player_id: e.player_id,
      quest_player_id: nil,
      quest_instance_id: nil
    }
    |> Repo.insert(on_conflict: :nothing, conflict_target: :id)

    :ok
  end

  def handle(%QuestCompleted{quest_id: id, completed_at: at, player_id: pid}, _meta) do
    from(q in QuestInstance,
      where: q.id == ^id,
      update: [set: [state: "completed", completed_at: ^at]]
    )
    |> Repo.update_all([])

    # Defensive: also update reward_object_id reference, if we want to back-reference (set in the QuestRewardMinted handler instead — see below).
    :ok
  end

  def handle(%QuestItemsCleanedUp{remaining_quest_object_ids: ids}, _meta) do
    if ids != [] do
      from(o in Object, where: o.id in ^ids)
      |> Repo.delete_all()
    end

    :ok
  end
end
```

The four handlers are independent — Commanded delivers events in order to a single handler, but if `QuestProjector` is restarted between events the next start replays from the saved offset, so each handler must be idempotent on replay:

- `QuestItemsConsumed`: `delete_all` of a closed id-set is idempotent.
- `QuestRewardMinted`: `insert(on_conflict: :nothing, conflict_target: :id)` is idempotent.
- `QuestCompleted`: `update_all` setting `state="completed"` is idempotent.
- `QuestItemsCleanedUp`: `delete_all` of a closed id-set is idempotent.

## `reward_object_id` back-reference

The `quest_instances.reward_object_id` column is populated in the `QuestRewardMinted` handler as a SET-NULL-safe back-reference for future quest-detail rendering. Add to the handler above:

```elixir
from(q in QuestInstance,
  where: q.id == ^e.quest_id,
  update: [set: [reward_object_id: ^e.reward_object_id]]
)
|> Repo.update_all([])
```

## Supervision

`QuestProjector` is added to `AgenticRealms.Application.commanded_children/0` (`lib/agenticrealms/application.ex:69–84`), inserted after `WorldProjector` and `PlayerStateProjector` in the list. It depends on `quest_instances` and the extended `world_objects` migrations having run, which they will have by the time the supervision tree starts in dev/test (`mix ecto.migrate` runs first).

## Tests

- `test/agenticrealms/world/projections/world_projector_quest_test.exs`:
  - `QuestAccepted` → row inserted; each spawn room receives a `PlaceObject` (verified by reading `world_objects` and asserting `quest_player_id` + `quest_instance_id` + `behaviors` carry the quest_tag).
  - Idempotent replay of `QuestAccepted`: replaying twice does not duplicate `quest_instances` or spawn double objects.
- `test/agenticrealms/world/projections/quest_projector_test.exs`:
  - Each of the four handlers applies correctly.
  - Idempotent replay for all four.
