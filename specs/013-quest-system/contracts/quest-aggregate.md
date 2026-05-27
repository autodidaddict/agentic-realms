# Contract: `Quest` aggregate

**Module**: `AgenticRealms.World.Quest` — new file `lib/agenticrealms/world/quest.ex`.

**Identity**: `quest_id` (binary_id). Registered in `World.Router` as `identify(Quest, by: :quest_id, prefix: "quest-")`.

## Struct

```elixir
defstruct [
  :quest_id,
  :player_id,
  :npc_blueprint_id,
  :slug,
  :state,                  # :initial | :active | :completed
  :definition_snapshot,
  :accepted_at,
  :completed_at
]
```

Initial replay starts from `%Quest{state: :initial}`.

## State machine

```text
:initial  ──AcceptQuest──▶ :active   ──FinalizeQuest──▶ :completed
:initial  ──FinalizeQuest─▶ {:error, :unknown_instance}
:active   ──AcceptQuest───▶ {:error, :already_active}
:completed ──*────────────▶ {:error, :already_completed}
```

## `execute/2`

```elixir
# Initial → Active
def execute(%Quest{state: :initial}, %AcceptQuest{} = cmd) do
  %QuestAccepted{
    quest_id: cmd.quest_id,
    player_id: cmd.player_id,
    npc_blueprint_id: cmd.npc_blueprint_id,
    slug: cmd.slug,
    definition_snapshot: cmd.definition_snapshot,
    accepted_at: cmd.accepted_at
  }
end

# Active → Completed (emits 4 events in one execute call)
def execute(%Quest{state: :active, quest_id: id, player_id: pid}, %FinalizeQuest{quest_id: id} = cmd) do
  [
    %QuestItemsConsumed{
      quest_id: id,
      player_id: pid,
      consumed_object_ids: cmd.consumed_object_ids
    },
    %QuestRewardMinted{
      quest_id: id,
      player_id: pid,
      reward_object_id: cmd.reward_object_id,
      reward_name: cmd.reward_name,
      reward_description: cmd.reward_description
    },
    %QuestCompleted{
      quest_id: id,
      player_id: pid,
      completed_at: cmd.completed_at
    },
    %QuestItemsCleanedUp{
      quest_id: id,
      remaining_quest_object_ids: cmd.remaining_quest_object_ids
    }
  ]
end

# Refusals
def execute(%Quest{state: :active}, %AcceptQuest{}), do: {:error, :already_active}
def execute(%Quest{state: :completed}, _cmd), do: {:error, :already_completed}
def execute(%Quest{state: :initial}, %FinalizeQuest{}), do: {:error, :unknown_instance}
```

**Note**: Aggregate-level refusals (`{:error, ...}`) should not normally be observed by the command-wrapper layer, because the wrappers validate against the read model before dispatching. Aggregate refusals are the last-line defense against a race (e.g., two concurrent finalize attempts on the same `quest_id`); they surface to the wrapper, which translates them to the uniform `{ok: false, reason: ...}` tool result.

## `apply/2`

```elixir
def apply(%Quest{}, %QuestAccepted{} = e) do
  %Quest{
    quest_id: e.quest_id,
    player_id: e.player_id,
    npc_blueprint_id: e.npc_blueprint_id,
    slug: e.slug,
    state: :active,
    definition_snapshot: e.definition_snapshot,
    accepted_at: e.accepted_at,
    completed_at: nil
  }
end

def apply(%Quest{} = q, %QuestCompleted{completed_at: at}) do
  %{q | state: :completed, completed_at: at}
end

# QuestItemsConsumed / QuestRewardMinted / QuestItemsCleanedUp do not change aggregate state — they are read-model side effects only.
def apply(quest, %QuestItemsConsumed{}), do: quest
def apply(quest, %QuestRewardMinted{}), do: quest
def apply(quest, %QuestItemsCleanedUp{}), do: quest
```

## Replay

Replaying `[QuestAccepted, QuestItemsConsumed, QuestRewardMinted, QuestCompleted, QuestItemsCleanedUp]` yields `%Quest{state: :completed}`. Replaying only `[QuestAccepted]` yields `%Quest{state: :active}`. Any other event ordering is structurally impossible because the aggregate only emits the four-event finalize bundle atomically.

## Tests (see `test/agenticrealms/world/quest_test.exs`)

- `AcceptQuest` from `:initial` emits a `QuestAccepted` with all fields copied.
- `AcceptQuest` from `:active` returns `{:error, :already_active}`.
- Any command from `:completed` returns `{:error, :already_completed}`.
- `FinalizeQuest` from `:initial` returns `{:error, :unknown_instance}`.
- `FinalizeQuest` from `:active` emits exactly `[QuestItemsConsumed, QuestRewardMinted, QuestCompleted, QuestItemsCleanedUp]` in order, each with the fields copied from the command.
- Replay round-trip: `apply` on the full event sequence produces a `:completed` aggregate matching the input.
