# Contract: UI broadcast events

All quest UI broadcasts go over the existing `AgenticRealmsWeb.Topics.player_topic/1` (`"player:<player_id>"`). Three new event structs are defined in `lib/agenticrealms_web/events/` and emitted from `AgenticRealms.UIEventBroadcaster` (`lib/agenticrealms/ui_event_broadcaster.ex`).

## Event structs

### `PlayerQuestAccepted`

```elixir
defmodule AgenticRealmsWeb.Events.PlayerQuestAccepted do
  @enforce_keys [:quest_id, :title, :narrative, :criteria]
  defstruct [:quest_id, :title, :narrative, :criteria]
  # criteria: [%{name: string, count: 0, target: pos_integer}]
end
```

### `PlayerQuestProgress`

```elixir
defmodule AgenticRealmsWeb.Events.PlayerQuestProgress do
  @enforce_keys [:quest_id, :criteria]
  defstruct [:quest_id, :criteria]
  # criteria: [%{name: string, count: non_neg_integer, target: pos_integer}]
end
```

### `PlayerQuestFinalized`

```elixir
defmodule AgenticRealmsWeb.Events.PlayerQuestFinalized do
  @enforce_keys [:quest_id, :title, :reward_name, :completed_at]
  defstruct [:quest_id, :title, :reward_name, :completed_at]
end
```

## Emission rules

### `QuestAccepted` (Commanded event)

```elixir
def handle(%QuestAccepted{} = e, _meta) do
  criteria =
    e.definition_snapshot["criteria"]
    |> Enum.map(fn c -> %{name: c["name"], count: 0, target: c["target_count"]} end)

  PubSub.broadcast(
    AgenticRealms.PubSub,
    Topics.player_topic(e.player_id),
    %PlayerQuestAccepted{
      quest_id: e.quest_id,
      title: e.definition_snapshot["title"],
      narrative: e.definition_snapshot["narrative"],
      criteria: criteria
    }
  )

  :ok
end
```

### `QuestCompleted` (Commanded event)

```elixir
def handle(%QuestCompleted{} = e, _meta) do
  # Look up the instance to retrieve title + reward name for the UI event
  instance = Quests.quest_instance(e.quest_id)

  PubSub.broadcast(
    AgenticRealms.PubSub,
    Topics.player_topic(e.player_id),
    %PlayerQuestFinalized{
      quest_id: e.quest_id,
      title: instance.definition_snapshot["title"],
      reward_name: instance.definition_snapshot["reward"]["name"],
      completed_at: e.completed_at
    }
  )

  :ok
end
```

### `ObjectTakenFromRoom` + `ObjectDroppedInRoom` (existing Commanded events) — extension

The existing handlers already broadcast `PlayerInventoryChanged`. Extend each to additionally broadcast a `PlayerQuestProgress` event for any active quest whose criteria reference the touched object's quest_tag:

```elixir
def handle(%ObjectTakenFromRoom{player_id: pid, object_id: oid} = e, _meta) do
  # ... existing PlayerInventoryChanged + RoomObjectTaken broadcasts ...

  for quest <- Quests.active_quests_referencing_object(pid, oid) do
    progress = Quests.progress_for(quest)

    PubSub.broadcast(
      AgenticRealms.PubSub,
      Topics.player_topic(pid),
      %PlayerQuestProgress{quest_id: quest.id, criteria: progress}
    )
  end

  :ok
end
```

`Quests.active_quests_referencing_object/2` reads the player's active quests, finds the object's behaviors (from the inserted row), and returns the subset of active quests whose `definition_snapshot.criteria` mention the same `quest_tag`. Implementation is a single read + in-memory filter.

`ObjectDroppedInRoom` is symmetric: same lookup, broadcast with the now-decremented counts.

## Subscriber: `GameLive`

`lib/agenticrealms_web/live/game_live.ex` gains three new `handle_info/2` clauses:

```elixir
def handle_info(%PlayerQuestAccepted{} = e, socket) do
  quests = socket.assigns.quests ++ [%{
    quest_id: e.quest_id,
    title: e.title,
    narrative: e.narrative,
    criteria: e.criteria
  }]

  {:noreply, assign(socket, :quests, quests)}
end

def handle_info(%PlayerQuestProgress{quest_id: id, criteria: c}, socket) do
  quests =
    Enum.map(socket.assigns.quests, fn
      %{quest_id: ^id} = q -> %{q | criteria: c}
      other -> other
    end)

  {:noreply, assign(socket, :quests, quests)}
end

def handle_info(%PlayerQuestFinalized{quest_id: id} = e, socket) do
  active = Enum.reject(socket.assigns.quests, &(&1.quest_id == id))
  completed = [%{
    quest_id: e.quest_id,
    title: e.title,
    completed_at: e.completed_at,
    reward_name: e.reward_name
  } | socket.assigns.completed_quests]

  {:noreply,
   socket
   |> assign(:quests, active)
   |> assign(:completed_quests, completed)}
end
```

The `:completed_quests` assign is new in `GameLive.mount/3` (initialized to `Quests.history_for(player_id)`).

## Tests

- `test/agenticrealms/ui_event_broadcaster_quest_test.exs`:
  - `QuestAccepted` → `PlayerQuestAccepted` broadcast with correct fields.
  - `QuestCompleted` → `PlayerQuestFinalized` broadcast with reward name.
  - `ObjectTakenFromRoom` for a tagged object → `PlayerQuestProgress` broadcast with incremented count.
  - `ObjectDroppedInRoom` for a tagged object → `PlayerQuestProgress` broadcast with decremented count.
- `test/agenticrealms_web/live/game_live_quest_test.exs`:
  - `GameLive` receives each event and updates assigns correctly.
