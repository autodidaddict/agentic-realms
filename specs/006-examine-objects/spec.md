# Feature Specification: Examine Objects and Players

**Feature Branch**: `006-examine-objects`
**Created**: 2026-05-21
**Status**: Draft
**Input**: User description: "Objects should be examinable individually. In addition to using 'look' to examine the room, players should be able to look at objects. Eligible objects for examination are objects in the same room as the player and objects in the player's inventory. Other players are also examinable. If someone types 'look alice' (or the natural language equivalent) and Alice is in that room, then we will display 'Alice is a player.' This description will get more rich over time as more features are added. When examining an object, its long description is displayed."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Examine an Object in the Current Room (Priority: P1)

A player sees an object listed in their current room — say a brass lantern sitting on a mantel — and wants more detail than the brief one-line description shown in the room view. They submit `look brass lantern` (or `look lantern`, or a natural-language variant such as `examine the lantern`, `inspect the lantern`, `study the lantern`) and the narrative log appends a detail entry for that object, showing its long description. The object itself is unchanged — examination is purely a read action — and the rest of the game continues as normal.

**Why this priority**: This is the core payoff of the feature. The persisted world from feature 003 already stores a long description for every game object, but until now players have had no way to see it — the room view (FR-005 in 003) lists objects with their short descriptions only. Until this story ships, the long description data is invisible to players, and the player has no way to "look closer" at anything in the world. Every subsequent story in this feature depends on the basic `look <target>` command shape introduced here.

**Independent Test**: Given a player in a room containing a brass lantern whose long description is "A tarnished brass oil lantern, its wick blackened but its reservoir still half-full of pungent oil.", when the player submits `look brass lantern`, then the log appends a detail entry containing that long description (or a clearly recognizable formatting of it). Repeat with at least one phrasing the fast parser would reject — `examine the brass lantern` — and verify the same outcome via the AI fallback from feature 005.

**Acceptance Scenarios**:

1. **Given** a player in a room that contains a brass lantern, **When** they submit `look brass lantern`, **Then** the narrative log appends a detail entry showing the lantern's long description and the object remains in the room (no take, no state change).
2. **Given** a player in a room that contains a brass lantern, **When** they submit a natural-language variant such as `examine the lantern`, `inspect the brass lantern`, or `study the lantern`, **Then** the same detail entry is appended via the AI fallback — i.e., the resolver from feature 005 now treats `examine`/`inspect`/`study` as valid mappings to the look-at-target action rather than refusing them.
3. **Given** a player in a room containing two objects with distinct names (a brass lantern and a leather journal), **When** they submit `look journal`, **Then** the detail entry shows the journal's long description (not the lantern's).
4. **Given** a player in a room, **When** they submit `look` with no target, **Then** the existing room view (from feature 003) is rendered — the no-target form is unchanged by this feature.

---

### User Story 2 - Examine an Object in the Player's Inventory (Priority: P1)

A player has picked up an object — say, that brass lantern — and is now in a different room. They want to re-read its long description without having to drop it back into a room first. They submit `look brass lantern` (or `examine my lantern`, etc.) and the narrative log appends the same kind of detail entry they would have seen while the lantern was on the mantel. The lantern stays in their inventory; examination does not move it, change its state, or notify other players.

**Why this priority**: Carried objects are the other half of the persisted world's object location model (FR-021 in 003 — "objects exist in a room OR in a player's inventory, never both"). If `look <target>` only worked on room objects, the player would have to drop an object to examine it, which would be a confusing inversion of the player's intuition. The cost of supporting inventory lookup alongside room lookup is small (the resolution logic merely searches both locations), and the player-experience gain is large.

**Independent Test**: Given a player carrying a brass lantern (taken in a previous step, verifiable via the Inventory HUD card and the `inventory` command from 003), when they submit `look brass lantern` while in a room that does NOT contain a brass lantern, then the detail entry for the lantern is still rendered using the lantern's long description — the resolver finds the object in the player's inventory.

**Acceptance Scenarios**:

1. **Given** a player carrying a brass lantern and standing in a room that contains no brass lantern, **When** they submit `look brass lantern`, **Then** the log appends the lantern's detail entry (the inventory copy is found).
2. **Given** a player carrying a brass lantern and standing in a room that ALSO contains a different brass lantern, **When** they submit `look brass lantern`, **Then** the system resolves the reference to one of them per a documented preference (see FR-006a below) and renders that one's long description.
3. **Given** a player carrying a journal, **When** they submit a natural-language variant such as `look at my journal` or `examine the journal in my pocket`, **Then** the journal's detail entry is rendered via the AI fallback.

---

### User Story 3 - Examine Another Player in the Current Room (Priority: P2)

A player notices another player listed in the room view — say, Alice — and wants to look at her. They submit `look alice` (or `examine alice`, `look at alice`, etc.) and the log appends a detail entry that reads `Alice is a player.` The entry is intentionally minimal in this feature — richer player descriptions (appearance, equipped items, status, etc.) are deferred to later features as those data fields come online — but the command path is wired up end-to-end so that future enrichments slot in without re-architecting.

**Why this priority**: Other-player examination is functionally distinct from object examination — it targets a different entity type and has a different (minimal) rendering contract — and the user explicitly called it out in the feature description. It is P2 rather than P1 because it delivers strictly less information than object examination in this feature's scope (one line of placeholder text vs. a full long description), and the engine wiring is the same as for objects (lookup → render). Shipping it together with the object cases keeps the player's mental model consistent ("look at anything in the room") and avoids a surprise refusal when a player tries the obvious thing.

**Independent Test**: Given two authenticated players Alice and Bob in the same room (verifiable via the room's `look` output listing both), when Bob submits `look alice`, then Bob's log appends a detail entry whose body is `Alice is a player.` and Alice receives no notification or witness entry (examining a player is a passive read, not a world event).

**Acceptance Scenarios**:

1. **Given** Alice and Bob are both in the same room, **When** Bob submits `look alice`, **Then** Bob's log appends a detail entry containing exactly `Alice is a player.` (case of Alice's display name preserved).
2. **Given** Alice and Bob are both in the same room, **When** Bob submits `look Alice` (uppercase) or `LOOK ALICE`, **Then** the same detail entry is rendered — player-name matching is case-insensitive (consistent with the `tell` / `whisper` recipient resolution from feature 004).
3. **Given** Alice and Bob are in different rooms, **When** Bob submits `look alice`, **Then** the log appends a refusal entry indicating Alice isn't visible to Bob (same shape of refusal as for an object that isn't present — see FR-009).
4. **Given** Alice has logged out (her connection has dropped — see feature 003a edge-case fixes), **When** Bob submits `look alice` in the room where Alice was last seen, **Then** Alice is treated as absent (consistent with feature 003a's rule that offline players are filtered from the HUD and from `look` room output) and Bob's log appends a refusal entry.
5. **Given** a player submits `look <their own name>`, **Then** the same detail entry shape is rendered as for any other player (`<self-name> is a player.`). Players can examine themselves.

---

### Edge Cases

- **Target not present anywhere visible to the player** (not in the room, not in inventory, not a player in the room): the log appends a refusal entry using the same "you don't see that here" pattern that take/drop use today (FR-019 / FR-020 in 003 — preserve the existing world-state refusal language so the player gets a uniform "target not found" experience across all targeting commands).
- **Ambiguous reference** (e.g., `look lantern` when the room contains a brass lantern AND the player carries a brass lantern; or two distinct lanterns of different materials in the same room): the system resolves per a documented preference (see FR-006a below) and renders one specific target's detail entry. If even that preference doesn't yield a single match (e.g., two identically named objects in the same location), the log appends a refusal entry asking the player to be more specific.
- **Fixed (non-takeable) objects**: are still examinable. The "fixed" flag from 003 governs take, not look. A statue bolted to the floor still has a long description and can be examined.
- **Self-examination**: `look <self-name>` or `look me` / `look self` resolves to the player examining themselves, producing the same `<name> is a player.` entry as for other players.
- **Pronouns / context-dependent references**: matching feature 005's stance, the resolver does not maintain conversational state. `look it` resolves only if the visible scope contains a single unambiguous candidate; otherwise it refuses.
- **Whitespace / casing / partial matches**: target matching MUST tolerate the same variations the take/drop / `tell` recipient commands tolerate today (case-insensitive, trim whitespace, allow substring matches when unambiguous — consistent with feature 003 / 004 behavior).
- **Target longer than 500 characters**: capped to the same input length used by communication verbs and the LLM resolver (FR-017 in 005); over-cap input is refused before any resolution happens.
- **Examining an object does NOT emit a witness entry**: examination is a private read, unlike take/drop/arrival/departure which emit witness entries (FR-025..FR-030 in 003). Other players in the room are not notified when someone examines an object or a player.

## Requirements *(mandatory)*

### Functional Requirements

**Command shape**:

- **FR-001**: The system MUST extend the existing `look` command (from feature 003) to accept an optional target argument. `look` with no argument MUST continue to render the current room (existing behavior, unchanged). `look <target>` MUST render a detail entry for the named target.
- **FR-002**: The set of natural-language variants the AI resolver (feature 005) maps to `look <target>` MUST include at minimum `examine`, `inspect`, `study`, `read`, and `look at`, plus reasonable English paraphrases (e.g., `take a closer look at`, `check out the`, `what does the X look like`). This explicitly reverses FR-007a in feature 005, which previously required the resolver to REFUSE these phrasings — after this feature ships, they MUST resolve to the look-at-target action.
- **FR-003**: The player's narrative log MUST distinguish a target-detail entry from a room-view entry visually or structurally, so the player can tell at a glance whether the most recent log block describes the whole room or a single examined target.

**Target resolution**:

- **FR-004**: The set of examinable targets visible to a player MUST be (a) game objects currently located in the same room as the player, (b) game objects currently located in the player's own inventory, and (c) players currently present in the same room as the player (including the player themselves).
- **FR-005**: Target name matching MUST be case-insensitive and MUST allow unambiguous substring / partial-name matching consistent with how take/drop and `tell` / `whisper` recipient resolution behave today.
- **FR-006**: When multiple visible targets match a given input, the system MUST apply a deterministic disambiguation preference and render exactly one target's detail entry, or refuse with a clarification prompt if even that preference yields no single match.
- **FR-006a**: The disambiguation preference order MUST be: (1) exact case-insensitive name match wins over partial match; (2) if multiple exact matches still exist, an object in the player's inventory wins over an object in the room (the player's "owned" copy is the more specific reference); (3) if multiple exact matches still exist within the same scope, the system MUST refuse with a clarification prompt rather than guess. Player names participate in step 1 alongside object names but never tie with object names — a player named "Lantern" examined via `look lantern` resolves to the player only if no object literally named "lantern" is visible; if both exist, the system refuses with a clarification prompt because they are not the same kind of target.
- **FR-007**: Targets that are not visible to the player (objects in other rooms, objects carried by other players, players in other rooms, players who are offline per feature 003a) MUST NOT be examinable. Attempting to examine such a target MUST surface a refusal in the same shape as the "you don't see that here" refusal for take/drop.

**Render contract**:

- **FR-008**: When the target is a game object, the detail entry MUST display the object's long description (the field already persisted on Game Object per FR-022 in feature 003). The object's name SHOULD be shown alongside the long description so the player can confirm which object was matched.
- **FR-009**: When the target is a player, the detail entry MUST display exactly the placeholder text `<display-name> is a player.`, preserving the case of the matched player's display name. This text is intentionally minimal — future features will enrich it as additional player attributes (appearance, equipped items, status effects, etc.) come online. The render contract MUST be structured so those future additions extend, rather than replace, the placeholder.
- **FR-010**: Examination MUST NOT change the world state: no object moves, no player is notified, no event is broadcast, no witness entry appears for any other player. The examined target is purely a read.
- **FR-011**: The same fast-vs-AI routing rules established in feature 005 apply: a canonical `look <target>` invocation MUST resolve via the fast parser with no AI cost; only natural-language phrasings that the fast parser rejects MUST fall through to the AI resolver. A fast-parsed `look <target>` whose target name does NOT exact-match anything visible MUST follow FR-001a from feature 005a — i.e., the player's literal input falls through to the AI resolver, which can map a loose noun phrase against actual visible targets.

**Refusal**:

- **FR-012**: When the target cannot be resolved at all (no visible object or player matches, even loosely), the system MUST append a refusal entry to the player's log using the existing "you don't see that here" pattern. The session MUST remain otherwise unchanged.
- **FR-013**: When the AI resolver from feature 005 selects look-at-target with a target that does not resolve in the player's visible scope, the existing FR-001a fallback loop guard MUST hold — no infinite fallback. The player sees a single refusal.

### Key Entities

- **Examinable Target**: One of three distinct entity types from the player's point of view — a Game Object in the room, a Game Object in the player's inventory, or a Player in the room (including self). The resolver returns one of these or refuses.
- **Target Reference**: A noun phrase supplied by the player (e.g., `brass lantern`, `the lantern`, `alice`, `my journal`) that the system resolves against the visible scope using the rules in FR-005 / FR-006 / FR-006a.
- **Detail Entry**: A new narrative-log entry type appended to the player's log when `look <target>` resolves successfully. Its body is either the target object's long description (for objects) or the placeholder line `<name> is a player.` (for players). Distinct from a Room Entry (the existing `look`-with-no-target output) per FR-003.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of game objects in the seeded starter map (introduced in feature 003) become examinable from at least one location (in the room where they spawn, and in any player's inventory after a `take`), with every examination rendering the object's persisted long description.
- **SC-002**: 95% of natural-language phrasings that mean "examine X" (across `examine`, `inspect`, `study`, `read`, `look at`, and common English paraphrases of those) correctly resolve to a look-at-target detail entry on first attempt. Measured against a curated test set of at least 30 inputs covering objects in rooms, objects in inventories, and players.
- **SC-003**: Canonical `look <target>` commands resolve in under 50 milliseconds 99% of the time. Adding the target argument to `look` MUST NOT impose any measurable latency on the no-target form (which continues to render the room view).
- **SC-004**: 100% of attempts to examine a target outside the player's visible scope (other rooms, other players' inventories, offline players) produce a refusal entry — the system never reveals the existence, name, or description of an out-of-scope target.
- **SC-005**: 100% of look-at-target invocations emit zero witness entries to other players in the room — examination is observably private (no broadcast, no log entry on any other session) when verified by parallel sessions in the same room.
- **SC-006**: After this feature ships, the regression suite confirms that the previously-required refusal behavior for `examine` / `inspect` / `study` (per FR-007a in feature 005) is reversed for these specific verbs — those phrasings now resolve to look-at-target actions, not refusals.

## Assumptions

- The persisted Game Object's "long description" field (FR-022 in feature 003) is already populated for every seeded object and is the canonical source for object detail rendering. No new fields are added by this feature.
- The AI resolver from feature 005 is the route for natural-language phrasings (`examine X`, `inspect X`, `study X`, etc.); its tool definitions will be updated to include a look-at-target tool / argument, and its system prompt and few-shot examples will reflect the new mapping. This feature's spec assumes that update is part of the implementation scope.
- The placeholder text for examining a player (`<display-name> is a player.`) is intentional scaffolding. Future features (player appearance, equipped items, status effects, etc.) will progressively enrich this entry. The render contract is designed to extend, not replace.
- Examination is read-only and produces no world events. There is no event-store entry, no Commanded command, no PubSub broadcast — purely a local query against the persisted world plus a render to the examining player's log.
- Case-insensitive substring matching for targets follows the same conventions as the existing take/drop and `tell` / `whisper` commands. If those commands change their matching semantics in a future feature, this feature's behavior follows.
- Offline-player handling (a player whose websocket has disconnected) follows feature 003a — offline players are not visible to `look` (room view) and are therefore not examinable via this feature either. No special-case logic is added here.
- The 500-character input length cap from feature 004 / 005 (FR-017) continues to apply to all player input, including the target argument to `look`.
- English-language input only for v1, matching feature 005's scope.
- Desktop web only, matching the scope of all prior features (001–005).
- Multi-step / chained intent ("look at the lantern and then take it") remains out of scope per feature 005's FR-010 — the resolver refuses chained intent regardless of whether `look <target>` is one of the steps.
