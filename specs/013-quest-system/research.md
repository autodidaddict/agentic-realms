# Phase 0 Research: Quest System (v1, FetchQuest)

The spec was fully clarified in two interactive rounds before planning. Every `NEEDS CLARIFICATION` was either resolved in conversation (10+ design exchanges) or eliminated by the two formal clarifications captured in `spec.md > Clarifications`. As a result, there are no open spec-level questions feeding into research.

What this document captures instead is the **design decisions** the plan rests on — the ones that have non-trivial alternatives, the ones that compose with existing project conventions in non-obvious ways, and the ones where another implementer might pick a different path without this record.

## D-1: Quest as its own aggregate, not as state on Player

**Decision**: `Quest` is a new aggregate, identified by `quest_id` (`prefix: "quest-"` in the router). One aggregate instance per accepted quest. Lifetime: birth at `QuestAccepted`, terminal at `QuestCompleted`.

**Rationale**:
- Each accepted quest has its own state machine (`:initial → :active → :completed`) and its own list of side-effect events (`QuestItemsConsumed`, `QuestRewardMinted`, `QuestCompleted`, `QuestItemsCleanedUp`). Folding those into the existing `Player` aggregate (`lib/agenticrealms/world/player.ex`) would balloon its event surface and tangle quest concerns with `SpawnPlayer` / `MovePlayer` / `RecordRoomDiscovery`.
- A `Quest` aggregate naturally maps to "one quest instance" — the unit the FR-004 instance-scoped quest tags reference, the unit `quest_instances.id` keys on, and the unit `world_objects.quest_instance_id` foreign-keys to.
- Replay locality: replaying a `Quest`'s events reconstructs only that quest, without scanning all of a player's events. This will scale better as templates accumulate.
- Existing precedent: `Region`, `NPCBlueprint`, and `Room` are all their own aggregates with focused state. Quest fits the same shape.

**Alternatives considered**:
- *Quest state on `Player` aggregate*: Rejected for the reasons above — concern entanglement and bloated Player event stream.
- *Quest state on `NPCBlueprint` aggregate*: Rejected — would couple per-player runtime state to a wizard-authored blueprint, and would force NPC events to fan out to multiple players. The blueprint correctly owns the *catalog* (FR-001), not the per-player *instances*.

## D-2: Sticky one-time completion enforced at two layers (aggregate + DB)

**Decision**: FR-012 (sticky completion per `(player, NPC, quest slug)`) is enforced both by the `accept_quest/3` command wrapper reading `quest_instances` and by a partial unique index on `quest_instances(player_id, npc_blueprint_id, slug) WHERE state = 'completed'`.

**Rationale**:
- The aggregate alone cannot enforce uniqueness across separate `Quest` aggregates — each new `accept_quest` generates a fresh `quest_id`, so there is no aggregate to consult for "did this player ever complete slug X with NPC Y?" The read model is authoritative for that question.
- The command wrapper reads the read model before dispatching, returning the `{ok: false, reason: :already_completed}` structured failure (per the clarification) without dispatching.
- The DB partial unique index is a backstop for the race in edge case "concurrent accept attempts": two parallel `accept_quest` calls could pass pre-dispatch validation if one is mid-flight to the projector when the other reads. The partial unique index causes the second projector insert to violate and surface as a projector error.
- The partial unique index covers only `state = 'completed'`, so two concurrent *active* quests (different slugs, same NPC) coexist fine. The aggregate refuses re-acceptance of an *active* slug via `accept_quest/3`'s read of the same table.

**Alternatives considered**:
- *Aggregate-only enforcement*: Rejected — race-prone (see above) and forces a per-player query inside the aggregate constructor, awkward in Commanded.
- *DB-only enforcement*: Rejected — would surface duplicate accepts as a generic DB error after partial side-effects (e.g., spawn objects already placed), undermining the per-FR-011a structured-failure contract.

## D-3: Finalize atomicity via aggregate-emitted event bundle + pre-dispatch validation

**Decision**: `FinalizeQuest` is preceded by a synchronous read in `Commands.finalize_quest/2` that (a) verifies the quest is active and belongs to the caller, (b) reads the player's current inventory, (c) matches against the criteria snapshot, (d) captures the exact object ids to consume, computes the reward, and the list of remaining quest-scoped objects to clean up. On success it dispatches `FinalizeQuest` carrying that captured plan. The `Quest` aggregate then emits **four events in one execute call**: `QuestItemsConsumed`, `QuestRewardMinted`, `QuestCompleted`, `QuestItemsCleanedUp`. The projector handles them in a single transaction.

**Rationale**:
- True ACID atomicity across the inventory check + state transition + reward mint is impossible without locking; the existing project pattern (e.g. `World.Commands.take/2` in `commands.ex`) uses pre-dispatch read-model validation + aggregate emission as the standard idiom. We follow it.
- Emitting four events from one execute call is supported by Commanded and yields a single projector transaction at apply time. The four events are conceptually one finalize step but split for projection clarity:
  - `QuestItemsConsumed` carries the exact `consumed_object_ids` — making it trivial to project a `DELETE FROM objects WHERE id IN (...)`.
  - `QuestRewardMinted` carries the reward `{name, description}` and a pre-generated `reward_object_id` — projector does `INSERT INTO objects ...`.
  - `QuestCompleted` is the lifecycle marker — projector does `UPDATE quest_instances SET state='completed', completed_at=...`.
  - `QuestItemsCleanedUp` carries `remaining_quest_object_ids` (any quest-scoped items not part of the consumed set — dropped in rooms, carried but not in the consumed set, etc.) — projector does `DELETE FROM objects WHERE id IN (...)`.
- The structured failure path (`{ok: false, reason: :criteria_unmet, missing: [...]}`) returns without dispatching, so a failed finalize is guaranteed to perform zero state changes (per SC-005).

**Alternatives considered**:
- *Single fat `QuestFinalized` event*: Rejected — would force the projector to inspect the event for many subtypes of side effects and make replay logic harder to reason about.
- *Project consumption + mint + cleanup via dispatched commands to a separate aggregate*: Rejected — the side effects all live in the `objects` table; an extra aggregate would not add isolation and would split the finalize transaction across multiple aggregate handlers.
- *Race-window TOCTOU mitigation via DB lock*: Rejected for v1 — the actor model already serializes per-player command dispatch via Commanded's aggregate dispatch on `quest_id` and per-player command serialization upstream is sufficient for the single-user-per-session reality. Multi-device-same-account is an explicit non-concern in v1.

## D-4: Quest items go through the existing `PlaceObject` command on accept, then are owned by `QuestProjector` for cleanup

**Decision**: Spawning quest-scoped items at `accept_quest` time is done by the `WorldProjector` (in its `QuestAccepted` handler) **dispatching `PlaceObject` commands to each spawn `Room` aggregate**, with the new `quest_player_id` + `quest_instance_id` fields carried through. The items then live as first-class room objects, takeable/droppable via the existing `TakeObject` / `DropObject` flows. The only special handling is cleanup: `QuestItemsConsumed` and `QuestItemsCleanedUp` direct-delete objects from the projector. The Room aggregate is not informed of these deletions because (a) they're not initiated by a room-scoped action and (b) the Room aggregate's `exits` map is the only state it owns; the read-model `objects` table is what queries read, and that's what the projector mutates.

**Rationale**:
- Reusing `PlaceObject` gives free integration with all existing room-rendering and item-resolution code paths (`Queries.list_objects_in_room/1`, `Queries.resolve_object_in_room/2`). The quest items appear in rooms exactly like static seeded objects do today.
- The viewer-filter is added at the *query* layer (see D-5), so all existing rendering paths inherit per-player visibility correctly with no changes to room aggregate code.
- Direct deletion on `QuestItemsConsumed` / `QuestItemsCleanedUp` is justified because the quest instance is authoritative over the lifecycle of objects it spawned. Asking the Room aggregate to emit `ObjectRemovedFromRoom` for each consumed apple would (a) require the projector to dispatch one command per object, (b) only work for objects still in their original room (not for ones moved to another room or held in inventory), and (c) introduce a "removed by quest" event variant on Room that would be ignored everywhere except cleanup. Direct projector deletion is the local minimum.
- The existing pattern has precedent: in 012 (`specs/012-maps/plan.md` line 127), the `WorldProjector` is allowed to *dispatch commands as side effects of events*. We follow the same pattern, restricted in scope to spawning quest items at accept time.

**Alternatives considered**:
- *Bypass `PlaceObject` and direct-insert at spawn*: Rejected — would mean quest items skip the canonical room-state event stream; they'd still render correctly, but newcomers reading the codebase would have to learn a parallel "how do quest items get into rooms?" pattern.
- *Have the Quest aggregate emit `ObjectPlacedInRoom`-flavored events directly*: Rejected — would couple Quest aggregate's event vocabulary to Room's event vocabulary, breaking aggregate isolation.

## D-5: Visibility filtering implemented as a SQL WHERE clause in `list_objects_in_room_for_viewer/2`

**Decision**: Add a viewer-aware variant of the existing `Queries.list_objects_in_room/1`:

```elixir
def list_objects_in_room_for_viewer(room_id, viewer_player_id) do
  from(o in Object,
    where: o.room_id == ^room_id,
    where: is_nil(o.quest_player_id) or o.quest_player_id == ^viewer_player_id
  )
  |> Repo.all()
end
```

The same predicate is applied in `Queries.resolve_object_in_room/2` so a non-owner cannot resolve a quest-scoped item's name when issuing a `take` or `examine`. All call sites that render room objects are updated to pass the viewer's `player_id`.

**Rationale**:
- Per-viewer filtering is already an established pattern in the codebase: `Queries.list_other_players/2` filters by online presence on a per-viewer basis. Adding per-viewer SQL filtering for items is a natural, additive extension of that pattern (zero new primitives, no per-row Phoenix.Presence checks).
- The filter pushes down into the index — with the partial check constraint `(quest_player_id IS NULL) = (quest_instance_id IS NULL)`, the `IS NULL OR =` predicate is cheap.
- Inventory rendering does not need this filter at all: an item is in inventory iff `player_id = $viewer`, and inventory is only ever rendered for the owning player. (Other-player inventory inspection is not a feature in v1.)

**Alternatives considered**:
- *Filter in Elixir after `Repo.all/1`*: Rejected — pulls quest-scoped items to the BEAM only to discard them; trivial perf hit but unprincipled.
- *Materialize a per-viewer view*: Rejected — overkill for two conditions in a WHERE clause.

## D-6: Progress is derived from inventory, never stored

**Decision**: Per-criterion progress for an active quest is computed on the fly as `count of items in player_id=P where quest_tag matches criterion`. Stored nowhere. Recomputed on every inventory change and on quest log read.

**Rationale**:
- The clarification settled FR-019 as a pure function of current inventory (no lifetime tracking). Storing progress would mean an extra source of truth that can drift on drops/transfers; we avoid that entirely.
- The recompute cost is trivially small (the quest's criteria list is ≤ a handful of tags; matching items in inventory is an indexed `WHERE quest_tag IN (...) AND player_id = P` query).
- The `UIEventBroadcaster` already sees every `ObjectTakenFromRoom` / `ObjectDroppedInRoom` event with player_id information, so we have a natural per-event hook to recompute + broadcast `PlayerQuestProgress`.

**Alternatives considered**:
- *Store progress on `quest_instances`*: Rejected — drift risk + double-write per pickup.
- *Project a separate `quest_progress` table*: Rejected — same drift risk plus extra rows per criterion.

## D-7: NPC system-prompt context includes catalog + active instances + completed slugs (per-NPC, per-player)

**Decision**: Extend `AgenticRealms.World.NPCChat.Context` to render a quest section into the NPC's system prompt, scoped to the conversation's `(viewer_player_id, npc_blueprint_id)` pair. Section contents:

1. **Offerable quests** — the NPC's full catalog (slug, title, narrative, brief criteria summary) **minus** any slug this player has already completed with this NPC. The LLM is told to mention these conversationally when contextually appropriate.
2. **Active quest instances** — each open `quest_instance` this player has with this NPC: `quest_id`, slug, title, per-criterion progress (`<name>: <n> / <target>`). The LLM uses these to pick the right `quest_id` when it decides to call `check_progress` or `finalize_quest`.
3. **Completed slugs** — bare list of slugs this player has finished with this NPC. The LLM is told that if the player references one, the NPC should react in-character to the prior completion and decline to re-offer.

**Rationale**:
- Per FR-013 / FR-014 the LLM needs these pieces of context to behave correctly. Computing them once per turn from the read model is cheap (`quest_instances` is small and indexed by `(player_id, state)`).
- Excluding completed slugs from the *offerable* list at context-render time means the LLM is much less likely to even consider offering a completed quest, removing whole classes of misbehavior before they happen. (We still defensively refuse at the `accept_quest` wrapper if the LLM does call it.)
- Per-(viewer, NPC) computation keeps the prompt size bounded by per-NPC catalog size, not by world-wide quest counts.

**Alternatives considered**:
- *Computed once at NPC spawn and cached*: Rejected — caches go stale on accept and finalize; the cost of recomputing per turn is negligible.
- *Single global quest context*: Rejected — leaks unrelated NPCs' state into every conversation.

## D-8: Existing quest UI stub is repurposed; HUD card → progress lines, modal → tab strip

**Decision**: The existing `hud_card "Quest Log"` (`game_components.ex:434`) and `quest_modal/1` (`game_components.ex:1057`) are repurposed rather than rebuilt.

- HUD card: each quest renders title + one line per criterion `<name>: <n> / <target>`. The `count={"#{length(@quests)} active"}` chip continues to show the count of *active* quests (completed quests are excluded from the source list per FR-022).
- Modal: gains a tab strip ("Active" / "Completed") at the top of the left-hand list. Active tab shows the same list as the HUD card with the full narrative. Completed tab shows completed quests indefinitely (FR-025). A completed quest's row is visually marked (e.g., a check glyph + dimmed text) per FR-026.

`GameLive` flips `@quests` and `@quest_details` from `GameData` stubs (`game_data.ex:85–129`) to live `Quests.active_for/1` and `Quests.history_for/1` reads, and adds three new `handle_info/2` clauses for the new PubSub events.

**Rationale**:
- The shape of the existing stub matches what we need with very small changes — the HUD card was already designed as a list of titles + progress strings, just with mock content.
- Repurposing keeps CSS / theming / layout consistent with the rest of the GUI (`specs/001-gui-design-language`) for free.
- Replacing `GameData.quests/0` and `GameData.quest_details/0` cleanly removes the mock-data path.

**Alternatives considered**:
- *Dedicated quest page / route*: Rejected — the HUD + modal pattern is the established at-a-glance/detail split used for inventory, stats, presence; quest mirrors that.
- *Inline chat lines per progress event ("You found 1 of 3 golden apples")*: Out of scope for v1 (noted as a future UX nicety during the design conversation). The quest log is the visible feedback channel.

## D-9: NPC blueprint extension via additive `quests` field on existing schema + event

**Decision**: Add a `quests` field to `NPCBlueprint` schema, struct, and `NPCBlueprintCreated` event. Default empty array. Existing blueprints replay with `quests: []`, which means "no quests offered" — exactly the prior behavior. Wizard authoring extends the existing `CreateNPCBlueprint` command struct with the same field; validation (slug presence, ≥1 criterion, spawn_room_ids exist at command-dispatch time) lives in the command wrapper.

**Rationale**:
- Strictly additive — no migrations of existing events, no event versioning, no shim. Default works for every legacy blueprint.
- Reuses the existing wizard authoring flow rather than introducing a separate "quest catalog editor" surface for v1. Future versions of NPC authoring (e.g. the toolset-composition model hinted at in `[[project_npc_toolsets]]`) can pull `quests` out of the blueprint and into a dedicated toolset; today's design doesn't preclude that.

**Alternatives considered**:
- *Separate `npc_quest_catalogs` table*: Rejected for v1 — adds a join, a separate authoring flow, and no benefit when each blueprint owns its catalog.
- *Quests authored as wizard-driven event sourcing on a separate `QuestCatalog` aggregate*: Rejected — catalogs change rarely; pretending they're a hot-loop event source is overkill.
