# Feature Specification: Quest System (v1, FetchQuest)

**Feature Branch**: `013-quest-system`
**Created**: 2026-05-27
**Status**: Draft
**Input**: User description: "Quests v1 — FetchQuest template with chat-driven lifecycle, instanced world items scoped per player, sticky one-time completion per (player, quest), and a live-updating quest log."

## Clarifications

### Session 2026-05-27

- Q: When `accept_quest`, `check_progress`, or `finalize_quest` is called with input that cannot be satisfied (already-completed slug, unknown quest instance ID, missing items, etc.), what should happen? → A: All three tools return a structured failure value (`{ok: false, reason: <code>, details: ...}`) to the LLM; the NPC's next turn renders the refusal in-character. The engine never speaks directly to the player.
- Q: How long do completed quests remain visible in the quest log? → A: Completed quests leave the active log surface (the HUD card) immediately on finalize; they persist indefinitely in a separate browsable "Completed" view accessible through the quest detail modal. All completions are retained for the player's lifetime.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Accept a quest from an NPC and see it appear in the quest log (Priority: P1)

A player chats with a questgiver NPC. The NPC mentions an available quest in conversational prose. The player expresses intent to take it on ("sure", "I'll do it", "yes"). The quest immediately appears in the player's quest log as active, with each required-item criterion shown at `0 / target`. The quest's key items spawn into their designated world rooms, owned by this player.

**Why this priority**: Without offer + accept working, no other quest functionality matters. This is the entry point to the entire system and the only path that creates a quest record.

**Independent Test**: A wizard authors a questgiver NPC with one FetchQuest in its catalog. A player chats with the NPC, says "yes" when the quest comes up, and verifies (a) the quest log shows the quest as active with `0 / target` progress, (b) the designated rooms now contain the quest's key items visible only to that player, and (c) no other player sees those items.

**Acceptance Scenarios**:

1. **Given** a player is chatting with an NPC whose catalog contains a FetchQuest the player has not completed, **When** the player expresses acceptance intent in natural language, **Then** an active quest record is created for that player, the quest log updates to display the new quest with each criterion at `0 / target`, and the quest's key items spawn in the designated rooms scoped to that player.
2. **Given** a player has already completed a quest with a specific NPC, **When** the player chats with that NPC and references the quest, **Then** the NPC reacts in-character acknowledging prior completion and no new quest record is created.
3. **Given** two players have independently accepted the same quest from the same NPC, **When** either player enters one of the designated rooms, **Then** that player sees only their own key item (not the other player's), and the other player's progress is unaffected by the first player's actions.

---

### User Story 2 - Collect quest items and watch progress update live (Priority: P1)

A player with an active FetchQuest travels through the world picking up tagged quest items. Each pickup increments the corresponding criterion's count in the quest log in real time. Dropping or otherwise removing a tagged item from inventory decrements the count.

**Why this priority**: This is the loop the player will spend most of their time in. Without live, accurate progress feedback the quest feels unresponsive and the player cannot tell whether they are done.

**Independent Test**: A player with one active FetchQuest that requires 3 of a tagged item walks into each designated room and takes the item. After each pickup the quest log line for that criterion advances by one (e.g. `0 / 3` → `1 / 3` → `2 / 3` → `3 / 3`) without manual refresh. Dropping one of the items rolls the count back down by one.

**Acceptance Scenarios**:

1. **Given** a player has an active FetchQuest requiring N items of a given quest tag and currently holds zero such items, **When** the player picks up one matching tagged item, **Then** the quest log for that criterion updates from `0 / N` to `1 / N` without a page reload.
2. **Given** a player holds K of N required items for a criterion, **When** the player drops or removes one of those items from inventory, **Then** the quest log for that criterion updates from `K / N` to `K-1 / N`.
3. **Given** a player accepts the quest while already carrying a matching tagged item (from any source), **When** the engine evaluates progress immediately on accept, **Then** the criterion reflects the current inventory count rather than zero.

---

### User Story 3 - Finalize the quest and receive the reward (Priority: P1)

A player who has collected all required items returns to the questgiver NPC and expresses intent to turn the quest in ("here you go", "I've got them", "I'm here to collect"). If all key items are present, they are destroyed atomically, the reward item is minted into inventory, and the quest is marked completed. If any items are missing, no state changes, and the NPC reacts in-character noting what is still needed.

**Why this priority**: Without finalize the player cannot complete a quest or claim a reward, defeating the loop. Together with US1 and US2 this forms the MVP.

**Independent Test**: A player with all required items chats with the questgiver and says "here you go". Verify (a) all key items are removed from inventory, (b) the reward item is added to inventory, (c) the quest log marks the quest as completed, and (d) any quest-scoped items still sitting in designated rooms for this quest instance are cleaned up. Repeat with a missing item and verify zero state change plus an in-character NPC response.

**Acceptance Scenarios**:

1. **Given** a player has an active FetchQuest with every criterion satisfied, **When** the player expresses finalize intent to the questgiver, **Then** all key items are removed from inventory, the reward item is minted into inventory, the quest record transitions to completed, and the quest log reflects all three changes.
2. **Given** a player has an active FetchQuest with at least one criterion not yet satisfied, **When** the player expresses finalize intent to the questgiver, **Then** no inventory changes occur, no reward is minted, the quest remains active, and the NPC responds in-character identifying what is still missing.
3. **Given** a quest instance has been finalized, **When** the engine processes finalization, **Then** any uncollected key items still in designated rooms tied to that instance are removed from the world.

---

### Edge Cases

- **Concurrent accept attempts**: If a player accepts the same quest twice rapidly (double-click on intent, retry on a network glitch), only one active quest record exists; the second attempt is a no-op.
- **Stockpiling tagged items before accept**: A player carrying a tagged item from a prior unrelated source at the time of accept begins the quest with non-zero progress. This is acceptable: tags are owned per quest instance, so cross-quest contamination is structurally prevented.
- **Player drops a key item and can't recover it**: Progress regresses to match current inventory. There is no mechanism in v1 to respawn dropped key items; the player must recover what they dropped, or the quest sits stuck in `active`. Abandonment is out of scope for v1.
- **Quest record exists but no NPC chat is open**: Progress events still fire on pickup/drop. The quest log updates regardless of whether the player is in a chat session.
- **Player tries to finalize away from the questgiver**: Finalize intent only reaches a tool call from within a chat session with the questgiver NPC. There is no global "turn in quest" command.
- **Two FetchQuests with structurally similar items**: Per-instance tag scoping ensures items belonging to one quest instance cannot satisfy another instance, even if their template-level tag patterns look similar.
- **NPC LLM context loss mid-conversation**: The list of player completions and active instances is injected into the NPC system prompt every turn, so the NPC behaves correctly even with no chat memory.
- **Quest items persist when player logs out**: Quest-scoped items continue to exist in the world for that player's quest instance and are visible to them again on return. Cleanup happens only on finalize.

## Requirements *(mandatory)*

### Functional Requirements

#### Quest catalog and authoring

- **FR-001**: A wizard MUST be able to attach a catalog of one or more FetchQuests to an NPC at NPC authoring time.
- **FR-002**: Each FetchQuest in a catalog MUST have a stable slug unique within that NPC's catalog, a title, a narrative summary, one or more required-item criteria, and a reward definition.
- **FR-003**: Each required-item criterion MUST consist of a quest tag (lowercase dot-segmented string) and a positive integer target count.
- **FR-004**: Quest tags MUST be scoped per quest instance — when a quest is accepted, the tag namespace MUST be unique to that instance so that two concurrent quests (across one or many players) cannot share inventory.
- **FR-005**: Each FetchQuest definition MUST declare a set of designated spawn rooms, mapping each required quest tag to the room(s) where the corresponding key items appear when the quest is accepted.
- **FR-006**: A reward definition MUST consist of an item name and item description, used to synthesize the reward item at finalize time. No item template system is required.

#### Quest lifecycle (chat-driven)

- **FR-007**: The questgiver NPC MUST be able to mention its catalog quests conversationally to a player based on system-prompt context. No dedicated "offer" tool call exists in v1.
- **FR-008**: The system MUST expose an `accept_quest` operation that the NPC's intent-parsing layer invokes when the player expresses acceptance intent in natural language.
- **FR-009**: Calling `accept_quest` for a (player, NPC, quest slug) triple MUST: (a) return a structured failure with reason `already_completed` if the player has that quest in `completed` state with this NPC, (b) return a structured failure with reason `already_active` if the player has that quest in `active` state with this NPC, (c) return a structured failure with reason `unknown_slug` if the slug is not in this NPC's catalog, (d) otherwise create an `active` quest record, trigger key-item spawning, and return a structured success value.
- **FR-010**: The system MUST expose a `check_progress` operation that returns, for the named quest instance, the current per-criterion progress (count present in inventory and target count) without modifying any state. The operation MUST return a structured failure with reason `unknown_instance` if the quest instance ID is not an active instance belonging to the calling player.
- **FR-011**: The system MUST expose a `finalize_quest` operation that atomically: verifies the quest instance ID is an active instance belonging to the calling player; if not, returns a structured failure with reason `unknown_instance`. Otherwise verifies every criterion is satisfied by current inventory; if so, removes the required quantity of tagged items, mints the reward item into inventory, marks the quest `completed`, cleans up any remaining quest-scoped items for that instance, and returns a structured success value; if criteria are unsatisfied, performs no state change and returns a structured failure with reason `criteria_unmet` and `missing: [...]` details.
- **FR-011a**: All three quest tools (`accept_quest`, `check_progress`, `finalize_quest`) MUST return values in a uniform structured shape: success as `{ok: true, ...}`, failure as `{ok: false, reason: <code>, details: ...}`. The NPC LLM is responsible for rendering both success and failure to the player in-character on its next conversational turn; the engine MUST NOT emit user-facing messages directly from these tools.
- **FR-012**: A quest in `completed` state for a (player, NPC, quest slug) triple MUST be permanently ineligible for re-acceptance by that player from that NPC in v1.

#### NPC awareness of player state

- **FR-013**: The NPC's per-turn context MUST include the catalog of offerable quests and the list of slugs this specific player has already completed with this NPC, so the LLM can react in-character to repeat requests without a separate tool call.
- **FR-014**: The NPC's per-turn context MUST include the list of active quest instances this player currently has open with this NPC, so the LLM can pick the correct quest instance ID when invoking `check_progress` or `finalize_quest`.

#### Item spawning and visibility (instanced world items)

- **FR-015**: On `accept_quest`, the engine MUST spawn each required key item, in the count specified by the criterion's target, into the designated rooms, with each spawned item carrying the quest tag, the unique quest instance identifier, and a `quest_player_id` referencing the accepting player.
- **FR-016**: Rooms MUST render their items per-viewer: items carrying a `quest_player_id` MUST be visible and takeable only by the player whose ID matches. Items without a `quest_player_id` MUST continue to render as public to all viewers, exactly as today.
- **FR-017**: Quest-scoped items MUST be takeable by their owning player using the same inventory mechanics as any other item — no special "quest take" command.
- **FR-018**: On `finalize_quest`, the engine MUST remove from the world any quest-scoped items associated with that quest instance, regardless of whether they remain in the original room, have been moved to another room, or are still being held.

#### Progress tracking and broadcasting

- **FR-019**: Progress for an active quest's criterion MUST be a pure function of the player's current inventory matching that criterion's quest tag, never a stored lifetime-pickup count.
- **FR-020**: The inventory system MUST emit pickup and drop events the quest tracker subscribes to. On any inventory change involving an item whose tag matches an active quest's criterion for that player, the system MUST recompute progress for that quest and broadcast a quest-progress event.
- **FR-021**: A quest-progress event MUST include enough information for a subscriber to update one quest's per-criterion display without re-fetching the full quest log.

#### Quest log UI

- **FR-022**: A player MUST have a visible active quest log surface (e.g. an always-visible HUD card) that lists their currently active quests. Completed quests MUST NOT appear in this active surface.
- **FR-023**: Each active quest entry MUST display the quest's title, its narrative summary, and one line per criterion in the form `<criterion name>: <current count> / <target count>`.
- **FR-024**: The active quest log surface MUST update in real time (without page reload) on quest acceptance, on every inventory change that affects an active quest's progress, and on finalize.
- **FR-025**: A player MUST also have a separate browsable "Completed" quest view (e.g. a tab within the quest detail modal) that lists all of their completed quests indefinitely, retained for the player's lifetime.
- **FR-026**: Completed quests in the browsable Completed view MUST be visually marked as completed (and thus distinguishable from any future active entry should the same title appear elsewhere).

#### Persistence and recovery

- **FR-027**: Active quest records, completed quest records, spawned quest-scoped items, and the (player, NPC, quest slug, state) relationships MUST survive process restart so a player's progress is preserved across sessions.

### Key Entities

- **FetchQuest definition (template-level)**: Wizard-authored definition attached to an NPC. Attributes: slug, title, narrative summary, list of criteria (each with quest tag and target count), designated spawn rooms per tag, reward (name + description).
- **Quest instance**: A specific (player, NPC, quest slug) acceptance. Attributes: unique instance ID, state (`active` / `completed`), accepted-at timestamp, completed-at timestamp (when applicable). Owns the set of spawned quest-scoped items and the namespace for its quest tags.
- **Quest-scoped item**: An item carrying a quest tag, a quest instance ID, and a `quest_player_id`. Visible and takeable only to the matching player; cleaned up on finalize.
- **NPC quest catalog**: A list of FetchQuest definitions attached to a specific NPC.
- **Player quest history**: Per (player, NPC) record of which quest slugs are currently active and which have been completed.
- **Quest progress event**: Broadcast on a per-player channel whenever an active quest's progress changes, and on accept and finalize. Carries enough information to update a single quest's log entry.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A player can complete the orchard-keeper walkthrough end-to-end (chat → accept → pick up three apples in three rooms → return → finalize → receive reward) without any intervention by a wizard or developer, in under 5 minutes of in-game play assuming the player knows where the rooms are.
- **SC-002**: Quest log entries reflect inventory changes within 1 second of the pickup or drop event in 95% of cases under normal multi-player load.
- **SC-003**: When two players accept the same FetchQuest from the same NPC concurrently, each player sees and can only interact with their own spawned key items; verified by neither player being able to take or destroy the other player's items in any sequence of actions.
- **SC-004**: After a player completes a FetchQuest with an NPC, every subsequent attempt to ask the same NPC for the same quest in natural language results in an in-character refusal from the NPC and zero new quest records, across at least 10 varied phrasings of the request.
- **SC-005**: A `finalize_quest` operation called with one or more criteria unsatisfied produces zero state change (no inventory removal, no reward mint, no record transition) — verifiable by snapshotting state before and after.
- **SC-006**: After a process restart, a player who had an active FetchQuest with two of three items in inventory resumes with the quest still active, the two items still in inventory, the third item still present in its designated room (only visible to that player), and the quest log showing `2 / 3`.

## Assumptions

- The existing per-viewer filtering pattern used for `other_players` in the room view can be extended to filter items by `quest_player_id` without introducing a new visibility primitive — i.e., per-viewer item filtering is an additive change to the room read model, not a redesign.
- The existing chat / intent-parsing layer (LLM tool-calling) is the only entry point for quest state transitions in v1. There are no UI buttons or commands (e.g., no "Accept" button on a quest card, no `/accept` command) for quest acceptance.
- The inventory system can be augmented to emit pickup and drop events on a known channel, or already does so. If it does not, that augmentation is in scope for this feature.
- Quest tags are owned by the quest instance, not the template. A definition declares a tag pattern (e.g. `quest.orchard.golden_apple`); when a player accepts, the engine derives an instance-scoped tag if necessary to prevent cross-instance collision. The exact derivation strategy is an implementation detail for planning.
- Rewards in v1 produce a single item per quest. Multi-item rewards, currency, XP, reputation, and lore unlocks are out of scope.
- Quest abandonment, expiration, time limits, and repeatable quests are out of scope for v1; once accepted, a quest is either completed or sits indefinitely in `active` state.
- Wizards authoring a FetchQuest are responsible for ensuring the designated spawn rooms exist in the world map at the time the quest becomes acceptable. Validation of room references is at authoring time, not accept time, in v1.
- Bespoke reward items (e.g. the "bigger golden apple") are synthesized in code from the `{name, description}` reward definition at finalize time. No general item authoring or item template system is built as part of this feature.
- Push-style completion notifications (NPC proactively pings the player when criteria are satisfied) are out of scope. All lifecycle transitions are player-initiated through chat.
