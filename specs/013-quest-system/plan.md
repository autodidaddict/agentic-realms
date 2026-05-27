# Implementation Plan: Quest System (v1, FetchQuest)

**Branch**: `013-quest-system` | **Date**: 2026-05-27 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/013-quest-system/spec.md`

## Summary

This feature introduces the first quest mechanic to the world. It adds:

1. **`Quest` aggregate** (new) — one aggregate per accepted quest instance, identified by `quest_id`. States: `active` → `completed`. Snapshots the catalog definition at acceptance time so subsequent definition edits never invalidate in-flight quests.
2. **NPC quest catalog** — extends the existing `NPCBlueprint` aggregate + schema with a `quests` field (list of FetchQuest definitions: slug, title, narrative, criteria, reward, spawn rooms). Authored at NPC creation time and replayable from events.
3. **Quest-scoped objects** — extends the existing `Object` schema with `quest_player_id` and `quest_instance_id` fields. Objects with these fields set are visible/takeable only to the matching player. Items behave like any other inventory item once picked up — the new visibility rule is enforced uniformly in the read-model queries.
4. **Three new NPCChat tools** — `accept_quest`, `check_progress`, `finalize_quest`, registered alongside the existing `say` / `emote` tools. All three return a uniform `{ok: true, ...}` / `{ok: false, reason: <code>, details: ...}` shape; the NPC LLM renders all responses (including refusals) in-character on its next turn. Per the clarification session, the engine never speaks directly to the player from these tools.
5. **NPC system-prompt context extension** — adds the NPC's quest catalog, this player's active quest instances with this NPC, and this player's completed quest slugs with this NPC to the per-turn context. The LLM uses these to mention quests in prose, refuse already-completed quests in-character, and pick the right `quest_id` when calling `check_progress` / `finalize_quest`.
6. **`QuestProjector`** — projects `QuestAccepted`, `QuestItemsConsumed`, `QuestRewardMinted`, `QuestCompleted`, `QuestItemsCleanedUp` into a `quest_instances` read-model table and into direct `objects` table mutations for the items the quest owns end-to-end. Spawning of quest items into rooms goes through the existing `PlaceObject` command on each spawn `Room` aggregate so the items are first-class room contents — they're just stamped with the visibility fields.
7. **Live quest log UI** — replaces the existing `GameData.quests/0` and `GameData.quest_details/0` stubs (`game_data.ex:85–129`) with a real per-player read driven off `quest_instances` + active-quest progress computation. The existing `hud_card "Quest Log"` (`game_components.ex:434`) keeps its current shape but its rows become per-criterion progress lines (`<criterion name>: <n> / <target>`). The existing `quest_modal/1` (`game_components.ex:1057`) gains an Active/Completed split to back FR-025/FR-026. Updates flow over the existing `player_topic(player_id)` PubSub channel as new `PlayerQuestAccepted`, `PlayerQuestProgress`, `PlayerQuestFinalized` UI events emitted from `UIEventBroadcaster`.

The model the user explicitly chose during clarification (Option A — instanced world items per quest player) is implemented by leveraging the **existing per-viewer filter pattern** in `Queries.list_other_players/2` (`queries.ex:380–399`). Filtering items by `quest_player_id` is a strictly additive extension to `Queries.list_objects_in_room/1` (`queries.ex:317–324`): `WHERE quest_player_id IS NULL OR quest_player_id = $viewer_id`. The same predicate is applied wherever items in a room are listed for a viewer (look, examine, take resolution). Items in inventory remain trivially per-player by virtue of the existing `player_id` foreign key — no change to inventory rendering is required.

Finalization atomicity is achieved by **pre-validating in the command-dispatch wrapper** (read the player's inventory, match against the snapshot criteria) and then dispatching `FinalizeQuest` to the `Quest` aggregate, which emits three events in one transaction: `QuestItemsConsumed` (carries the exact object ids to destroy, captured by the wrapper at pre-dispatch read time), `QuestRewardMinted` (carries reward name + description), and `QuestCompleted`. Plus a fourth `QuestItemsCleanedUp` event listing any of the quest's spawned objects that remain in the world (uncollected in rooms or dropped elsewhere) — those are deleted in the same projector transaction. If pre-validation fails, the wrapper returns `{:error, :criteria_unmet, missing: [...]}` to the NPCChat tool layer **without dispatching**; no state changes occur.

## Technical Context

**Language/Version**: Elixir 1.15+ on OTP 26+ (existing project baseline; consistent with feature 012).

**Primary Dependencies (existing, reused — no new dependencies)**:
- `phoenix ~> 1.8`, `phoenix_live_view ~> 1.1.0`, `phoenix_pubsub` — quest log lives in the existing `GameLive` (`live/game_live.ex`); SVG/HEEx components in `game_components.ex` already include the quest HUD card and modal stubs.
- `commanded ~> 1.4` + `commanded_eventstore_adapter ~> 1.4` — used for `Quest` aggregate + new events. NPCBlueprint extension adds new fields to existing `NPCBlueprintCreated` event.
- `ecto_sql ~> 3.11` + `postgrex` — schema migrations for `quest_instances` (new), `world_objects` extension (two new nullable columns), `npc_blueprints` extension (one new array column).
- `jason ~> 1.4` — already used for event + JSON-column serialization.

**Reused project infrastructure**:
- `AgenticRealms.World.Router` — extended with a new `Quest` aggregate identification (`identify(Quest, by: :quest_id, prefix: "quest-")`) and a new dispatch entry for `[AcceptQuest, FinalizeQuest]`.
- `AgenticRealms.World.Commands` — adds three new dispatch wrappers (`accept_quest/3`, `check_progress/2`, `finalize_quest/2`) that mirror the existing `take/2` pattern (pre-dispatch validation against the read model, then dispatch).
- `AgenticRealms.World.Projections.WorldProjector` — extended with handlers for the four new quest events. Quest-scoped object cleanup (`QuestItemsCleanedUp`) is a direct delete in the projector since the quest instance is authoritative over the lifecycle of objects it spawned; everyday take/drop continues to flow through `Room` aggregate events.
- `AgenticRealms.World.NPCChat.Tools.list/0` (`npc_chat/tools.ex:17–67`) — extended with three new tool schemas (`accept_quest`, `check_progress`, `finalize_quest`). All three follow the uniform `{ok: bool, ...}` shape per FR-011a (set during clarification).
- `AgenticRealms.World.NPCChat.Context` — extended with a per-(viewer, NPC) summary of the NPC's quest catalog, the viewer's active quest instances with this NPC (with current per-criterion progress), and the viewer's completed quest slugs with this NPC.
- `AgenticRealms.UIEventBroadcaster` — extended with handlers for the four new quest events that broadcast `PlayerQuestAccepted`, `PlayerQuestProgress`, and `PlayerQuestFinalized` UI events on the existing `player:<player_id>` topic. Additionally, the existing `ObjectTakenFromRoom` and `ObjectDroppedInRoom` handlers gain a side-effect that recomputes progress for any of the affected player's active quests whose criteria mention the touched object's quest tag, and broadcasts `PlayerQuestProgress`.
- `AgenticRealms.World.Queries.list_objects_in_room/1` (`queries.ex:317–324`) — extended with a viewer-aware overload `list_objects_in_room_for_viewer/2` that filters items where `quest_player_id IS NULL OR quest_player_id = $viewer_id`. All call sites for room-item rendering are updated to use the viewer-aware variant.
- `AgenticRealms.World.Queries.resolve_object_in_room/2` (`queries.ex:219–236`) — extended with the same viewer-aware filter so a non-owner cannot "take" or "examine" a quest-scoped item they cannot see.
- `AgenticRealmsWeb.GameLive` (`live/game_live.ex:103–106`) — `:quests`, `:quest_details`, `:selected_quest` assigns flip from `GameData` mock data to projector-driven reads (`Quests.active_for/1`, `Quests.history_for/1`). Three new `handle_info/2` clauses for `PlayerQuestAccepted` / `PlayerQuestProgress` / `PlayerQuestFinalized` keep the assigns in sync.
- `AgenticRealmsWeb.GameComponents.hud_card "Quest Log"` (`game_components.ex:434–443`) — rendering logic extended: each quest renders title + criteria lines `<name>: <n> / <target>`. The `count={"#{length(@quests)} active"}` stays accurate (completed quests are excluded from `@quests`).
- `AgenticRealmsWeb.GameComponents.quest_modal/1` (`game_components.ex:1057–1080`) — extended with an Active / Completed tab split. Active tab shows the same rows as the HUD card with the narrative summary; Completed tab shows completed quests indefinitely.

**Storage**:
- **New table `quest_instances`**: `id` (binary_id PK, the `quest_id`), `player_id` (bigint FK → `players.id`, NOT NULL), `npc_blueprint_id` (string FK → `npc_blueprints.id`, NOT NULL), `slug` (string NOT NULL), `state` (string NOT NULL: `"active"` or `"completed"`), `accepted_at` (utc_datetime NOT NULL), `completed_at` (utc_datetime NULL), `definition_snapshot` (jsonb NOT NULL — full FetchQuest definition at acceptance time: title, narrative, criteria, reward, spawn rooms), `reward_object_id` (binary_id NULL, populated on finalize). Unique partial index on `(player_id, npc_blueprint_id, slug)` WHERE `state = 'completed'` — enforces FR-012 (sticky one-time completion) at the DB layer. Index on `(player_id, state)` for fast "active quests for this player" lookups.
- **Extended `world_objects`** (`object.ex`): adds `quest_player_id` (bigint FK → `players.id`, NULL — set when the object is scoped to a quest) and `quest_instance_id` (binary_id FK → `quest_instances.id`, NULL — links the object to the quest that owns its lifecycle). Both are NULL for all pre-existing objects; the migration backfills NULL. Index on `quest_instance_id` to support bulk cleanup at finalize. Combined check constraint: `(quest_player_id IS NULL) = (quest_instance_id IS NULL)` — they are set together or not at all.
- **Extended `npc_blueprints`** (`npc_blueprint.ex`): adds `quests` (jsonb NOT NULL DEFAULT `'[]'::jsonb` — array of FetchQuest definitions). Existing blueprints get an empty array, which means "no quests offered" — exactly the prior behavior. The `NPCBlueprintCreated` event gains a `quests` field with the same default.
- **Persistent state is read-replay-safe**. The `quest_instances` table is rebuildable from event replay (every row maps 1:1 to a `Quest` aggregate's events). The `world_objects` extensions are rebuildable from the existing object events plus the new quest events for the two new fields.
- **No new volatile state**. No GenServers, no ETS tables, no per-player live caches.

**Testing**:
- `ExUnit` (existing) — unit + projector + LiveView.
- **Aggregate unit tests**:
  - `Quest.execute/2` + `Quest.apply/2`: `AcceptQuest` from `:initial` state emits `QuestAccepted`; from any other state returns `{:error, :already_active}`. `FinalizeQuest` from `:active` emits the 4-event tuple; from `:completed` returns `{:error, :already_completed}`. Mid-stream replay reconstructs the state correctly.
- **Command-wrapper unit tests** (`Commands.accept_quest`, `.finalize_quest`, `.check_progress`):
  - `accept_quest`: refusal for unknown slug, completed slug, already-active slug; success path returns `{:ok, quest_id}`.
  - `check_progress`: refusal for unknown instance or instance not belonging to caller; success path returns per-criterion counts derived from current inventory.
  - `finalize_quest`: refusal for unknown instance, instance not belonging to caller, unsatisfied criteria (with `missing: [...]`); success path captures the exact set of object ids to consume and dispatches the command.
- **Projector tests**:
  - `QuestAccepted` → row inserted into `quest_instances` with `state="active"`; spawn rooms each receive a `PlaceObject` command dispatch resulting in objects with `quest_player_id` + `quest_instance_id` set.
  - `QuestItemsConsumed` → matching `objects` rows deleted.
  - `QuestRewardMinted` → new object row inserted with `player_id` set, `quest_player_id`/`quest_instance_id` NULL (the reward is a normal item).
  - `QuestCompleted` → `quest_instances.state` set to `"completed"`, `completed_at` populated.
  - `QuestItemsCleanedUp` → all remaining objects with the given `quest_instance_id` are deleted.
  - **Idempotent replay**: each event handler uses `on_conflict: :nothing` / `Repo.delete_all/2` where applicable so replaying against a partially-populated read model is safe.
- **Viewer-filter query tests**:
  - `list_objects_in_room_for_viewer/2`: object with no `quest_player_id` visible to all; object with `quest_player_id=A` visible to A, hidden from B and from anonymous viewers.
  - `resolve_object_in_room/2`: same filter applied — non-owner cannot resolve the name.
- **NPCChat tool tests**:
  - Each of the three tools returns the uniform `{ok, ...}` / `{ok: false, reason, details}` shape on the documented branches.
  - Tool definitions are present in `Tools.list/0`.
- **NPCChat context tests**:
  - Per-(viewer, NPC) context renders the NPC's quest catalog, the viewer's active instances with progress counts, and the viewer's completed slugs.
- **UIEventBroadcaster tests**:
  - `QuestAccepted` → `PlayerQuestAccepted` broadcast on `player:<player_id>`.
  - `ObjectTakenFromRoom` for an object whose tag matches an active quest's criterion → `PlayerQuestProgress` broadcast with updated counts.
  - `ObjectDroppedInRoom` for the same → `PlayerQuestProgress` broadcast with counts decremented.
  - `QuestCompleted` → `PlayerQuestFinalized` broadcast.
- **LiveView integration**: a single `@moduletag :integration` test exercises US1–US3 end-to-end against a seeded orchard-keeper NPC with one FetchQuest in its catalog:
  - Mount LiveView → quest log empty.
  - Player chats with orchard keeper → mock the LLM tool-call invocation of `accept_quest` (no real LLM in this test).
  - Assert active quest appears in HUD card with `0 / 3` progress, three apples spawn in three rooms.
  - Player moves to each room → `look` shows the apple → `take golden apple` → progress advances.
  - Player returns to orchard keeper → mock `finalize_quest` tool-call → assert reward item in inventory, quest moves to Completed tab.
- **Multi-player isolation test**: two players accept the same quest from the same NPC concurrently → each player sees only their own apples; `take` by one player does not affect the other player's progress.
- **Restart recovery test**: with one active quest at `2 / 3` progress, stop and restart the Commanded application; on restart, assert the quest is still `:active`, the two collected apples are still in inventory, and the third apple is still in its spawn room (visible only to the owning player). Backed by SC-006.

**Target Platform**: Linux server BEAM cluster (production); macOS BEAM single-node (dev). Identical to feature 012.

**Project Type**: Phoenix LiveView web application.

**Performance Goals**:
- Active-quest progress recompute on inventory change: O(C) where C is the number of criteria across the affected player's active quests. Expected ≤ 10 criteria total in v1 (single FetchQuest with a few criteria). Sub-millisecond per recompute.
- Quest log re-render on progress event: server-side LiveView diff. End-to-end latency (object event → DOM update) ≤ 1 second per SC-002.
- `accept_quest` total latency including spawn-room dispatches: ≤ 500 ms p95 for a quest with ≤ 5 spawn rooms. Spawn dispatches are issued synchronously in the projector's transaction so the user sees the quest fully spawned before the quest log update lands.

**Constraints**:
- **No new dependencies.** All work done within the existing Elixir/Phoenix/Commanded/Ecto stack.
- **No NPC LLM dependency for state correctness.** The engine validates everything; the LLM is the intent parser and the character voice. A misbehaving LLM (hallucinated slug, wrong instance id) cannot corrupt state; it gets a `{ok: false, reason: ...}` and renders a refusal in-character on its next turn.
- **Sticky completion enforced at DB layer** via the partial unique index on `quest_instances`, not only in the aggregate. This protects against any race in concurrent accept attempts (FR-009 (b) + edge case "concurrent accept attempts").
- **Quest items are never silently dropped.** Whenever a player's inventory or a room's contents change a quest's progress, the broadcaster emits a `PlayerQuestProgress` event. There is no path where progress moves silently.
- **No backward-compat migration path needed for blueprints or objects.** Both new columns are nullable; existing rows are unaffected. `npc_blueprints.quests` defaults to `[]`.
- **Cluster correctness**: quest-progress recomputation in the broadcaster is pure DB-backed (no node-local state), so cross-node moves and reconnects work transparently.

**Scale/Scope**:
- Expected concurrent active quests per player: ≤ 5 (one FetchQuest template in v1; future templates will fit comfortably in the same data shape).
- Expected catalog size per NPC: ≤ 10 quests.
- Expected spawn objects per quest instance: ≤ 10 across all rooms.
- Total `quest_instances` rows over time: roughly (players × NPCs × quests-completed-per-player). Modest under any realistic load.

## Constitution Check

**Constitution file**: `.specify/memory/constitution.md` remains at template defaults (no concrete ratified principles). There are no enumerated gates to evaluate. PASS by default.

## Project Structure

### Documentation (this feature)

```text
specs/013-quest-system/
├── plan.md                         # This file
├── research.md                     # Phase 0 — aggregate-vs-Player decision, finalize atomicity, NPC context shape, viewer-filter SQL strategy, UI tab approach
├── data-model.md                   # Phase 1 — Quest aggregate state machine; quest_instances schema; world_objects + npc_blueprints extensions; PubSub event shapes
├── quickstart.md                   # Phase 1 — manual smoke test (seed orchard-keeper → chat → accept → pick apples → return → finalize → restart)
├── contracts/                      # Phase 1
│   ├── quest-aggregate.md          #   Quest aggregate: state machine, commands, events, replay
│   ├── npc-blueprint-quests.md     #   NPCBlueprint extension: quests field shape; NPCBlueprintCreated event extension
│   ├── object-quest-fields.md      #   world_objects extension: quest_player_id / quest_instance_id; viewer filter contract
│   ├── npc-chat-tools.md           #   accept_quest / check_progress / finalize_quest tool schemas + uniform return contract (FR-011a)
│   ├── command-wrappers.md         #   Commands.accept_quest/3, check_progress/2, finalize_quest/2 wrapper contracts (pre-dispatch validation)
│   ├── projector-quest.md          #   QuestProjector handlers for 4 quest events + on_conflict patterns
│   ├── ui-broadcast-events.md      #   PlayerQuestAccepted / PlayerQuestProgress / PlayerQuestFinalized struct shapes + emit rules
│   └── npc-system-prompt.md        #   NPC system-prompt context: catalog + active instances + completed slugs
├── checklists/
│   └── requirements.md             # From /speckit-specify
└── tasks.md                        # Phase 2 — /speckit-tasks output (NOT created here)
```

### Source Code (repository root)

Single Phoenix project, layout consistent with features 005–012. New files marked `+`; modified `M`.

```text
agenticrealms/
├── lib/
│   ├── agenticrealms/
│   │   └── world/
│   │       ├── quest.ex                                       + New aggregate. Struct: %Quest{quest_id, player_id, npc_blueprint_id, slug, state, definition_snapshot}. execute/2 handles AcceptQuest from :initial → QuestAccepted; FinalizeQuest from :active → [QuestItemsConsumed, QuestRewardMinted, QuestCompleted, QuestItemsCleanedUp]. apply/2 transitions :initial → :active → :completed.
│   │       ├── commands/
│   │       │   ├── accept_quest.ex                            + New command. Fields: quest_id, player_id, npc_blueprint_id, slug, definition_snapshot.
│   │       │   ├── finalize_quest.ex                          + New command. Fields: quest_id, consumed_object_ids, reward_object_id, reward_name, reward_description, remaining_quest_object_ids.
│   │       │   └── create_npc_blueprint.ex                      M  Add :quests field to the command struct (defaults to []). Validation: each entry is a valid FetchQuest map (slug present, ≥1 criterion, valid spawn_room_ids — checked at command dispatch against the read model).
│   │       ├── events/
│   │       │   ├── quest_accepted.ex                          + Fields: quest_id, player_id, npc_blueprint_id, slug, definition_snapshot, accepted_at.
│   │       │   ├── quest_items_consumed.ex                    + Fields: quest_id, player_id, consumed_object_ids.
│   │       │   ├── quest_reward_minted.ex                     + Fields: quest_id, player_id, reward_object_id, reward_name, reward_description.
│   │       │   ├── quest_completed.ex                         + Fields: quest_id, player_id, completed_at.
│   │       │   ├── quest_items_cleaned_up.ex                  + Fields: quest_id, remaining_quest_object_ids.
│   │       │   └── npc_blueprint_created.ex                     M  Add :quests field (default []). Backward-compat: existing events have no field → projector defaults it to [] on replay.
│   │       ├── npc_blueprint.ex                                 M  Add :quests to defstruct (default []). Extend execute/2 for CreateNPCBlueprint (carry through). Extend apply/2 for NPCBlueprintCreated (load quests). Validation of quest catalog shape lives here.
│   │       ├── commands.ex                                      M  accept_quest/3 wrapper (player_id, npc_blueprint_id, slug) → reads NPC catalog, validates slug existence, checks for completed/active duplicates, generates quest_id, dispatches AcceptQuest with definition snapshot. check_progress/2 wrapper — pure read; returns per-criterion counts from inventory. finalize_quest/2 wrapper — reads inventory, matches criteria, captures consumed_object_ids + remaining_quest_object_ids, mints reward_object_id, dispatches FinalizeQuest or returns {:error, :criteria_unmet, missing: [...]}. create_npc_blueprint extended to accept the new :quests field and validate spawn_room_ids exist.
│   │       ├── router.ex                                        M  Add identify(Quest, by: :quest_id, prefix: "quest-"). Add dispatch([AcceptQuest, FinalizeQuest], to: Quest).
│   │       ├── queries.ex                                       M  Add list_objects_in_room_for_viewer/2 (filters quest-scoped items by viewer). Update resolve_object_in_room/2 to apply the same filter. Add quests_active_for/1, quests_history_for/1, quest_instance/1 reads.
│   │       ├── quests.ex                                      + New module. Higher-level API: active_for(player_id) returns active quests with computed per-criterion progress; history_for(player_id) returns completed quests; progress_for(quest_id) computes current per-criterion counts from inventory + definition snapshot.
│   │       ├── projections/
│   │       │   ├── world_projector.ex                           M  Handle QuestAccepted → insert quest_instances row; dispatch PlaceObject command to each spawn room for each criterion item (with quest_player_id, quest_instance_id passed through). Handle NPCBlueprintCreated extended to project :quests. Handle ObjectPlacedInRoom extended to read quest_player_id + quest_instance_id from the event and persist them on the objects row.
│   │       │   └── quest_projector.ex                         + New projector. Handles QuestItemsConsumed → DELETE FROM objects WHERE id IN (consumed_object_ids). Handles QuestRewardMinted → INSERT new objects row (player_id set, quest_player_id NULL, quest_instance_id NULL — reward is a normal item). Handles QuestCompleted → UPDATE quest_instances SET state='completed', completed_at=... Handles QuestItemsCleanedUp → DELETE FROM objects WHERE id IN (remaining_quest_object_ids). Uses on_conflict: :nothing where applicable for replay idempotency.
│   │       ├── schemas/
│   │       │   ├── object.ex                                    M  Add :quest_player_id (belongs_to :quest_player, Player, foreign_key: :quest_player_id), :quest_instance_id (belongs_to :quest_instance, QuestInstance, foreign_key: :quest_instance_id). Both nullable.
│   │       │   ├── quest_instance.ex                          + New Ecto schema. Mirrors quest_instances table. has_many :scoped_objects, Object, foreign_key: :quest_instance_id.
│   │       │   └── npc_blueprint.ex                             M  Add :quests field (array of map, default []).
│   │       ├── place_object.ex                                  M  Add quest_player_id + quest_instance_id to the PlaceObject command struct (both nullable). The Room aggregate passes them through to ObjectPlacedInRoom.
│   │       ├── events/object_placed_in_room.ex                  M  Add quest_player_id + quest_instance_id fields (nullable). Forward-compat: missing fields on legacy events default to nil at apply time.
│   │       ├── npc_chat/
│   │       │   ├── tools.ex                                     M  Add accept_quest, check_progress, finalize_quest tool definitions to list/0. Tool result envelope: {ok: bool, ...}.
│   │       │   ├── conversation.ex                              M  Add handle_tool_call clauses for the three new tools. Each invokes the matching Commands wrapper, then returns the structured result to the LLM in its next round-trip.
│   │       │   ├── context.ex                                   M  Add per-(viewer, NPC) summary: quest_catalog (from blueprint), active_quest_instances_with_this_npc (slug + per-criterion progress + quest_id), completed_quest_slugs_with_this_npc. Rendered into the system prompt at every turn.
│   │       │   └── system_prompt.ex                             M  Extend the prompt template to include the quest section described above when present.
│   │       └── seed.ex                                          M  Adds one questgiver NPCBlueprint ("Orchard Keeper") with one FetchQuest in its catalog (collect 3 golden apples; spawn rooms = 3 specific rooms seeded for this; reward = "bigger golden apple"). The seed runs after the existing world seed so the spawn rooms already exist.
│   │   └── ui_event_broadcaster.ex                              M  Add handle/2 clauses for QuestAccepted (broadcast PlayerQuestAccepted on player:<id>), QuestCompleted (broadcast PlayerQuestFinalized on player:<id>). Extend existing ObjectTakenFromRoom + ObjectDroppedInRoom handlers: after the existing PlayerInventoryChanged broadcast, look up the player's active quests; for each one whose criteria mention the object's quest tag, recompute progress and broadcast PlayerQuestProgress.
│   ├── agenticrealms_web/
│   │   ├── topics.ex                                            # (no change; existing player:<id> topic is reused)
│   │   ├── live/
│   │   │   └── game_live.ex                                     M  Replace assign(:quests, GameData.quests()) with assign(:quests, Quests.active_for(player_id)). Replace assign(:quest_details, GameData.quest_details()) with assign(:quest_details, Quests.history_for(player_id) ++ Quests.active_for(player_id) -- or restructure as a unified detail list). Add handle_info/2 for PlayerQuestAccepted (append to :quests), PlayerQuestProgress (update specific quest's per-criterion line), PlayerQuestFinalized (remove from :quests, add to completed tab data). Keep the existing select_quest handler.
│   │   └── components/
│   │       └── game_components.ex                               M  hud_card "Quest Log" — render each quest with title and per-criterion lines: <div class="qt">{quest.title}</div> + <div :for={c <- quest.criteria}>{c.name}: {c.count} / {c.target}</div>. quest_modal — add a tab strip ("Active" / "Completed") above the existing detail rendering; show the per-tab list on the left, details on the right.
│   ├── game_data.ex                                             M  DELETE quests/0 and quest_details/0 functions. Replace any remaining mock-data references in game_live.ex with calls to Quests.* readers.
├── priv/
│   └── repo/
│       └── migrations/
│           ├── <ts1>_create_quest_instances.exs               + Creates quest_instances table with all fields described above; partial unique index on (player_id, npc_blueprint_id, slug) WHERE state='completed'; index on (player_id, state).
│           ├── <ts2>_extend_world_objects_with_quest_fields.exs + Adds quest_player_id (bigint FK) and quest_instance_id (binary_id FK) to world_objects. Both nullable. Index on quest_instance_id. Check constraint (quest_player_id IS NULL) = (quest_instance_id IS NULL).
│           └── <ts3>_extend_npc_blueprints_with_quests.exs    + Adds quests (jsonb NOT NULL DEFAULT '[]') to npc_blueprints.
├── assets/
│   └── css/
│       └── game.css                                             M  Add styling for the quest_modal tab strip (.quest-tab, .quest-tab--active) and for completed-quest visual marker (.quest-item--completed) per FR-026. Reuse existing CSS variables.
├── config/                                                       # (no changes)
└── test/
    ├── agenticrealms/
    │   ├── world/
    │   │   ├── quest_test.exs                                 + Quest aggregate execute/2 + apply/2 round-trip for the full state machine.
    │   │   ├── commands_quest_test.exs                        + Command-wrapper tests for accept_quest/3, check_progress/2, finalize_quest/2 covering every refusal path.
    │   │   ├── quests_test.exs                                + Quests.active_for/1, history_for/1, progress_for/1 against fixtures.
    │   │   ├── queries_quest_filter_test.exs                  + list_objects_in_room_for_viewer/2 + resolve_object_in_room/2 viewer-filter behavior.
    │   │   ├── projections/
    │   │   │   ├── world_projector_quest_test.exs             + QuestAccepted projection: row inserted, spawn objects materialized via PlaceObject dispatch; NPCBlueprintCreated extended (quests projected).
    │   │   │   └── quest_projector_test.exs                   + QuestItemsConsumed / QuestRewardMinted / QuestCompleted / QuestItemsCleanedUp projection handlers. Idempotent replay.
    │   │   ├── npc_chat/
    │   │   │   ├── tools_quest_test.exs                       + Each of the 3 tools registered; result envelope is {ok: bool, ...}.
    │   │   │   ├── context_quest_test.exs                     + Per-(viewer, NPC) summary includes catalog + active instances with progress + completed slugs.
    │   │   │   └── conversation_quest_test.exs                + handle_tool_call routes the three tools to the Commands wrappers; structured failure flows back to the LLM.
    │   │   └── seed_quest_test.exs                            + Seeded Orchard Keeper has the FetchQuest in catalog; spawn rooms exist; reward shape is correct.
    │   └── ui_event_broadcaster_quest_test.exs                + QuestAccepted / QuestCompleted broadcasts; ObjectTakenFromRoom / ObjectDroppedInRoom broadcasts include PlayerQuestProgress when an active criterion is affected.
    └── agenticrealms_web/
        └── live/
            ├── game_live_quest_test.exs                       + Integration test (`@moduletag :integration`). End-to-end orchard-keeper walkthrough: mount → accept (via mocked tool call) → walk → take apples → progress advances → return → finalize → reward in inventory → Completed tab populated.
            ├── game_live_quest_multiplayer_test.exs           + Multi-player isolation: two players accept same quest → each sees their own apples → take/drop on player A doesn't affect player B.
            └── game_live_quest_restart_test.exs               + Restart recovery test (SC-006): active quest at 2/3 → stop & restart Commanded → assert state preserved.
```

**Structure Decision**: A new `lib/agenticrealms/world/quest.ex` aggregate sits at the world top level (peer to `room.ex`, `region.ex`, `npc_blueprint.ex`, `player.ex`). A new `lib/agenticrealms/world/quests.ex` higher-level reader sits next to `queries.ex` and `map_view.ex` — it's a read-model query module focused on quest progress. A new `lib/agenticrealms/world/projections/quest_projector.ex` sits next to the existing projectors. NPCChat tool extensions stay inside the existing `lib/agenticrealms/world/npc_chat/` namespace. UI work is confined to `game_components.ex` (HUD card rows + modal tab strip), `game_live.ex` (handle_info for the three new UI events + assigns flip from `GameData` to `Quests` reads), and a small set of CSS additions. The Application supervision tree gains one new child: the `World.Projections.QuestProjector` is added to the `commanded_children/0` list right after the existing projectors.

## Complexity Tracking

No constitution gates violated. No complexity items to track.
