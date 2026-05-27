# Quickstart: Quest System (v1, FetchQuest)

This walkthrough exercises every state transition for the FetchQuest feature against a freshly seeded world. The "Orchard Keeper" NPC is seeded with one FetchQuest in its catalog; three rooms are seeded as spawn rooms for the three golden apples.

## Pre-requisites

- Working dev environment (Postgres + EventStore running; matches the dev setup used for feature 012).
- Branch `013-quest-system` checked out.
- Database is at the post-012 schema (i.e., the maps-feature migrations have been applied).

## Setup (one-time)

```bash
# Apply quest migrations
mix ecto.migrate

# Re-seed the world (rebuilds the world graph including the Orchard Keeper)
mix run priv/repo/seeds.exs
```

After the seed runs, the world contains (in addition to whatever 012 set up):

- A `npc_blueprint` for **"Orchard Keeper"** with one FetchQuest in `quests`:
  - slug: `golden_apples`
  - title: *The Orchard Keeper's Errand*
  - narrative: *Three golden apples have rolled away from my orchard. Bring them back.*
  - criteria: `[%{name: "Golden Apples", quest_tag: "quest.orchard.golden_apple", target_count: 3, spawn_room_ids: [<room_id_1>, <room_id_2>, <room_id_3>]}]`
  - reward: `%{name: "bigger golden apple", description: "An impossibly large golden apple, warm to the touch."}`
- One clone of the Orchard Keeper placed in the room next to the existing Stone Atrium.
- The three designated spawn rooms exist in the world and are reachable on foot from the Orchard Keeper. **No golden apples exist in any room yet** — they only spawn when a specific player accepts the quest.

## Walkthrough

### 1. Mount the GameLive

```bash
mix phx.server
# Open http://localhost:4000, log in as a test player, enter the game.
```

**Verify**:
- Quest log HUD card on the right shows "0 active". List is empty.
- Click the HUD card → quest modal opens → both "Active" and "Completed" tabs are empty.

### 2. Walk to the Orchard Keeper and start a chat

The Orchard Keeper NPC is one room east of the Stone Atrium (or wherever the seed placed it; check `seed.ex` for the exact path).

```text
> east
> chat orchard keeper
```

**Verify**:
- A chat session opens.
- The NPC's system prompt context now contains `quest_context` with the `golden_apples` slug in `offerable_quests`, no active instances, no completed slugs.

### 3. NPC offers the quest

Say hello and let the NPC bring up the quest (the LLM is told in its system prompt to offer when appropriate). Or prompt directly:

```text
> "Do you have any work for me?"
```

**Expected NPC reply**: a conversational mention of the golden-apples quest — "Three of my apples have rolled away..." (exact wording is the LLM's). No tool call yet — `offer_quest` does not exist as a tool (per the clarification, the offer is purely conversational).

### 4. Accept the quest

```text
> "Sure, I'll help."
```

**Expected behavior**:
- The NPC's LLM calls the `accept_quest` tool with `slug: "golden_apples"`.
- `Commands.accept_quest/3` validates and dispatches; the `Quest` aggregate emits `QuestAccepted`.
- `WorldProjector` inserts a `quest_instances` row (`state="active"`) and dispatches 3 `PlaceObject` commands (one per spawn room) with `quest_player_id = your player_id` and `quest_instance_id = the new quest_id`.
- `UIEventBroadcaster` broadcasts `PlayerQuestAccepted` on your `player:<id>` topic.
- The Orchard Keeper's next message acknowledges the acceptance ("I knew I could count on you...").

**Verify**:
- Quest log HUD card now shows "1 active" with a row: *The Orchard Keeper's Errand* + `Golden Apples: 0 / 3`.
- Click the HUD card → modal "Active" tab shows the same quest with the full narrative.

### 5. Walk to each spawn room and look — quest items are visible only to you

```text
> west
> west
> south  (or however the seed laid out the rooms)
> look
```

**Verify**:
- The room renders a `· golden apple — …` line in its objects list.
- **Multi-player check**: in a separate browser/incognito session, log in as a different test player and visit the same room. They do NOT see the golden apple — it's scoped to your `player_id` via `quest_player_id`.

### 6. Pick up the first apple

```text
> take golden apple
```

**Expected behavior**:
- `Commands.take/2` resolves the object via `resolve_object_in_room/3` (which honors the viewer filter), dispatches `TakeObject`, Room aggregate emits `ObjectTakenFromRoom`.
- `UIEventBroadcaster.handle/2` for `ObjectTakenFromRoom`:
  1. Broadcasts the existing `PlayerInventoryChanged(:added)`.
  2. Looks up your active quests whose criteria mention `quest.orchard.golden_apple` (the instance-scoped tag).
  3. Recomputes per-criterion progress = `1 / 3`.
  4. Broadcasts `PlayerQuestProgress`.
- `GameLive` updates `:quests` assign → HUD card row now shows `Golden Apples: 1 / 3`.

**Verify**:
- Apple appears in inventory.
- Quest log line updates live to `1 / 3` (no page reload).

### 7. Drop and re-pick to confirm progress regression

```text
> drop golden apple
```

**Verify**:
- Quest log line drops back to `0 / 3`.
- A dropped apple sits in the current room, visible only to you (still has `quest_player_id` set).

```text
> take golden apple
```

**Verify**:
- Quest log returns to `1 / 3`.

### 8. Collect the remaining two apples

```text
> [walk to second spawn room]
> take golden apple
> [walk to third spawn room]
> take golden apple
```

**Verify**:
- Quest log advances `1/3 → 2/3 → 3/3` in real time as each is picked up.

### 9. Check progress mid-chat (optional)

Walk back to the Orchard Keeper, start a chat, and say:

```text
> "How am I doing?"
```

**Expected behavior**: NPC's LLM calls `check_progress` with the quest_id (which is in the NPC's system prompt as part of `active_instances`). Tool returns `%{ok: true, quest_id: ..., criteria: [%{name: "Golden Apples", count: 3, target: 3}]}`. The NPC responds in-character ("You've gathered all three!").

### 10. Finalize

```text
> "Here you go."
```

**Expected behavior**:
- NPC's LLM calls `finalize_quest` with the quest_id.
- `Commands.finalize_quest/2` validates: instance is yours, is active, all criteria satisfied. Captures the three apple object ids as `consumed_object_ids`. Generates `reward_object_id`. Dispatches `FinalizeQuest`.
- `Quest` aggregate emits the four events: `QuestItemsConsumed`, `QuestRewardMinted`, `QuestCompleted`, `QuestItemsCleanedUp`.
- `QuestProjector` applies all four in one Repo transaction.
- `UIEventBroadcaster` broadcasts `PlayerQuestFinalized`.
- The Orchard Keeper says something in-character about handing over the bigger golden apple.

**Verify**:
- Inventory no longer contains the three small golden apples.
- Inventory now contains a "bigger golden apple".
- Quest log HUD card shows "0 active". Row is gone.
- Quest modal "Active" tab is empty; "Completed" tab shows *The Orchard Keeper's Errand* with the completion timestamp and reward name.

### 11. Try to re-accept the same quest

Back in a chat with the Orchard Keeper:

```text
> "Got any more work?"
```

**Expected behavior**:
- The NPC's system prompt context now lists `golden_apples` in `completed_slugs`, NOT in `offerable_quests`.
- The LLM will NOT call `accept_quest` for `golden_apples`. It will respond in-character ("You've already done me that favor.") referencing the prior completion.
- Even if the LLM mis-fires and calls `accept_quest("golden_apples")` anyway, the wrapper returns `{:error, :already_completed}` and the LLM renders the refusal on its next turn. Zero state change.

### 12. Restart recovery test (SC-006)

Accept the quest again with a second test player. Pick up two of the three apples. Then:

```bash
# Stop the Phoenix server (Ctrl-C twice in iex, or kill the process).
# Restart it:
mix phx.server
```

Reconnect as the second test player.

**Verify**:
- Quest log shows the quest still active at `2 / 3`.
- The two collected apples are still in inventory.
- The third apple is still in its spawn room, visible only to you.
- No double-spawn occurred (the quest_instances row + objects rows survived; no event was replayed that would spawn additional apples).

### 13. Multi-player isolation test (SC-003)

In two separate browser sessions, log in as two different test players. Both walk to the Orchard Keeper and both accept the quest within seconds of each other.

**Verify**:
- Each player sees a quest log entry with their own `quest_id`.
- Each spawn room contains TWO golden apples in the database (one per player), but each player sees ONLY their own when they `look`.
- Player A picks up an apple → Player A's progress goes to `1 / 3`, Player B's stays at `0 / 3`.
- Player A's `take` on player B's apple is impossible (the apple is not in the visible objects list and `resolve_object_in_room/3` won't return it). Even if a malicious client crafts a `take` payload with the apple's exact id, the `quest_player_id` check at the take wrapper denies it (`resolve_object_in_room/3` returns nil).

## Troubleshooting

- **Quest log doesn't update on pickup**: check `UIEventBroadcaster` logs — the new `PlayerQuestProgress` broadcast should fire on every `ObjectTakenFromRoom` for a tagged item. Verify `Quests.active_quests_referencing_object/2` returns the quest.
- **NPC offers a completed quest**: check the system prompt — `completed_slugs` should be populated and `offerable_quests` should exclude that slug. The LLM is a soft channel; the hard guarantee is the `Commands.accept_quest/3` wrapper, which will refuse with `{:error, :already_completed}`.
- **Apple visible to other players**: check `Queries.list_objects_in_room_for_viewer/2` is being called instead of the legacy `list_objects_in_room/1` for room rendering. All room-rendering call sites must thread the viewer's `player_id` through.
- **Finalize fails mysteriously**: read the tool result. The `details.missing` field lists exactly which criterion is short. The most common cause is an apple dropped in another room — pick it up and try again, or re-collect from inventory.

## Reset

To clear quest state without resetting the entire world:

```bash
psql $DATABASE_URL -c "DELETE FROM world_objects WHERE quest_instance_id IS NOT NULL;"
psql $DATABASE_URL -c "DELETE FROM quest_instances;"
```

This wipes the read model. To also clear the event store of quest events:

```bash
# Quest events live in the standard event store; a full event-store reset clears them along with everything else.
mix do event_store.drop, event_store.create, event_store.init, ecto.reset
mix run priv/repo/seeds.exs
```

(Note that the full reset undoes the world graph too; only use it in dev when you want a fully clean slate.)
