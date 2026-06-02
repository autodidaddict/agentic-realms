# Feature Specification: Wizard-Created Object Blueprints (Milestone 1)

**Feature Branch**: `014-item-blueprints`
**Created**: 2026-06-02
**Status**: Draft
**Input**: User description: "wizard-created item blueprints (milestone 1)"

## Overview

This is **milestone 1** of a multi-milestone effort to let wizards author the world's content (rooms, objects, NPCs, quests, spells) interactively. Milestone 1 scope is **object blueprints only** — the substrate, the trance/sanctum authoring mode, and the world-side affordances for spawning and extracting object blueprints. NPC blueprints follow in milestone 2, which will also fold spec 008's existing `NPCClonedFromBlueprint` event and `npc_clones.blueprint_id` column into the simpler pattern this milestone establishes.

The codebase calls these world objects "Objects" (table `world_objects`, schema `Object`, events `Object*` from feature 006 onward). The spec 001 wizard UI mockup labels them "Item" in the kind picker. This spec uses "Object" everywhere except in user-facing UI copy, where "Item" continues to appear; the two terms refer to the same entity.

## Clarifications

### Session 2026-06-02

- Q: Are Object Blueprints global, creator-owned, or owner-with-admin-override? → A: Global — any authenticated wizard may edit any Object Blueprint in this milestone. The existing **regions** concept (e.g., Blackmire, Hollowvale from the world seed) is the planned basis for future authorization scoping, but is not in milestone 1's scope.
- Q: Can wizards delete Object Blueprints in milestone 1? → A: No — delete is not exposed. The registry shows every Blueprint that has ever been committed. Cleanup, if needed, is via wipe-and-replay during the destroyable-event-log phase. Adding delete (soft or hard) is a future-milestone concern.
- Q: Does milestone 1 carry forward spec 001's "Save as draft" button? → A: No — the wizard view's footer in milestone 1 has two buttons only: **Discard** and **Commit**. Spec 001's three-button footer (Discard / Save as draft / Commit to world) is amended; in-flight work is lost on disconnect or mode switch. Drafts are deferred to a future milestone.
- Q: How are concurrent commits to the same Object Blueprint resolved? → A: Optimistic locking on `revision`. Each commit carries the wizard's known `revision`; if it doesn't match the persisted current `revision`, the commit fails and the wizard is shown the latest version to reapply their edits over. The whole flow MUST go through the event store (Commanded aggregate → event → projection) — concurrent-edit detection lives at the aggregate boundary, not in the projection layer. A future milestone that introduces behaviors will replace bulk Blueprint edits with discrete behavior-level events (`BehaviorAdded`, `BehaviorRemoved`, etc.), shrinking the per-commit overlap surface; until then, whole-Blueprint commit + revision check is sufficient.
- Q: How does the system distinguish wizards from players, and how does a player become a wizard? → A: A new `is_wizard` boolean on the `Accounts.Player` schema. Every wizard-only action (mode toggle, prompt submission in wizard view, all Blueprint and Object authoring commands, the Extract action, the Blueprints registry tab) MUST be gated on this flag. Promotion is performed by `AgenticRealms.Accounts.promote_to_wizard(player_id)` — a named function intended to be invoked from iex during local development. No UI for promotion ships in milestone 1.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Wizard Authors an Object Blueprint in Trance (Priority: P1)

A wizard in the room they've been editing flips the mode toggle from World to Sanctum. The wizard's chrome swaps into trance mode (no spatial context; no map; no current-room banner). Other players in the wizard's room see a system log entry: `<wizard name> enters a trance.` The wizard types a natural-language prompt into the textarea — *"a brass-bound chest, weather-beaten, carved with the seal of the Western Reach. Heavy. Fixed to whatever floor it sits on."* — and the Interpreted Data card progressively reveals fields the LLM has extracted: name `brass-bound chest`, short description, long description, `fixed: true`. The wizard clicks **Commit** in the footer. A new Object Blueprint exists in the blueprint registry, at revision 1. The wizard flips the toggle back; their player-visible log shows `<wizard name> appears to come out of a trance.`

**Why this priority**: This is the central authoring loop the milestone exists to deliver. Without it, blueprints cannot be authored at all and every downstream story is moot. The "speak it into being" prompt path is the headline user experience.

**Independent Test**: Sign in as a wizard, switch to Wizard mode (existing), flip the new mode toggle to Sanctum, type a prompt of at least 20 words describing an item, watch the Interpreted Data card populate, click Commit, then confirm a row exists in the blueprint registry with the expected name and `revision: 1`. Verify a player connected as a separate user in the wizard's room sees the trance entry/exit log entries at the moment of each toggle flip.

**Acceptance Scenarios**:

1. **Given** an authenticated wizard standing in a room, **When** they flip the mode toggle from World to Sanctum, **Then** the wizard's chrome switches to blueprint-mode (the World map and current-room banner are hidden, the prompt placeholder reads `describe an archetype...`), AND every other player session currently in that room receives a system log entry `<wizard display name> enters a trance.`
2. **Given** a wizard in Sanctum mode with an empty Interpreted Data card, **When** they type a multi-sentence prompt describing an item, **Then** the Interpreted Data card progressively reveals extracted fields (name, short description, long description, fixed flag) as the LLM produces them.
3. **Given** a populated Interpreted Data card, **When** the wizard clicks Commit, **Then** a new Object Blueprint persists with `revision: 1`, appears in the blueprint registry, and the Commit/Discard footer disables until further edits.
4. **Given** a wizard in Sanctum mode, **When** they flip the mode toggle back to World, **Then** the chrome switches back to world-mode, AND every other player in the wizard's current room receives a system log entry `<wizard display name> appears to come out of a trance.`
5. **Given** no other players are in the wizard's room, **When** the wizard toggles into or out of Sanctum, **Then** no log entries are emitted (no one to witness) and the mode switch is silent.

---

### User Story 2 - Wizard Spawns an Object from a Blueprint into a Room (Priority: P1)

A wizard in World mode stands in the Stone Atrium. They open the blueprint registry, find the `brass-bound chest` blueprint they authored earlier, and click **Spawn here**. A new Object appears in the Stone Atrium with the blueprint's fields denormalized into the row (name `brass-bound chest`, short description, long description, `fixed: true`). Every player currently in the Stone Atrium receives the standard object-arrival entry in their log. The wizard's player-side view (when they later flip to Player mode) shows the chest listed in the room. They could now spawn a second one — the second is a sibling, not the same object.

**Why this priority**: This is the payoff story for User Story 1 — blueprints are only valuable if you can put copies of them in the world. Spawning is also the simplest possible demonstration that the milestone is wired end-to-end.

**Independent Test**: Author a blueprint via Story 1, walk to a specific room, click Spawn here on the registry row, then `look` (as a player in the same room) and verify the new object is listed with its short description. Spawn it twice into different rooms; verify two independent objects with distinct ids exist.

**Acceptance Scenarios**:

1. **Given** a wizard in World mode in room R, with an Object Blueprint B in the registry, **When** they click "Spawn here" on B's registry row, **Then** a new Object is created in R with B's denormalized payload, an Object-arrival witness entry is emitted to every player in R, and the new Object carries no reference to B (no `blueprint_id` field, no stored lineage).
2. **Given** a Blueprint B has been used to spawn an Object O, **When** the wizard later edits B (incrementing its revision), **Then** O is unchanged — its fields reflect B's state *at the moment of spawn*, not B's current state.
3. **Given** a Blueprint B, **When** the wizard spawns from B twice into the same room, **Then** two distinct Objects exist in that room with different ids and matching denormalized payloads (the standard same-room-name disambiguation rules from feature 006 apply to examination).

---

### User Story 3 - Wizard Creates an Object Freeform in the World (Priority: P2)

A wizard in World mode stands in a room and types a prompt directly into the world-mode prompt textarea — *"a small clay pot, half-empty of dry barley, leaning against the wall"* — without selecting any blueprint. The LLM-routed intent recognizes the prompt as an object-creation action. The Interpreted Data card populates with extracted fields. The wizard clicks Commit. A new Object exists in the wizard's current room. **No Object Blueprint is created.** The object is freestanding and exists in the world identically to one spawned from a blueprint — there is no observable difference.

**Why this priority**: Demonstrates blueprints are *optional* — one-off content is a first-class path, not a workaround. Lower priority than P1 because the spawn-from-blueprint path is the more representative authoring loop; freeform is the convenience path for one-offs.

**Independent Test**: As a wizard in World mode in a specific room, submit a prompt describing an item, click Commit, then verify (a) a new Object exists in that room and (b) the blueprint registry contains no new entries.

**Acceptance Scenarios**:

1. **Given** a wizard in World mode in room R, **When** they submit an object-describing prompt and click Commit, **Then** a new Object is created in R with the LLM-extracted payload, and the blueprint registry's row count is unchanged.
2. **Given** a freshly created freeform Object, **When** another player examines it, **Then** the long description renders exactly as feature 006 specifies — there is no visible indicator that the object was created without a blueprint.
3. **Given** a wizard's prompt is ambiguous or describes something that is not an object (e.g., `tell me about the western reach`), **When** the wizard submits it, **Then** the Interpreted Data card does not populate, the Commit button does not enable, and an inline hint indicates the prompt was not recognized as a creation intent.

---

### User Story 4 - Wizard Extracts Essence from a World Object into a New Blueprint (Priority: P2)

A wizard in World mode focuses a specific Object in the room (clicking it in the room view's entity list, or in the Objects registry). On the focused Object's panel an **Extract essence** button appears. The wizard clicks it. The wizard is immediately flipped into Sanctum mode (trance log entries emit to other players in the room), and the Interpreted Data card opens in blueprint-edit mode pre-populated with a wholesale copy of every field on the source Object. The wizard can refine the draft (e.g., generalize the name from `Garrick's clay pot` to `clay pot`) via the form controls. They click Commit. A new Object Blueprint exists in the registry at `revision: 1`. **The source Object is unchanged** — it still stands in its original room with its original fields.

**Why this priority**: The "promote one-off to reusable" flow. P2 because the user only needs it after they've discovered something they made freeform is worth reproducing.

**Independent Test**: Create a freeform Object via Story 3 with a distinctive name. Focus it in the room view. Click Extract essence. Confirm (a) the wizard's mode flipped to Sanctum, (b) the Interpreted Data card is populated with the Object's exact field values, (c) on Commit, a new Blueprint exists with those values, (d) the source Object's fields are byte-identical to what they were before extraction.

**Acceptance Scenarios**:

1. **Given** a wizard in World mode focused on Object O, **When** they click Extract essence, **Then** the wizard's `authoring_mode` flips to `:blueprints`, the trance entry log entry is emitted, the Interpreted Data card opens with a draft blueprint whose every field equals O's corresponding field, and no Blueprint is persisted yet.
2. **Given** an in-progress extract draft, **When** the wizard clicks Commit, **Then** a new Object Blueprint persists with `revision: 1` and Object O is read back from the database with identical field values to before the extract was initiated.
3. **Given** an in-progress extract draft, **When** the wizard clicks Discard, **Then** no Blueprint is persisted, the wizard remains in Sanctum mode, and Object O is unchanged.

---

### User Story 5 - Wizard Edits an Existing Blueprint or Object via the Form Editor (Priority: P2)

A wizard finds an existing Blueprint in the registry and clicks its row. They are dropped into Sanctum mode (if not already there) with the Blueprint focused in the Interpreted Data card. The card is fully editable — name, short description, long description, fixed flag — using the same chip/text/toggle controls from spec 001's mockup. The wizard changes the short description, clicks Commit. The Blueprint's `revision` increments by 1. **No previously spawned Objects are affected.** Symmetrically, focusing a world Object in World mode lets the wizard edit its fields directly; on Commit, the Object's fields update in place and existing room-occupants see updated examine output on their next look.

**Why this priority**: Editing is the long tail of authoring — most blueprints will be tweaked many times after first creation. P2 rather than P1 because Story 1 already covers initial creation; editing is incremental.

**Independent Test**: Author a Blueprint, focus it from the registry, change one field via the form, click Commit, and verify (a) the Blueprint's revision is now 2, (b) any Objects previously spawned from it remain at their original field values, and (c) the form can edit it again to revision 3.

**Acceptance Scenarios**:

1. **Given** a Blueprint B at revision N in the registry, **When** the wizard clicks B's registry row, **Then** the wizard enters Sanctum mode (if not there already), B becomes the focused blueprint, and the Interpreted Data card renders B's current fields in editable form controls.
2. **Given** the wizard has edited B's fields in the card, **When** they click Commit, **Then** B's payload updates and B's revision increments to N+1.
3. **Given** the wizard has edited B's fields, **When** they click Discard before committing, **Then** the focused fields revert to B's persisted values and B's revision is unchanged.
4. **Given** an Object O exists in room R and the wizard is in World mode in R, **When** they click O in the room view, **Then** O becomes the focused object and its fields render in editable form controls. On Commit, O's fields update in place; any player examining O after the update sees the new values.
5. **Given** the wizard is currently typing in a prompt textarea, **When** they attempt to edit a focused thing's form fields, **Then** the form controls accept edits independently of the prompt — the two surfaces never compete for input.

---

### User Story 6 - Wizard Browses the Blueprint Registry from Either Mode (Priority: P3)

A wizard can open the Blueprints registry tab from either World mode or Sanctum mode. The registry shows a paginated list of every Object Blueprint with its name, revision, and a short snippet of its description. From World mode, each row exposes a "Spawn here" action that creates an Object in the wizard's current room. From either mode, clicking the row enters/stays in Sanctum and focuses the Blueprint for editing.

**Why this priority**: Quality-of-life navigation. Without this, the wizard would still be able to author blueprints (they remember the names) but wouldn't have an easy way to discover or re-find them. P3 because Stories 1, 2, and 4 are functional without it (the registry can ship as a flat list with no filter/search in milestone 1).

**Independent Test**: Author three blueprints. Open the registry from World mode. Confirm all three are listed. Click "Spawn here" on one — verify it spawns in the current room. Click the row of another — verify trance starts and that blueprint becomes focused.

**Acceptance Scenarios**:

1. **Given** N Object Blueprints exist, **When** the wizard opens the Blueprints registry tab in either mode, **Then** all N are listed showing name, revision, and a short description snippet.
2. **Given** the wizard is in World mode in room R and the registry shows a Blueprint B, **When** they click "Spawn here" on B's row, **Then** a new Object is created in R with B's denormalized fields (equivalent to Story 2 via prompt-driven spawn).
3. **Given** the wizard is in any mode and the registry shows Blueprint B, **When** they click B's row title (not the Spawn action), **Then** the wizard enters Sanctum (if not there) and B becomes the focused blueprint with editable form controls.

---

### Edge Cases

- **Wizard in trance disconnects.** If the wizard's session drops while in Sanctum mode, their presence is removed from the world (existing presence rules). No automatic "wakes from trance" log entry is emitted — the wizard is simply gone. On reconnect, they return in World mode by default (the trance flag does not persist across sessions in milestone 1).
- **Two wizards in the same room, both in trance.** Each transition emits its own log entry. There is no aggregate or deduplicated "the wizards are in a trance" message.
- **Wizard attempts to spawn an object in a room they are not in.** Not supported in milestone 1. The Spawn here action is wizard's-current-room-only; the registry does not offer a room picker. Future milestone may add cross-room spawning.
- **Wizard edits a Blueprint while another wizard is mid-extract from the same Object.** Edits to a Blueprint and an Object are independent — extracts copy from the Object's current persisted state at the moment of the click, so a concurrent Blueprint edit affects nothing.
- **Player examines an Object during the moment of its spawn.** Existing concurrency rules from features 006/007 apply — the spawn arrival entry and any look output interleave by event order.
- **LLM extraction fails or returns nothing useful.** The Interpreted Data card stays empty, the Commit button stays disabled, and the wizard can edit the prompt or use the form controls directly to author fields. The form is always the authoritative input; the prompt is a convenience.
- **Wizard edits a freeform Object's fields.** Same path as editing a Blueprint-spawned Object — Objects have no `blueprint_id`, no lineage. Edit just updates the row.
- **Blueprint at revision N is committed with no actual changes.** The revision does not bump — only field-changing commits increment revision (avoids no-op churn).
- **Wizard wants to remove a Blueprint.** Not supported in milestone 1 (see Clarifications). The registry MUST NOT expose a Delete affordance, the intent router MUST NOT support any deletion tool, and there is no event of the form `ObjectBlueprintDeleted`. Cleanup, if accumulation becomes a problem, is via wipe-and-replay during the destroyable-event-log phase.
- **Wizard disconnects mid-authoring.** Whatever was in the Interpreted Data card is lost (per the no-drafts clarification). On reconnect the wizard returns to `:world` mode (per FR-005) with a clean editor. No "resume your draft" prompt is shown.
- **Two wizards edit the same Blueprint and both press Commit.** Per FR-020a, the first commit succeeds and increments `revision` from N to N+1. The second wizard's commit fails with a stale-write error because their known revision is now stale; they are shown the latest version and prompted to reapply their edits over the newer state. There is no automatic merge.

## Requirements *(mandatory)*

### Functional Requirements

**Authoring mode & trance**
- **FR-001**: The wizard view MUST expose a mode toggle that switches the wizard's `authoring_mode` between `:world` and `:blueprints`. The toggle MUST be a UI control (button/switch/segmented chooser) — there MUST NOT be a typed verb the wizard must enter to change mode.
- **FR-002**: When a wizard's `authoring_mode` flips from `:world` to `:blueprints`, every other player session currently in the wizard's room MUST receive a system log entry of the form `<wizard display name> enters a trance.`
- **FR-003**: When a wizard's `authoring_mode` flips from `:blueprints` to `:world`, every other player session currently in the wizard's room MUST receive a system log entry of the form `<wizard display name> appears to come out of a trance.`
- **FR-004**: When a wizard's room contains no other live player sessions at the moment of a mode flip, NO trance log entries are emitted. There MUST NOT be a replay of missed trance entries when a player reconnects later (consistent with feature 003's live-witness model).
- **FR-005**: When a wizard's session disconnects while in `:blueprints` mode, no `appears to come out of a trance` entry is emitted. On reconnect, the wizard's authoring mode resets to `:world`.
- **FR-006**: While in `:blueprints` mode, the wizard's player-side presence remains pinned to their world coordinate. They MUST be visible in the room view of any player who `look`s, but spatial commands targeting the wizard (whisper, examine) MUST behave per existing rules — `:blueprints` mode is a UI state on the wizard's session, not a world-state condition.
- **FR-006a**: Any authenticated wizard MUST be permitted to create, edit, extract, and spawn from any Object Blueprint in this milestone. Object Blueprints MUST NOT carry a `created_by` field, a region scope, or any other ownership attribute. (Region-based authorization is a planned future direction — see the corresponding entry in the Clarifications section — but is explicitly out of scope here.)

**Wizard authorization**
- **FR-WIZ-1**: The `Accounts.Player` schema MUST gain an `is_wizard` boolean column (default `false`). Existing players are non-wizards until explicitly promoted.
- **FR-WIZ-2**: `AgenticRealms.Accounts.promote_to_wizard/1` MUST be exposed as a public function that takes a player id, sets the player's `is_wizard` to `true`, and returns `{:ok, %Player{}}` on success or `{:error, :not_found}` if no such player exists. The function MUST be safely re-runnable on an already-wizard player (idempotent — returns the same `{:ok, ...}` shape). No demote function is in scope for milestone 1.
- **FR-WIZ-3**: The Player/Wizard top-bar mode switch from spec 001 MUST render only when the authenticated player's `is_wizard` is `true`. For non-wizards the switch MUST NOT appear, and the wizard view MUST NOT be reachable via direct URL — any LiveView mount targeting the wizard view by a non-wizard MUST redirect to the player view with a flash or be 404'd (planning-level choice).
- **FR-WIZ-4**: Every wizard-only LiveView event (mode toggle, prompt submit, Commit, Discard, Extract, "Spawn here" on a registry row) MUST verify `is_wizard` at handler entry. A non-wizard who somehow triggers one of these events (e.g., via crafted client-side message) MUST receive a refusal; the system MUST NOT mutate state.
- **FR-WIZ-5**: Every wizard-only Commanded command MUST carry the originating player's `id`, and the command-dispatch wrapper MUST verify `is_wizard` at dispatch time. Commands MUST be refused with `{:error, :not_a_wizard}` if the player is not a wizard.
- **FR-WIZ-6**: No UI for promoting a player to a wizard ships in milestone 1. Promotion is exclusively performed via `iex` invocation of `Accounts.promote_to_wizard/1` against the local node.

**Object Blueprint data model**
- **FR-007**: The system MUST support an Object Blueprint entity with at minimum: `id` (see FR-007a), `kind` (constant `object` in this milestone), `name`, `short_description`, `long_description`, `fixed` (boolean), `revision` (integer ≥ 1), and creation/update timestamps.
- **FR-007a**: An Object Blueprint's `id` MUST be a human-typable string slug consisting only of lowercase ASCII letters, digits, and underscores (regex `^[a-z][a-z0-9_]*$`), at least 1 and at most 64 characters long. The id MUST be globally unique among Object Blueprints. UUIDs MUST NOT be used. This aligns with spec 008's existing NPC Blueprint id pattern, where blueprints carry typeable identifiers like `garrick_the_innkeeper` rather than UUIDs.
- **FR-007b**: On Blueprint creation, the system MUST default-derive a candidate `id` from the wizard-supplied `name` by lowercasing, replacing non-alphanumeric runs with `_`, and stripping leading/trailing underscores. The wizard MUST be able to override this candidate before committing. After commit the `id` is immutable — subsequent edits to `name` MUST NOT change the `id`. If the derived candidate collides with an existing Blueprint id, the system MUST surface the collision in the form so the wizard can choose a different id before commit (no automatic numeric suffixing).
- **FR-008**: Object Blueprint `revision` MUST start at 1 on creation and MUST increment by exactly 1 on every commit that changes one or more of the blueprint's content fields. Commits that do not change any field MUST NOT bump `revision`.
- **FR-009**: Object Blueprints MUST NOT carry a list, count, or any other reference to the Objects spawned from them. The relationship is constructor-only.

**World Object creation paths**
- **FR-010**: The system MUST support a "spawn from blueprint" action available in World mode: given a focused Blueprint and the wizard's current room, the system MUST create a new Object in that room with every field denormalized from the blueprint at spawn time.
- **FR-011**: The system MUST support a "freeform create" action available in World mode: given a wizard's natural-language prompt and their current room, the LLM-routed intent MAY produce a draft Object whose fields the wizard can review and commit. On commit, a new Object MUST be created in the wizard's current room with no blueprint reference of any kind.
- **FR-012**: Objects created via either path MUST be observationally indistinguishable in the world (same row schema, same examination behavior, same takeable-or-fixed handling per feature 006).
- **FR-013**: Newly spawned Objects MUST NOT carry a `blueprint_id` field on the read-model row. The spawn event MUST NOT carry a `blueprint_id` field in its payload. Historical origin is not preserved beyond the event-stream record of what was spawned.
- **FR-014**: When a new Object is spawned into a room that has one or more live player sessions present, those sessions MUST receive an arrival witness entry consistent with feature 007's FR-011 pattern (`<object short description> appears.` or equivalent — the exact copy is settled by existing patterns, not by this spec).

**Extract action**
- **FR-015**: When the wizard focuses a world Object in World mode, the focused-Object panel MUST expose an "Extract essence" action.
- **FR-016**: Clicking Extract essence MUST: (a) flip the wizard's `authoring_mode` to `:blueprints` (with the FR-002 trance log entry), (b) open a draft Blueprint in the Interpreted Data card whose every settable field is a wholesale copy of the source Object's corresponding field, (c) leave the source Object unmodified in the database.
- **FR-017**: An in-progress extract draft that is Discarded MUST result in no persisted Blueprint and no changes to the source Object. The wizard MUST remain in `:blueprints` mode after Discard — the trance does not auto-end.
- **FR-018**: An in-progress extract draft that is Committed MUST persist a new Object Blueprint at `revision: 1` whose fields match what the wizard saw in the Interpreted Data card at commit time. The source Object MUST remain unmodified by the extract.

**Editing**
- **FR-019**: The Interpreted Data card MUST serve as the editor for any focused Object or Blueprint, using direct form controls (text inputs, chip editors, boolean toggles) as appropriate for each field type. No natural-language prompt MUST be required to perform an edit.
- **FR-020**: Committing edits to a Blueprint MUST update its persisted fields and increment its `revision` per FR-008. Committing edits to an Object MUST update its persisted fields in place; the Object's identity is unchanged.
- **FR-020a**: Every Blueprint edit-commit MUST carry the wizard's *known* `revision` value (the revision at the moment the form was opened). If the persisted Blueprint's current `revision` does not equal that value at the moment of commit, the commit MUST fail with a stale-write error and the wizard MUST be presented with the latest persisted version so they can reapply their edits. The check MUST be enforced inside the Commanded aggregate that owns the Blueprint (not in the projection or in the LiveView), so concurrent commits race at the event-store boundary rather than at the read model.
- **FR-020b**: All state changes covered by this spec — Blueprint creation, Blueprint edits, Object spawn (both paths), Object edits, and extract commits — MUST be implemented as event-sourced aggregate commands that emit the events defined in FR-029 through FR-032. Direct writes to the read-model tables bypassing the aggregate are not permitted.
- **FR-021**: Editing a Blueprint MUST NOT propagate to any previously spawned Object. Editing an Object MUST NOT propagate to any Blueprint (none is referenced anyway).

**Intent routing**
- **FR-022**: The wizard's prompt textarea MUST be routed through an LLM-backed intent resolver that supports the following creation tools and no others in this milestone: `manifest_object_freeform`, `spawn_object_from_blueprint`, `draft_object_blueprint`. The resolver MUST also support the `extract_essence` tool when triggered by the UI button (not by natural-language prompt — Extract has no prompt-driven invocation in milestone 1).
- **FR-023**: The intent resolver MUST receive a `current_context` payload on every invocation containing `{mode: :world | :blueprints, room_id: <wizard's current room>, focused_object_id: <id or nil>, focused_blueprint_id: <id or nil>}`. Tools whose semantics depend on a current room (manifest/spawn) MUST use `room_id` from this context.
- **FR-024**: In `:blueprints` mode the resolver MUST refuse any tool that requires a `room_id` and MUST surface a hint to the wizard that spatial actions are not available in trance.
- **FR-025**: The resolver MUST NOT support any edit verbs (no `update_object`, no `set_field`, etc.). Edit requests phrased as prompts MUST be either ignored or surfaced as "edits happen via the form on the focused thing, not via prompts."

**Registry**
- **FR-026**: The wizard view MUST expose a Blueprints registry tab listing every Object Blueprint with at minimum: name, revision, and a short description snippet.
- **FR-027**: Each registry row, when the wizard is in World mode, MUST expose a "Spawn here" action that triggers FR-010 with the wizard's current room as the target.
- **FR-028**: Clicking the title of a registry row (in either mode) MUST: (a) flip the wizard's `authoring_mode` to `:blueprints` if not already there (with FR-002 log entry as a side effect), (b) make the clicked Blueprint the focused blueprint, (c) render its fields in the Interpreted Data card for editing.

**Events & migration**
- **FR-029**: A new event `ObjectSpawned` MUST be emitted on every world Object creation (both blueprint-spawn and freeform paths). The event payload MUST carry the new Object's `object_id`, the destination `room_id`, and the denormalized Object fields. The payload MUST NOT carry a `blueprint_id` field — by design, the spawned Object has no stored lineage to the Blueprint that produced it (if any).
- **FR-030**: A new event `ObjectBlueprintCreated` MUST be emitted on every Blueprint creation (both initial-author and post-extract paths). The event payload MUST carry the Blueprint's `blueprint_id` (the human-typable slug from FR-007a), the Blueprint's content fields, and `revision: 1`. The `blueprint_id` is mandatory — this event describes the lifecycle of a specific Blueprint and must identify it.
- **FR-031**: A new event `ObjectBlueprintEdited` MUST be emitted on every Blueprint edit-commit that changes one or more fields. The payload MUST carry the Blueprint's `blueprint_id`, the new field values, and the new `revision`. The `blueprint_id` is mandatory for the same reason as FR-030.
- **FR-032**: A new event `ObjectEdited` MUST be emitted on every Object edit-commit that changes one or more fields. The payload MUST carry the Object's `object_id` and the new field values. The payload MUST NOT carry a `blueprint_id` — consistent with FR-013 and FR-029, Object events never reference Blueprints.
- **FR-033**: The existing seed-time Object placement logic (feature 003 / 007 era) MAY be reworked to emit `ObjectSpawned` events in place of older paths. The event log is currently destroyable (no migration of stored events is required); see the project memory `event-log-destroyable-phase` for the rationale and the caveat about that phase ending.

### Key Entities

- **Object Blueprint**: A reusable archetype for an Object, authored by a wizard. Carries a human-typable string id (per FR-007a — e.g., `brass_bound_chest`, never a UUID), name, short description, long description, fixed flag, a monotonically increasing revision integer, and creation/update timestamps. Does NOT carry coord/room, does NOT carry a list of spawned Objects. Edits do not propagate to Objects spawned earlier. The id is immutable after creation and is the canonical reference for the Blueprint in events, registry rows, and LLM tool calls.
- **Object** (existing, schema unchanged in this milestone): A world entity placed in exactly one room (or carried by a player per feature 003's location model). Carries a denormalized payload populated either by a Blueprint at spawn time or by a wizard's freeform prompt. Does NOT carry any blueprint reference.
- **Wizard Authoring Mode** (new session-level state): A per-wizard-session flag with values `:world` or `:blueprints`. Drives the wizard view's chrome and the intent resolver's tool surface. Resets to `:world` on reconnect; not persisted to the world model.
- **ObjectSpawned event**: Records that an Object was placed in a room. Carries the denormalized payload and `room_id`; no `blueprint_id`. Replaces no prior event (Objects up to feature 013 were created via seed paths only; this is the first runtime Object-creation event).
- **ObjectBlueprintCreated / ObjectBlueprintEdited events**: Record the lifecycle of an Object Blueprint.
- **ObjectEdited event**: Records an in-place edit to a world Object made by a wizard via the form editor.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A wizard can author a new Object Blueprint, end-to-end (from flipping the mode toggle to seeing the Blueprint in the registry), in under 90 seconds for a single-paragraph description.
- **SC-002**: Spawning an Object from a Blueprint into the wizard's current room reflects in every co-located player's narrative log within 2 seconds of the wizard's click.
- **SC-003**: The trance log entries emitted to co-located players appear within 500 ms of the mode toggle flip, matching the latency budget of existing live-witness entries from feature 003.
- **SC-004**: Extracting essence from a world Object produces a draft Blueprint whose every field exactly matches the source Object's corresponding field, with zero divergence in 100% of regression tests.
- **SC-005**: Editing a Blueprint at revision N produces revision N+1 if any content field changed; a no-op commit produces no revision bump in 100% of regression tests.
- **SC-006**: A wizard editing a Blueprint does NOT alter any previously spawned Object's fields, verified by post-edit field-equality checks against the pre-edit Object snapshot.
- **SC-007**: Two Objects spawned from the same Blueprint into different rooms can be independently edited without cross-effect.
- **SC-008**: 100% of new Objects created in this milestone (via either path) have no `blueprint_id` column on their row and no `blueprint_id` field in `ObjectSpawned` or `ObjectEdited` event payloads. (Blueprint lifecycle events — `ObjectBlueprintCreated`, `ObjectBlueprintEdited` — naturally carry the operand Blueprint's `blueprint_id` per FR-030 and FR-031.)
- **SC-009**: 100% of Object Blueprints created in this milestone carry an `id` matching `^[a-z][a-z0-9_]*$` (length 1–64) and zero Object Blueprints have a UUID-shaped id.

## Assumptions

- **Terminology**: This spec uses "Object" to match the existing codebase schema (`world_objects`, `Object`, `Object*` events). Spec 001's UI mockup labels these "Items" in the kind picker and on registry chips; that label is unchanged for users. A future rename of either is out of scope.
- **Object schema fields covered**: This milestone covers the existing top-level scalar fields on `world_objects` — `name`, `short_description`, `long_description`, `fixed`. The `behaviors` field (array of maps) and quest-scoped fields (`quest_player_id`, `quest_instance_id`) are NOT in scope for either the Blueprint authoring surface or the freeform-create path; behaviors are deferred to a later wizard milestone, and quest-scoped objects continue to be created exclusively via feature 013's quest-accept path.
- **Blueprint kinds**: The Blueprint entity's `kind` field is a forward-looking distinguisher. Milestone 1 ships with `kind: object` only. Milestone 2 will add `kind: npc` and fold spec 008's existing `npc_blueprints` table either into a unified table keyed by `kind` or as a sibling table — that schema decision is deferred to milestone 2.
- **Blueprint id pattern aligns with spec 008**: Spec 008 already established that NPC Blueprints use human-typable string ids (`garrick_the_innkeeper`, `orchard_keeper`) rather than UUIDs. Milestone 1's Object Blueprints adopt the same convention (FR-007a). Milestone 2's unified-or-sibling table decision will preserve this convention; UUIDs are explicitly rejected as Blueprint identifiers across the system.
- **Mode toggle copy**: The exact wording of the in-fiction toggle ("Enter trance" / "Return to your body" vs. "Sanctum" / "World") is a UI-copy decision settled at LiveView wiring time. Both options are acceptable; the placeholder log entries in FR-002 and FR-003 are independent of the toggle button's label.
- **Wizard authorization is introduced by this spec**: There is no pre-existing `is_wizard` field on `Accounts.Player`; milestone 1 adds it (see FR-WIZ-1 through FR-WIZ-6 and the corresponding Clarifications entry). The Player/Wizard top-bar switch in spec 001's mockup was added on the assumption that some authorization mechanism would exist; this spec is what wires it up. Promotion is via `iex` only — no admin UI ships now.
- **Authorization vs event sourcing**: `is_wizard` lives on the `Accounts.Player` Ecto schema and is set by a plain Ecto update inside `Accounts.promote_to_wizard/1`. It is NOT event-sourced, consistent with the existing Accounts module style (registration, password change, preferences updates are all plain Ecto). Wizard authorization checks in the world layer read the flag synchronously from the read model; no Commanded aggregate is involved in the account-level promotion. This is a deliberate divergence from the world's event-sourcing pattern and is documented in research.md.
- **Spec 008 untouched**: Existing `npc_blueprints`, `npc_clones`, `NPCClonedFromBlueprint`, and the I-1 invariant ("every clone has exactly one blueprint at spawn time") remain in place exactly as feature 008 shipped. Milestone 2 amends them; this milestone does not.
- **Event log can be destroyed**: Per project memory `event-log-destroyable-phase`, the existing event log can be wiped during this milestone's deploy. No event-stream migration is required to introduce the new events or to retire any older paths. If this phase has ended by the time this spec ships, the migration story will need to be added.
- **No cross-room spawn**: Wizards can only spawn Objects into their current room in this milestone. A room picker on the registry's Spawn action is deferred.
- **No blueprint versioning beyond a counter**: The `revision` integer is a counter, not a version pointer. There is no checkout-old-revision, no branching, and no instance pinning. Existing Objects don't reference Blueprints anyway, so there is nothing to pin.
- **Future region-based authorization**: The world already partitions space into regions (e.g., Blackmire, Hollowvale per the existing world seed). A future milestone is expected to introduce region-scoped wizard authorization, where a wizard's edit/spawn/extract permissions on a Blueprint are gated by whether they have authoring rights in the regions where instances would land. Milestone 1 deliberately defers this — any wizard can do anything Blueprint-related — so the region-permission machinery does not have to ship in lockstep with the substrate. Code in milestone 1 should NOT introduce ownership fields that a region-permission system would later need to reconcile.
- **No Blueprint deletion in milestone 1**: Create, edit, spawn, and extract are the only Blueprint lifecycle actions. There is no `ObjectBlueprintDeleted` event, no soft-delete `is_archived` flag, no Delete button. The registry grows monotonically. If a future milestone adds delete, soft-delete is the more likely shape (preserves the event log's referential integrity), but that decision is deferred.
- **Spec 001 footer amended**: Spec 001's wizard mockup specifies a three-button footer (Discard / Save as draft / Commit to world). Milestone 1 ships a **two-button footer** (Discard / Commit) on every wizard authoring surface. The "Save as draft" affordance is deferred. The acceptance scenarios throughout this spec assume this two-button shape.
- **All state changes are event-sourced through Commanded aggregates**: Consistent with features 003, 007, 008, 011, 013, every Blueprint and Object mutation in this milestone is implemented as an aggregate command that emits the events defined in FR-029 through FR-032 and is projected into the read-model tables by the existing projector pattern. The aggregate is the only writer; the LiveView never updates rows directly. Optimistic-lock enforcement (FR-020a) lives in the aggregate.
- **Future direction — discrete behavior-level events**: When wizard authoring extends to object/NPC behaviors in a later milestone, bulk Blueprint edits are expected to give way to discrete events like `BehaviorAdded`, `BehaviorRemoved`, `BehaviorReordered`. This will narrow the concurrent-edit overlap window further (two wizards both adding behaviors to the same Blueprint will only conflict if their changes touch the same behavior). Milestone 1's whole-Blueprint optimistic lock is the simpler stepping stone, deliberately chosen because behaviors aren't here yet.
