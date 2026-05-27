# Contract: command-dispatch wrappers in `AgenticRealms.World.Commands`

Three new wrappers are added to `lib/agenticrealms/world/commands.ex`, mirroring the existing `take/2` / `drop/2` pre-dispatch-validation pattern. All three return `{:ok, ...}` or `{:error, reason, details}` and are the SOLE entry points for the NPCChat tool layer.

## `accept_quest/3`

```elixir
@spec accept_quest(player_id :: integer, npc_blueprint_id :: string, slug :: string)
  :: {:ok, quest_id :: binary}
   | {:error, :unknown_slug}
   | {:error, :already_completed}
   | {:error, :already_active, existing_quest_id :: binary}
```

**Algorithm**:

1. Look up the NPC blueprint via `Repo.get/2`. If missing → propagate `{:error, :unknown_npc}` (defensive — should not happen in normal flows because the conversation context already validated the NPC at chat start).
2. Find the quest definition in `blueprint.quests` matching `slug`. If missing → `{:error, :unknown_slug}`.
3. Query `quest_instances` for `(player_id, npc_blueprint_id, slug)`:
   - If a row with `state = "completed"` exists → `{:error, :already_completed}`.
   - If a row with `state = "active"` exists → `{:error, :already_active, that_row.id}`.
4. Generate `quest_id = Ecto.UUID.generate()`.
5. Build `definition_snapshot` by deep-copying the template definition and rewriting each criterion's `quest_tag` to the **instance-scoped** form:
   - Template tag `"quest.orchard.golden_apple"` becomes instance tag `"quest.013-quest-system.orchard.golden_apple.<first_8_chars_of_quest_id>"`.
   - This is the only place tags are rewritten. Everything downstream uses the snapshotted tags.
6. Dispatch `%AcceptQuest{quest_id, player_id, npc_blueprint_id, slug, definition_snapshot, accepted_at: DateTime.utc_now()}`.
7. On dispatch `:ok` → return `{:ok, quest_id}`. On aggregate refusal (race-only) → translate to the corresponding `{:error, ...}`.

## `check_progress/2`

```elixir
@spec check_progress(player_id :: integer, quest_id :: binary)
  :: {:ok, criteria :: [criterion_progress]}
   | {:error, :unknown_instance}
```

**Algorithm**:

1. `case Quests.quest_instance(quest_id)` →
   - `nil` → `{:error, :unknown_instance}`
   - `%QuestInstance{state: "active", player_id: ^player_id} = inst` → continue
   - `%QuestInstance{}` (wrong player or completed) → `{:error, :unknown_instance}`
2. `progress = Quests.progress_for(inst)` → returns `[%{name, count, target}, ...]`.
3. Return `{:ok, progress}`.

**Pure read** — no dispatch, no state change.

## `finalize_quest/2`

```elixir
@spec finalize_quest(player_id :: integer, quest_id :: binary)
  :: {:ok, %{quest_id: binary, reward_name: string, reward_description: string}}
   | {:error, :unknown_instance}
   | {:error, :criteria_unmet, missing :: [criterion_progress]}
```

**Algorithm**:

1. `case Quests.quest_instance(quest_id)` →
   - `nil` → `{:error, :unknown_instance}`
   - `%QuestInstance{state: "active", player_id: ^player_id} = inst` → continue
   - anything else → `{:error, :unknown_instance}`
2. Read all objects with `quest_instance_id = quest_id`. Partition into:
   - `in_inventory`: `player_id = ^player_id AND room_id IS NULL`
   - `elsewhere`: everything else (in some room, or held by another player — though FR-016 ensures only this player can pick them up; "elsewhere" in practice means dropped in a room).
3. For each criterion in `inst.definition_snapshot.criteria`:
   - Find matching items in `in_inventory` by `quest_tag`.
   - If `count(matches) < target_count` → record `%{name, count: count(matches), target: target_count}` in `missing`.
   - Otherwise, pick `target_count` matches and append their ids to `consumed_object_ids`.
4. If `missing` is non-empty → `{:error, :criteria_unmet, missing}`. Do NOT dispatch.
5. Compute `remaining_quest_object_ids = (in_inventory ids ∪ elsewhere ids) -- consumed_object_ids`.
6. Generate `reward_object_id = Ecto.UUID.generate()`.
7. Build `FinalizeQuest`:
   ```elixir
   %FinalizeQuest{
     quest_id: quest_id,
     consumed_object_ids: consumed_object_ids,
     reward_object_id: reward_object_id,
     reward_name: inst.definition_snapshot["reward"]["name"],
     reward_description: inst.definition_snapshot["reward"]["description"],
     remaining_quest_object_ids: remaining_quest_object_ids,
     completed_at: DateTime.utc_now()
   }
   ```
8. Dispatch. On `:ok` → return `{:ok, %{quest_id, reward_name, reward_description}}`. On aggregate refusal → translate.

## Atomicity & invariants

- The wrappers are the **only** caller of `AcceptQuest` / `FinalizeQuest` commands; the aggregate is the **only** consumer. There is no path that bypasses the wrapper's validation.
- The wrappers do not hold any locks. Concurrent invocations on the same `(player_id, npc_blueprint_id, slug)` can both pass step 3; the partial unique index on `quest_instances` is the backstop that surfaces the duplicate as a projector error in the second branch.
- The wrappers compute the consumed and remaining object id sets **at dispatch time**. If the player's inventory changes between the wrapper's read and the projector's apply, the snapshot in the command still wins — the projector deletes exactly those ids. This is acceptable in v1 because Commanded's per-aggregate dispatch is serialized.

## Tests (`test/agenticrealms/world/commands_quest_test.exs`)

- `accept_quest/3` returns each error branch correctly, and the success branch returns a new `quest_id` and dispatches `AcceptQuest`.
- `accept_quest/3` rewrites quest tags to instance-scoped form in `definition_snapshot`.
- `check_progress/2` returns each error branch, and computes correct counts from a fixture inventory.
- `finalize_quest/2` returns each error branch, captures the correct `consumed_object_ids` and `remaining_quest_object_ids`, and dispatches `FinalizeQuest`.
- `finalize_quest/2` returns `{:error, :criteria_unmet, missing: ...}` when the player has only `target_count - 1` of a criterion's items, with the exact missing entry.
