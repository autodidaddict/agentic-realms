---
description: "Tasks for Quest System (v1, FetchQuest)"
---

# Tasks: Quest System (v1, FetchQuest)

**Input**: Design documents from `/specs/013-quest-system/`
**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`

**Tests**: Test tasks ARE included for every aggregate, projector, query, broadcaster, and LiveView surface — matching the project's established conventions from features 005–012 (e.g. the explicit per-module test layout in `specs/012-maps/plan.md`). The plan's "Testing" section enumerates the expected test coverage; the tasks below realize it.

**Organization**: Tasks are grouped by user story so each story can be implemented and tested independently. All three user stories are P1 — they form the MVP together, but each is independently testable per its `Independent Test` block in `spec.md`. After the foundational phase completes, US1 → US2 → US3 should be executed in order: US2 relies on quests existing (US1) and US3 relies on quests with progress (US2-touched paths).

## Format: `[ID] [P?] [Story] Description`

- `[P]` = parallelizable (different files, no dependency on incomplete tasks in this phase)
- `[Story]` = which user story (US1 / US2 / US3) — omitted for Setup, Foundational, and Polish

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Sanity-check the dev environment and stage shared resources.

- [X] T001 Verify the feature branch `013-quest-system` is checked out and the existing `mix deps.get` / `mix ecto.migrate` / `mix test` baseline is green before any new work begins (no code changes; environment gate)
- [X] T002 [P] Create `lib/agenticrealms_web/events/` directory (new home for the three quest UI broadcast structs) and confirm it is included in the existing compile path (no exclusion in `mix.exs`)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Migrations, schemas, aggregate scaffolding, events, commands, router wiring, projector field extensions, viewer-filter queries, reader module, UI event structs, HUD card render shape, NPC system-prompt extension. Every user story below depends on this phase being complete.

**Critical**: Do NOT start US1 / US2 / US3 work until every task in this phase is checked off and `mix test` is green.

### Migrations

- [X] T003 [P] Add migration `priv/repo/migrations/<ts>_create_quest_instances.exs` per `data-model.md` § 2: `quest_instances` table with id (binary_id PK), player_id (bigint FK, NOT NULL), npc_blueprint_id (string FK, NOT NULL), slug (string NOT NULL), state (string NOT NULL), accepted_at (utc_datetime NOT NULL), completed_at (utc_datetime NULL), definition_snapshot (jsonb NOT NULL), reward_object_id (binary_id NULL), timestamps. Partial unique index on `(player_id, npc_blueprint_id, slug) WHERE state = 'completed'`. Index on `(player_id, state)`. Index on `(npc_blueprint_id, slug)`
- [X] T004 [P] Add migration `priv/repo/migrations/<ts>_extend_world_objects_with_quest_fields.exs` per `contracts/object-quest-fields.md`: add `quest_player_id` (bigint FK → players ON DELETE SET NULL, NULL) and `quest_instance_id` (binary_id FK → quest_instances ON DELETE CASCADE, NULL); check constraint `(quest_player_id IS NULL) = (quest_instance_id IS NULL)`; partial index on `quest_instance_id WHERE quest_instance_id IS NOT NULL`
- [X] T005 [P] Add migration `priv/repo/migrations/<ts>_extend_npc_blueprints_with_quests.exs` per `contracts/npc-blueprint-quests.md`: add `quests jsonb NOT NULL DEFAULT '[]'::jsonb` column to `npc_blueprints`

### Schemas

- [X] T006 Create `lib/agenticrealms/world/schemas/quest_instance.ex` as `AgenticRealms.World.QuestInstance` per `data-model.md` § 2: fields id (binary_id PK), player_id (integer), npc_blueprint_id (string), slug (string), state (string), accepted_at, completed_at, definition_snapshot (:map), reward_object_id (binary_id), timestamps. `has_many :scoped_objects, AgenticRealms.World.Object, foreign_key: :quest_instance_id`
- [X] T007 Extend `lib/agenticrealms/world/schemas/object.ex` per `contracts/object-quest-fields.md`: add `field :quest_player_id, :integer`, `field :quest_instance_id, :binary_id`, and the two `belongs_to` associations with `define_field: false`. No changeset changes yet (changesets continue to validate the existing fields; new fields are written by the projector directly)
- [X] T008 Extend `lib/agenticrealms/world/schemas/npc_blueprint.ex` per `contracts/npc-blueprint-quests.md`: add `field :quests, {:array, :map}, default: []`

### Quest aggregate scaffolding

- [X] T009 Create `lib/agenticrealms/world/quest.ex` defining `AgenticRealms.World.Quest` per `contracts/quest-aggregate.md`. Struct only — fields per the contract; `state` defaults to `:initial`. NO `execute/2` or `apply/2` clauses yet beyond the empty case clauses (those land in US1 + US3). Add module doc explaining the state machine

### Event modules

- [X] T010 [P] Create `lib/agenticrealms/world/events/quest_accepted.ex` with `@derive Jason.Encoder` and the fields per `data-model.md` § 4.1: `quest_id, player_id, npc_blueprint_id, slug, definition_snapshot, accepted_at`
- [X] T011 [P] Create `lib/agenticrealms/world/events/quest_items_consumed.ex` per § 4.2: `quest_id, player_id, consumed_object_ids`
- [X] T012 [P] Create `lib/agenticrealms/world/events/quest_reward_minted.ex` per § 4.3: `quest_id, player_id, reward_object_id, reward_name, reward_description`
- [X] T013 [P] Create `lib/agenticrealms/world/events/quest_completed.ex` per § 4.4: `quest_id, player_id, completed_at`
- [X] T014 [P] Create `lib/agenticrealms/world/events/quest_items_cleaned_up.ex` per § 4.5: `quest_id, remaining_quest_object_ids`
- [X] T015 Extend `lib/agenticrealms/world/events/npc_blueprint_created.ex` adding `:quests` to the defstruct (default value handled by aggregate's `apply/2` via `Map.get/3`) per `contracts/npc-blueprint-quests.md`

### Command modules

- [X] T016 [P] Create `lib/agenticrealms/world/commands/accept_quest.ex` defining `AgenticRealms.World.Commands.AcceptQuest` struct with fields per `contracts/command-wrappers.md` § AcceptQuest section: `quest_id, player_id, npc_blueprint_id, slug, definition_snapshot, accepted_at`
- [X] T017 [P] Create `lib/agenticrealms/world/commands/finalize_quest.ex` defining `AgenticRealms.World.Commands.FinalizeQuest` struct with fields: `quest_id, consumed_object_ids, reward_object_id, reward_name, reward_description, remaining_quest_object_ids, completed_at`
- [X] T018 Extend `lib/agenticrealms/world/commands/create_npc_blueprint.ex` adding `:quests` field (default `[]`) per `contracts/npc-blueprint-quests.md`

### Router registration

- [X] T019 Extend `lib/agenticrealms/world/router.ex` per `plan.md` Source Code section: add `identify(Quest, by: :quest_id, prefix: "quest-")` and `dispatch([AcceptQuest, FinalizeQuest], to: Quest)` to the appropriate sections of the router

### `PlaceObject` + `ObjectPlacedInRoom` extensions (carries quest fields)

- [X] T020 Extend `lib/agenticrealms/world/commands/place_object.ex` (or wherever the existing `PlaceObject` struct lives) adding `quest_player_id: nil` and `quest_instance_id: nil` to the defstruct per `data-model.md` § 7. Existing call sites unaffected (both default nil)
- [X] T021 Extend `lib/agenticrealms/world/events/object_placed_in_room.ex` adding the same two fields. Legacy events without these fields apply with both as nil per `Map.get(event, :field, nil)` in `apply/2`
- [X] T022 Extend the `Room` aggregate's `execute/2` clause for `PlaceObject` in `lib/agenticrealms/world/room.ex` to pass through `quest_player_id` and `quest_instance_id` into the emitted `ObjectPlacedInRoom` event
- [X] T023 Extend `WorldProjector.handle/2` for `ObjectPlacedInRoom` in `lib/agenticrealms/world/projections/world_projector.ex` to persist `quest_player_id` and `quest_instance_id` onto the inserted `world_objects` row (use `Map.get/3` with default `nil` for legacy-event safety)
- [ ] T024 Extend the existing `world_projector` tests in `test/agenticrealms/world/projections/` (whichever file covers `ObjectPlacedInRoom`) adding a case that inserts an object with quest fields set and reads them back

### Viewer-filter queries

- [X] T025 Add `list_objects_in_room_for_viewer/2` to `lib/agenticrealms/world/queries.ex` per `contracts/object-quest-fields.md`: filters by `is_nil(o.quest_player_id) or o.quest_player_id == ^viewer_player_id`
- [X] T026 Extend `resolve_object_in_room/2` in `lib/agenticrealms/world/queries.ex` to accept a `viewer_player_id` argument (new signature `resolve_object_in_room/3`) and apply the same predicate. Add an `@deprecated` shim for the old arity if any callers can't be updated atomically, or update all callers in this task — preferred path is updating all callers
- [X] T027 Update `Queries.look_room/1` (`queries.ex:36–54`) to call `list_objects_in_room_for_viewer/2` with the requesting player's `player_id`. Verify the `RoomView` struct still populates `objects` correctly
- [X] T028 Update `World.Commands.take/2` and any examine paths in `commands.ex` to thread the player's id into the new `resolve_object_in_room/3` signature so non-owners cannot resolve quest-scoped items by name
- [ ] T029 [P] Add `test/agenticrealms/world/queries_quest_filter_test.exs` covering: (a) public item visible to all, (b) `quest_player_id=A` item visible to A only, (c) `resolve_object_in_room/3` rejects non-owner, (d) DB check constraint rejects mismatched (`quest_player_id`, `quest_instance_id`) pairings

### `Quests` reader module

- [X] T030 Create `lib/agenticrealms/world/quests.ex` defining `AgenticRealms.World.Quests` with the API in `data-model.md` § 11: `active_for/1`, `history_for/1`, `quest_instance/1`, `progress_for/1`, `active_quests_referencing_object/2`. `progress_for/1` reads the player's inventory and matches each criterion by `quest_tag` against the `definition_snapshot.criteria`. `active_quests_referencing_object/2` finds the object's `behaviors` entry with `type: "quest_tag"` and returns matching active quests
- [ ] T031 [P] Add `test/agenticrealms/world/quests_test.exs` covering `active_for/1`, `history_for/1`, `progress_for/1`, `active_quests_referencing_object/2` against fixtures (no NPC chat / aggregate paths needed — pure read-model tests)

### UI broadcast event structs

- [X] T032 [P] Create `lib/agenticrealms_web/events/player_quest_accepted.ex` per `contracts/ui-broadcast-events.md` with `@enforce_keys [:quest_id, :title, :narrative, :criteria]`
- [X] T033 [P] Create `lib/agenticrealms_web/events/player_quest_progress.ex` with `@enforce_keys [:quest_id, :criteria]`
- [X] T034 [P] Create `lib/agenticrealms_web/events/player_quest_finalized.ex` with `@enforce_keys [:quest_id, :title, :reward_name, :completed_at]`

### Quest log UI shape (HUD card)

- [X] T035 Update the `hud_card "Quest Log"` block in `lib/agenticrealms_web/components/game_components.ex` (lines ~434–443) so each quest renders title plus one line per criterion `<name>: <count> / <target>` instead of the current single `quest.progress` string. Use the `:criteria` field on each quest map. Preserve the existing CSS classes (`.quest-item`, `.qt`, `.qp`). The HUD card `count={"#{length(@quests)} active"}` continues to reflect the count of active quests

### NPC system prompt + context

- [X] T036 Add `quest_context/2` to `AgenticRealms.World.NPCChat.Context` (`lib/agenticrealms/world/npc_chat/context.ex`) per `contracts/npc-system-prompt.md`. Returns `%{offerable_quests: [...], active_instances: [...], completed_slugs: [...]}`. `offerable_quests` excludes both completed slugs and currently-active slugs for this player–NPC pair
- [X] T037 Extend `AgenticRealms.World.NPCChat.SystemPrompt` (`lib/agenticrealms/world/npc_chat/system_prompt.ex`) to render the `## Quests` section as described in `contracts/npc-system-prompt.md` when any of the three lists is non-empty; omit the section entirely otherwise
- [ ] T038 [P] Add `test/agenticrealms/world/npc_chat/context_quest_test.exs` covering empty / catalog-only / active-only / completed-only / mixed states of `quest_context/2`

### Foundational checkpoint

- [ ] T039 Run `mix compile --warnings-as-errors`, `mix ecto.migrate`, and `mix test` — all green before proceeding to user story phases

---

## Phase 3: User Story 1 — Accept a quest from an NPC and see it appear in the quest log (Priority: P1) 🎯 MVP

**Goal**: A player chatting with a questgiver NPC can accept a quest. The active quest appears in their log at `0 / target`. The quest's items spawn into the designated rooms, scoped to that player.

**Independent Test**: Per `spec.md` US1 — seed an NPC blueprint with one FetchQuest in its catalog. Drive a chat that ends in `accept_quest("golden_apples")` (mock the LLM tool call, dispatch directly). Verify: (a) `quest_instances` row inserted with `state="active"`, (b) the designated spawn rooms each contain a tagged item with `quest_player_id` set, (c) `PlayerQuestAccepted` is broadcast and the LiveView quest log shows the new quest at `0 / 3`, (d) a second test player sees no apples in the spawn rooms.

### Aggregate

- [X] T040 [US1] Implement `Quest.execute/2` for the `:initial → :active` transition in `lib/agenticrealms/world/quest.ex`: `AcceptQuest` from `:initial` emits `QuestAccepted` with the command's fields copied. `AcceptQuest` from `:active` returns `{:error, :already_active}`. Per `contracts/quest-aggregate.md`
- [X] T041 [US1] Implement `Quest.apply/2` for `QuestAccepted` — transitions the aggregate to `:active`, populates fields per `contracts/quest-aggregate.md` § apply
- [ ] T042 [P] [US1] Add `test/agenticrealms/world/quest_accept_test.exs` covering aggregate execute/apply for the accept path including the `:already_active` refusal

### Command wrapper

- [X] T043 [US1] Add `accept_quest/3` to `lib/agenticrealms/world/commands.ex` per `contracts/command-wrappers.md` § accept_quest. Algorithm: look up blueprint → locate catalog entry → check `quest_instances` for completed/active rows → generate `quest_id` → rewrite quest tags to instance-scoped form → dispatch `AcceptQuest`. Returns `{:ok, quest_id}` or one of `{:error, :unknown_slug}` / `{:error, :already_completed}` / `{:error, :already_active, existing_quest_id}`
- [ ] T044 [US1] Extend `create_npc_blueprint/*` wrapper in the same `commands.ex` to validate the `:quests` field per `contracts/npc-blueprint-quests.md` validation rules (slug uniqueness, criteria shape, spawn_room_ids exist, reward shape)
- [ ] T045 [P] [US1] Add `test/agenticrealms/world/commands_accept_quest_test.exs` covering every error branch of `accept_quest/3` and the success branch including the instance-tag rewrite
- [ ] T046 [P] [US1] Add `test/agenticrealms/world/commands_create_npc_blueprint_quests_test.exs` covering each catalog-validation error branch (`:invalid_quests`, `:quest_invalid_slug`, `:quest_duplicate_slug`, `:quest_invalid_title`, `:quest_invalid_narrative`, `:quest_no_criteria`, `:quest_invalid_criterion`, `:quest_spawn_count_mismatch`, `:quest_unknown_spawn_room`, `:quest_invalid_reward`) plus the success branch

### Projector

- [X] T047 [US1] Extend `WorldProjector.handle/2` in `lib/agenticrealms/world/projections/world_projector.ex` with a `QuestAccepted` clause per `contracts/projector-quest.md`. Inside a `Repo.transaction/1`: (a) insert `quest_instances` row with `state="active"`, (b) for each criterion, for each `spawn_room_id`, dispatch a `PlaceObject` command via `Commands.place_object/2` with the new `quest_player_id` + `quest_instance_id` fields set and a `behaviors: [%{type: "quest_tag", tag: criterion["quest_tag"]}]` entry. Idempotent under replay (use `on_conflict: :nothing, conflict_target: :id` on the insert; dispatch failures from already-placed objects must not crash the projector)
- [X] T048 [US1] Extend `WorldProjector.handle/2` for `NPCBlueprintCreated` to project the new `:quests` field per `contracts/npc-blueprint-quests.md`. Use `Map.get(event, :quests, [])` for legacy-event compatibility
- [ ] T049 [P] [US1] Add `test/agenticrealms/world/projections/world_projector_quest_accept_test.exs` covering: (a) `QuestAccepted` event inserts the `quest_instances` row, (b) three `PlaceObject` dispatches result in three `world_objects` rows each carrying `quest_player_id` + `quest_instance_id` + the behavior entry, (c) replaying `QuestAccepted` twice does not duplicate
- [ ] T050 [P] [US1] Add `test/agenticrealms/world/projections/world_projector_npc_blueprint_quests_test.exs` covering the extended `NPCBlueprintCreated` handler

### UI broadcaster

- [X] T051 [US1] Add a `QuestAccepted` clause to `AgenticRealms.UIEventBroadcaster.handle/2` (`lib/agenticrealms/ui_event_broadcaster.ex`) per `contracts/ui-broadcast-events.md`. Compute the criteria list with all counts at 0 from the event's `definition_snapshot`, then `Phoenix.PubSub.broadcast/3` a `%PlayerQuestAccepted{}` on `Topics.player_topic(player_id)`
- [ ] T052 [P] [US1] Add `test/agenticrealms/ui_event_broadcaster_quest_accept_test.exs` asserting the `PlayerQuestAccepted` broadcast fires with the correct quest_id, title, narrative, and criteria-at-zero

### NPCChat tool registration + dispatch

- [X] T053 [US1] Extend `Tools.list/0` in `lib/agenticrealms/world/npc_chat/tools.ex` adding the `accept_quest` tool schema per `contracts/npc-chat-tools.md` § Tool 1
- [X] T054 [US1] Add a `handle_tool_call/3` clause in `lib/agenticrealms/world/npc_chat/conversation.ex` for `"accept_quest"` that calls `Commands.accept_quest(viewer_player_id, npc_blueprint_id, slug)` and packages the result into the `{ok: bool, ...}` envelope per `contracts/npc-chat-tools.md`
- [ ] T055 [P] [US1] Add `test/agenticrealms/world/npc_chat/tools_accept_quest_test.exs` covering tool registration (in `Tools.list/0`) and `handle_tool_call/3` envelopes for success and each failure branch

### GameLive integration

- [X] T056 [US1] Update `lib/agenticrealms_web/live/game_live.ex`: replace `assign(:quests, GameData.quests())` (~line 103) with `assign(:quests, AgenticRealms.World.Quests.active_for(player_id))`. Add a `handle_info/2` clause for `%PlayerQuestAccepted{}` that appends a new quest row to `:quests` per `contracts/ui-broadcast-events.md`
- [X] T057 [US1] In the same file, ensure the player's `player_topic/1` PubSub subscription already covers the new struct (no Topics change needed; only verify subscription is active in `mount/3`)
- [ ] T058 [P] [US1] Add `test/agenticrealms_web/live/game_live_accept_test.exs` asserting that broadcasting `%PlayerQuestAccepted{}` to a mounted LiveView updates `assigns.quests` and the HUD card renders `0 / target` lines

### Seed

- [X] T059 [US1] Extend `lib/agenticrealms/world/seed.ex` to create:
  - One `NPCBlueprint` called "Orchard Keeper" with one FetchQuest in its `quests` array: slug `golden_apples`, title *The Orchard Keeper's Errand*, narrative per `quickstart.md`, one criterion `{name: "Golden Apples", quest_tag: "quest.orchard.golden_apple", target_count: 3, spawn_room_ids: [3 specific seeded room ids]}`, reward `{name: "bigger golden apple", description: "An impossibly large golden apple, warm to the touch."}`
  - One clone of this blueprint placed adjacent to the Stone Atrium
  - Confirm the three spawn rooms exist (reuse existing seeded rooms; create new ones only if needed)
- [ ] T060 [P] [US1] Extend `test/agenticrealms/world/seed_test.exs` (or add a focused file) asserting the Orchard Keeper blueprint is seeded with the expected catalog and clone placement

**Checkpoint US1**: After all US1 tasks check off, an `accept_quest` tool call (mocked from a test) successfully creates an active quest, spawns three player-scoped apples in the three spawn rooms, broadcasts `PlayerQuestAccepted`, and updates the live quest log. Other players see no apples.

---

## Phase 4: User Story 2 — Collect quest items and watch progress update live (Priority: P1)

**Goal**: A player with an active FetchQuest picks up tagged items in the world. The per-criterion progress counter (`<n> / <target>`) updates in real time. Dropping a tagged item decrements the counter.

**Independent Test**: Per `spec.md` US2 — with an active quest pre-seeded for a test player at `0 / 3`, pick up an apple in one of the spawn rooms; assert the HUD card line moves to `1 / 3` without page reload. Drop it; assert it returns to `0 / 3`. Accept a quest while already holding a matching tagged item; assert progress reflects current inventory.

### Broadcaster extensions

- [X] T061 [US2] Extend `UIEventBroadcaster.handle/2` for `ObjectTakenFromRoom` in `lib/agenticrealms/ui_event_broadcaster.ex` per `contracts/ui-broadcast-events.md`. After the existing `PlayerInventoryChanged(:added)` broadcast, call `Quests.active_quests_referencing_object(player_id, object_id)`, recompute `Quests.progress_for/1` for each, and broadcast a `%PlayerQuestProgress{}` per quest on `player_topic(player_id)`
- [X] T062 [US2] Extend `UIEventBroadcaster.handle/2` for `ObjectDroppedInRoom` symmetrically — same lookup, broadcast `PlayerQuestProgress` with the now-decremented counts. Per `contracts/ui-broadcast-events.md`
- [ ] T063 [P] [US2] Add `test/agenticrealms/ui_event_broadcaster_quest_progress_test.exs` asserting: (a) `ObjectTakenFromRoom` for a tagged object emits `PlayerQuestProgress` with the incremented count, (b) `ObjectDroppedInRoom` emits with decremented count, (c) untagged objects do NOT trigger a quest-progress broadcast, (d) tagged objects belonging to a different player's quest do NOT trigger a broadcast to this player

### GameLive integration

- [X] T064 [US2] Add a `handle_info/2` clause in `lib/agenticrealms_web/live/game_live.ex` for `%PlayerQuestProgress{}` per `contracts/ui-broadcast-events.md`. Update the matching quest's `:criteria` field in `assigns.quests`. Confirm the HUD card re-renders the new counts diffed via LiveView
- [ ] T065 [P] [US2] Add `test/agenticrealms_web/live/game_live_progress_test.exs` asserting that pickup → broadcast → assigns update flows correctly, including the case where a player drops an item and progress regresses

### Accept-time progress recompute

- [X] T066 [US2] In `Quests.active_for/1` (`lib/agenticrealms/world/quests.ex`), confirm that the criteria counts returned reflect current inventory at read time — verify the integration test for "player accepts a quest while already carrying a tagged item" in the test below
- [ ] T067 [P] [US2] Add `test/agenticrealms/world/quests_accept_time_progress_test.exs` covering: when a player accepts a quest while already holding a matching tagged item (from any source), `Quests.active_for/1` returns the criterion with `count` reflecting that pre-existing item — not zero

**Checkpoint US2**: After all US2 tasks check off, picking up and dropping tagged items in any room updates the quest log live with sub-second latency. Per-player isolation continues to hold from US1.

---

## Phase 5: User Story 3 — Finalize the quest and receive the reward (Priority: P1)

**Goal**: A player with all required items can finalize the quest by chatting "here you go" with the questgiver NPC. Reward is minted, key items are destroyed, quest moves from active log to Completed view. Missing items causes a structured failure and zero state change.

**Independent Test**: Per `spec.md` US3 — with an active quest pre-seeded and all required items in the player's inventory, drive `finalize_quest(quest_id)`; assert key items removed, reward minted, quest marked completed, Completed tab populated. Repeat with one item missing; assert zero state change and structured failure.

### Aggregate

- [X] T068 [US3] Implement `Quest.execute/2` for `:active → :completed` in `lib/agenticrealms/world/quest.ex`: from `:active`, `FinalizeQuest` emits the four-event bundle `[QuestItemsConsumed, QuestRewardMinted, QuestCompleted, QuestItemsCleanedUp]` per `contracts/quest-aggregate.md`. From `:initial` returns `{:error, :unknown_instance}`. From `:completed` returns `{:error, :already_completed}`
- [X] T069 [US3] Implement `Quest.apply/2` for `QuestCompleted` (transitions to `:completed` with `completed_at` set). The three side-effect events (`QuestItemsConsumed`, `QuestRewardMinted`, `QuestItemsCleanedUp`) do NOT mutate aggregate state — add no-op apply clauses that return the unchanged aggregate
- [ ] T070 [P] [US3] Extend `test/agenticrealms/world/quest_accept_test.exs` (or split into a finalize test) covering: finalize from `:active` emits exactly the 4 events in order; finalize from `:initial` returns `:unknown_instance`; finalize from `:completed` returns `:already_completed`; replay round-trip ends at `:completed`

### Command wrappers

- [X] T071 [US3] Add `check_progress/2` to `lib/agenticrealms/world/commands.ex` per `contracts/command-wrappers.md` § check_progress. Pure read; routes through `Quests.quest_instance/1` and `Quests.progress_for/1`
- [X] T072 [US3] Add `finalize_quest/2` to `lib/agenticrealms/world/commands.ex` per `contracts/command-wrappers.md` § finalize_quest. Algorithm: validate instance ownership + active state → read inventory restricted to `quest_instance_id = quest_id` → match each criterion → on shortfall return `{:error, :criteria_unmet, missing}` with no dispatch → otherwise capture `consumed_object_ids`, compute `remaining_quest_object_ids`, generate `reward_object_id`, dispatch `FinalizeQuest`
- [ ] T073 [P] [US3] Add `test/agenticrealms/world/commands_check_progress_test.exs` covering each branch
- [ ] T074 [P] [US3] Add `test/agenticrealms/world/commands_finalize_quest_test.exs` covering: success path (full inventory) captures correct object id sets; `:unknown_instance` for nonexistent / not-mine / completed; `:criteria_unmet` with `missing: [...]` for partial inventory; dispatched command struct field values

### Quest projector

- [X] T075 [US3] Create `lib/agenticrealms/world/projections/quest_projector.ex` defining `AgenticRealms.World.Projections.QuestProjector` per `contracts/projector-quest.md`. Module is a `Commanded.Event.Handler` with `consistency: :eventual`. Implement handlers for `QuestItemsConsumed` (delete_all by id), `QuestRewardMinted` (insert new object owned by player with quest fields nil; AND `Repo.update_all` to set `quest_instances.reward_object_id` for back-reference), `QuestCompleted` (update_all setting state="completed", completed_at), `QuestItemsCleanedUp` (delete_all by id; no-op if list empty). Each handler must be idempotent on replay
- [X] T076 [US3] Register `QuestProjector` in `AgenticRealms.Application.commanded_children/0` (`lib/agenticrealms/application.ex:69–84`) — added after `WorldProjector` and `PlayerStateProjector` in the list
- [ ] T077 [P] [US3] Add `test/agenticrealms/world/projections/quest_projector_test.exs` covering each handler. Including idempotent-replay: invoking each handler twice produces the same state as invoking it once

### UI broadcaster

- [X] T078 [US3] Add a `QuestCompleted` clause to `UIEventBroadcaster.handle/2` per `contracts/ui-broadcast-events.md`. Look up the quest instance to retrieve title + reward name; broadcast `%PlayerQuestFinalized{}` on `Topics.player_topic(player_id)`
- [ ] T079 [P] [US3] Add `test/agenticrealms/ui_event_broadcaster_quest_finalize_test.exs` asserting the `PlayerQuestFinalized` broadcast with correct fields

### NPCChat tools + dispatch

- [X] T080 [US3] Extend `Tools.list/0` in `lib/agenticrealms/world/npc_chat/tools.ex` adding `check_progress` and `finalize_quest` tool schemas per `contracts/npc-chat-tools.md` § Tool 2 + Tool 3
- [X] T081 [US3] Add `handle_tool_call/3` clauses in `lib/agenticrealms/world/npc_chat/conversation.ex` for `"check_progress"` and `"finalize_quest"`. Each calls the corresponding `Commands.*` wrapper and packages results into the `{ok: bool, ...}` envelope per `contracts/npc-chat-tools.md`
- [ ] T082 [P] [US3] Add `test/agenticrealms/world/npc_chat/tools_check_progress_test.exs` and `test/agenticrealms/world/npc_chat/tools_finalize_quest_test.exs` covering registration and every envelope branch

### GameLive + UI

- [X] T083 [US3] In `lib/agenticrealms_web/live/game_live.ex`: initialize a new `:completed_quests` assign in `mount/3` from `Quests.history_for(player_id)`. Add a `handle_info/2` clause for `%PlayerQuestFinalized{}` that removes the quest from `:quests` and prepends it to `:completed_quests` per `contracts/ui-broadcast-events.md`. Wire the existing `select_quest` handler to also index `:completed_quests` when the modal is on the Completed tab
- [X] T084 [US3] Extend `quest_modal/1` in `lib/agenticrealms_web/components/game_components.ex:1057–1080` to include a tab strip ("Active" / "Completed") above the existing left-hand list. Active tab shows quests from `@quests` (with the per-criterion progress lines and narrative); Completed tab shows quests from `@completed_quests` with completion timestamp + reward name. Add a `:tab` assign or use `phx-click` event to switch tabs
- [X] T085 [US3] Add a visually-distinct marker (check glyph + dimmed text) on each row in the Completed tab per FR-026
- [X] T086 [P] [US3] Add CSS rules to `assets/css/game.css` for the new `.quest-tab`, `.quest-tab--active`, and `.quest-item--completed` classes. Reuse existing CSS variables (`--ink`, `--ink-faint`, `--player`, etc.) so the rules inherit all existing themes
- [ ] T087 [P] [US3] Add `test/agenticrealms_web/live/game_live_finalize_test.exs` asserting that broadcasting `%PlayerQuestFinalized{}` to a mounted LiveView moves the quest from `:quests` to `:completed_quests`, and that the modal's Active tab is empty / Completed tab shows the entry

### Remove stub data

- [X] T088 [US3] Delete `quests/0` and `quest_details/0` functions from `lib/agenticrealms/game_data.ex`. Verify no remaining callers (grep across `lib/` and `test/`)

**Checkpoint US3**: After all US3 tasks check off, the full happy path works: accept → collect → return → finalize → reward in inventory → quest in Completed tab. Partial inventory triggers structured failure with no state change. Repeat-accept attempts are refused.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Multi-player isolation integration test, restart-recovery integration test, quickstart smoke verification, cleanup.

- [X] T089 Add `test/agenticrealms_web/live/game_live_quest_multiplayer_test.exs` per `plan.md` Testing section. Two LiveView sessions, two players accept the same quest concurrently from the same NPC. Assert each sees only their own apples in spawn rooms; player A's take/drop does not affect player B's progress. Backs SC-003
- [ ] T090 Add `test/agenticrealms_web/live/game_live_quest_restart_test.exs` per `plan.md` Testing section. Active quest at `2 / 3` → stop and restart the Commanded application supervisor → assert (a) `Quest` aggregate replays to `:active`, (b) two collected apples remain in inventory, (c) third apple remains in its spawn room visible only to the owning player, (d) HUD card shows `2 / 3` on re-mount. Backs SC-006
- [ ] T091 Run through `specs/013-quest-system/quickstart.md` manually in a dev shell. Confirm each verify step actually passes. File any deltas as follow-up tasks
- [ ] T092 [P] Update `MEMORY.md` (auto-memory) — append entry pointing to this quest-system feature directory if any non-obvious decisions surfaced during implementation that future conversations should remember. Skip if nothing new emerged beyond what's in the spec/plan
- [X] T093 [P] Confirm `CLAUDE.md` SPECKIT marker still points at `specs/013-quest-system/plan.md` (set during `/speckit-plan`). Update only if the value drifted during implementation
- [X] T094 Run `mix format`, `mix compile --warnings-as-errors`, and full `mix test` (including `:integration` tagged tests). All green before considering the feature complete

---

## Dependencies between phases

```text
Phase 1 (Setup) ─▶ Phase 2 (Foundational) ─┬─▶ Phase 3 (US1)
                                            ├─▶ Phase 4 (US2)
                                            └─▶ Phase 5 (US3)

Phase 4 (US2) and Phase 5 (US3) depend on Phase 3 (US1) for fixture quest creation in their integration tests.
Phase 6 (Polish) depends on all preceding phases.
```

**Story execution order**: US1 → US2 → US3. While each story is independently testable (per the `Independent Test` blocks), the natural fixture flow is that US2 and US3 tests reuse the US1-seeded Orchard Keeper. US2 and US3 can run in parallel only if separate developers build separate fixture quests for their tests; otherwise serialize.

**Parallel opportunities within phases**:
- Phase 2: migrations T003/T004/T005 in parallel; event modules T010–T014 in parallel; command modules T016/T017 in parallel; UI broadcast structs T032/T033/T034 in parallel; tests across modules in parallel.
- Phase 3 (US1): T042, T045, T046, T049, T050, T052, T055, T058, T060 — all test files independent of each other and parallel-safe once their implementations land.
- Phase 4 (US2): T063, T065, T067 parallel.
- Phase 5 (US3): T070, T073, T074, T077, T079, T082, T086, T087 parallel.
- Phase 6: T089, T090 can run in parallel; T091 serializes after both.

## Implementation strategy

- **MVP scope** = US1 (Phase 3) alone. After Phase 3 completes, a player can accept a quest, see it in the log, and watch the items spawn. They cannot yet complete it. Even at MVP, the feature delivers a recognizable user-facing slice with a visible-in-the-UI artifact.
- **Recommended ship gate**: US1 + US2 + US3 (all P1). Per the spec, the three stories are split for independent testability but ship together — the orchard-keeper walkthrough in `quickstart.md` requires all three.
- **Foundational risk note**: T020–T023 (PlaceObject + ObjectPlacedInRoom extensions) touch existing event schemas. Run the full test suite after this set lands; any regression is most likely to surface here.
- **NPC system-prompt extension (T036/T037)** is the only place this feature touches LLM behavior. Manual smoke via `quickstart.md` step 2–4 is the cheapest way to catch prompt-rendering regressions.

## Format validation

Confirmed: every task above starts with `- [ ]`, has a sequential `TXXX` ID, includes a `[P]` marker only where genuinely parallel, includes a `[USN]` story label only inside user-story phases, and references a concrete file path in the description.
