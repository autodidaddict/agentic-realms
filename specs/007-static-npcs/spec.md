# Feature Specification: Static NPCs

**Feature Branch**: `007-static-npcs`
**Created**: 2026-05-23
**Status**: Draft
**Input**: User description: "static NPCs - NPCs are now a first class citizen in the game. They can be spawned into rooms and only into rooms. When an NPC enters a room, the occupants of that room receive a \"(name) arrives.\" message. In this feature, NPCs cannot move, cannot speak, cannot participate in combat, or do anything else other than exist. NPCs can be examined through the same means that a player might examine other players or objects. NPCs cannot be picked up and so should have the same type of flag as other \"un-gettable\" objects. An NPC's long description is sent to a player who examines that NPC."

## Clarifications

### Session 2026-05-23

- Q: Is NPC spawning a seed-time-only operation in this feature, or does it also include a runtime admin/scripted path? → A: Seed-time only, but the arrival-witness pipeline (FR-011/012/013/014) IS implemented and exercised by the seed-time spawn event so it is proven for future features that may introduce runtime spawning.
- Q: Can NPCs be removed from the world in this feature, and if so does that emit a departure witness entry? → A: No runtime removal path is exposed. The world-reset/re-seed path MAY rewrite the persisted world wholesale (including removing or replacing existing NPCs), but NO departure witness entry is emitted in this feature — the corrected room state is discoverable via the room view on the next `look`.
- Q: What is the uniqueness constraint on NPC display names? → A: Display names MUST be unique within a single room. NPCs in different rooms MAY share a display name (e.g., two innkeepers both named "Garrick" in different taverns is valid).
- Q: How are NPCs visually distinguished from players and objects in the room view? → A: Render NPCs in their own labeled section in the room view, parallel to the existing sections for objects and other players. The section label is "Also here".

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See an NPC in a Room (Priority: P1)

A player walks into a room (or is already standing in one) and the room contains a non-player character — say, an old innkeeper named Garrick. When the player issues `look` (or it is auto-rendered on arrival via the existing room view from feature 003), the room entry lists Garrick alongside any objects and other players present in that room. Garrick is visible as a distinct entity — clearly an NPC, not a player and not an object — so the player can tell at a glance that there is "someone" there worth interacting with later, even though no interaction beyond examination is wired up yet in this feature.

**Why this priority**: This is the foundational payoff of the feature. Until an NPC is visible in the room view, the player has no way to know an NPC exists at all — every other story (examining it, arrival messages, ungettability) depends on the player first being aware that NPCs occupy rooms. The existing room renderer (FR-005 in feature 003) already lists objects and other players, so this story is fundamentally an extension of that listing to a new entity type. Without this story, NPCs are invisible scaffolding; with it, they are first-class inhabitants of the world.

**Independent Test**: Seed the world such that the starter room contains exactly one NPC named "Garrick the Innkeeper" with a known long description, then log in as a fresh player and observe the room view rendered on first arrival. The room entry MUST list Garrick as an occupant of the room in a section/labeling visually distinct from "other players" and from "objects". Repeat with a room containing zero NPCs and verify no NPC section appears for that room.

**Acceptance Scenarios**:

1. **Given** a room that contains one NPC (Garrick) and no other occupants, **When** a player in that room issues `look`, **Then** the room entry includes an "Also here" section listing Garrick, separate from the existing sections for objects and other players.
2. **Given** a room that contains Garrick the Innkeeper AND a player named Alice AND a brass lantern, **When** a second player Bob in that room issues `look`, **Then** the room entry contains three distinct sections — the existing "other players" listing showing Alice, the existing "objects" listing showing the brass lantern, and the new "Also here" section showing Garrick — and the three entity types are clearly distinguishable in the rendered output.
3. **Given** a room that contains no NPCs, **When** a player in that room issues `look`, **Then** the room entry contains no "Also here" section at all (existing behavior for empty categories — consistent with how the room view omits an "objects" line when a room has no objects).
4. **Given** the seeded starter map after this feature ships, **When** the world is initialized, **Then** at least one room in the starter map contains at least one NPC so the feature is demonstrable from a fresh login without authoring new content.

---

### User Story 2 - Examine an NPC (Priority: P1)

A player sees an NPC listed in their current room — Garrick the Innkeeper — and wants to know more about him. They submit `look garrick` (or `examine garrick`, `inspect the innkeeper`, or any natural-language variant the AI resolver from feature 005 accepts per feature 006). The narrative log appends a detail entry containing Garrick's long description — the same kind of detail entry that examining a game object produces (feature 006). The NPC itself is unchanged — examination is read-only — and no other player in the room is notified.

**Why this priority**: This is the second half of the feature's core payoff. Once NPCs are visible in the room (Story 1), the immediate player intuition is "I want to look closer." Feature 006 already established `look <target>` as the universal examination verb for objects and players; this story extends that verb's resolver to also match NPC names. Until this ships, the long description data on the NPC entity is invisible to players — an exact parallel to the situation feature 006 fixed for game objects. P1 because the user's feature description explicitly calls examination out, and because it is the only player-facing interaction NPCs support in this feature.

**Independent Test**: Given a player in a room containing an NPC named "Garrick the Innkeeper" whose long description is "A wiry man in a stained apron, his eyes sharp despite the late hour. He polishes a tankard that already looks clean.", when the player submits `look garrick`, then the log appends a detail entry containing that long description. Repeat with the natural-language variant `examine the innkeeper` and verify the same detail entry is rendered via the AI fallback from feature 005 (i.e., the resolver now treats NPC names and descriptive references to NPCs as valid look-at-target inputs).

**Acceptance Scenarios**:

1. **Given** a player in a room that contains the NPC Garrick the Innkeeper, **When** they submit `look garrick`, **Then** the log appends a detail entry showing Garrick's long description (the NPC's full long description, identical in render contract to an object's long description per FR-008 in feature 006).
2. **Given** a player in a room that contains Garrick, **When** they submit a natural-language variant such as `examine the innkeeper`, `inspect garrick`, `look at the old man`, or `study the innkeeper`, **Then** the same detail entry is rendered via the AI fallback — the resolver now treats NPC names and descriptive references as valid look-at-target inputs.
3. **Given** a player in a room that contains both Garrick (an NPC) and a player named Alice, **When** they submit `look garrick`, **Then** the detail entry shows Garrick's NPC long description, not Alice's player placeholder (FR-009 in feature 006).
4. **Given** a player in a room that contains both Garrick AND a player who happens to also be named Garrick (or some other NPC and player with overlapping/colliding names), **When** they submit `look garrick`, **Then** the system applies a deterministic disambiguation rule and renders exactly one detail entry, or refuses with a clarification prompt — never silently picks the "wrong" one (see FR-008 below).
5. **Given** a player in a room that contains Garrick, **When** any player in that room examines Garrick, **Then** no other player (including Garrick himself, if such a thing were addressable) receives a witness entry. Examination remains private, identical to feature 006's contract for examining objects and players.

---

### User Story 3 - Witness an NPC Arriving in a Room (Priority: P2)

The world's seed-time spawn operation places an NPC into a room. If that spawn happens to fire while live player sessions are present in the destination room (e.g., a re-seed or world-reset event that runs while testers are connected), the players in that room receive a passive system log entry — `Garrick the Innkeeper arrives.` — at the moment the NPC appears, with no input on their part. This mirrors the existing player-arrival witness entry from feature 003 (FR-027): when a player walks into a room, the existing occupants see `Alice arrives.` (or `Alice arrives from the south.` when direction is known). NPCs spawning into rooms produce the directionless form because NPCs in this feature do not move — they only appear, with no source room or compass direction to attribute the arrival to.

**Why this priority**: The user's feature description explicitly calls out this arrival message, and the broadcast path needs to exist now so that future features (runtime spawn, NPC movement, scripted behaviors) can light it up without re-architecture. It is P2 rather than P1 because, in this feature, seed-time is the only spawn trigger (clarified 2026-05-23) and typical end-user gameplay will not witness an arrival event — they discover NPCs already in place via the room view (Story 1). The arrival pipeline is implemented and exercised by the seed-time spawn event so the contract is proven; it just happens to fire only in seed/reset scenarios in this feature.

**Independent Test**: Have two players Alice and Bob log in to a room that contains no NPCs. While both players' sessions are connected and idle, trigger a seed-time spawn (or world-reset spawn) that places Garrick the Innkeeper into that exact room. Both Alice's and Bob's narrative logs MUST receive a system entry reading `Garrick the Innkeeper arrives.` (case of the NPC's display name preserved) at the moment of the spawn, without either player issuing any command. A subsequent `look` by either player MUST then list Garrick as an occupant of the room (consistent with Story 1).

**Acceptance Scenarios**:

1. **Given** a room with two live player sessions (Alice and Bob) and zero NPCs, **When** Garrick is spawned into that room, **Then** both Alice's and Bob's narrative logs append a system entry `Garrick the Innkeeper arrives.` at the moment of the spawn, and a subsequent `look` lists Garrick as a present NPC.
2. **Given** a room with zero live players, **When** Garrick is spawned into that room, **Then** no log entries are produced (there is no one to witness), but the world state reflects Garrick's presence so that any later-arriving player sees him via `look` (Story 1).
3. **Given** an NPC spawn into a room with players present, **When** the arrival event is delivered, **Then** the entry shape MUST match feature 003's FR-027 directionless arrival format (`<name> arrives.`) — NOT the `arrives from the south` variant, because NPCs in this feature have no source room.
4. **Given** a player has multiple concurrent sessions open and is in the destination room (consistent with feature 003's multi-session model), **When** an NPC arrives in that room, **Then** every one of the player's sessions in that room receives the arrival entry (consistent with FR-035 from feature 003).

---

### User Story 4 - Try to Take an NPC (Priority: P3)

A player, perhaps testing the limits of the world or just being curious, attempts to `take garrick` while standing in the same room as Garrick the Innkeeper. The system refuses, leaving the world state unchanged and appending a system message that NPCs cannot be picked up — using the same refusal shape as attempting to take a "fixed" (un-gettable) object per feature 003. Garrick remains in the room, the player's inventory is unchanged, and no witness entry is produced for other players in the room (because the action did not succeed and produced no world change).

**Why this priority**: The user's feature description explicitly required NPCs to be un-gettable with "the same type of flag as other un-gettable objects" — meaning the existing "fixed" flag mechanism from feature 003 should govern this refusal, not a new NPC-specific code path. This is P3 rather than P1/P2 because (a) it is a refusal/edge-case behavior rather than a payoff behavior — the player gets nothing positive out of it; (b) the existing `take` command already has the refusal infrastructure (FR-010 in feature 003 refuses fixed objects); and (c) the player intuition for "you can't take a person" is strong enough that the absence of any refusal at all would just be a bug, not a feature gap. We list it explicitly so the contract is clear and so the engineering team knows to wire NPC entities through the same un-gettable code path as fixed objects.

**Independent Test**: Place a player in a room that contains the NPC Garrick. Have the player submit `take garrick` (and also a natural-language variant such as `pick up the innkeeper`). In both cases, the log MUST append a refusal entry consistent with the existing fixed-object refusal language from feature 003 (FR-010), Garrick MUST remain in the room, the player's inventory MUST be unchanged, and no other player in the room MUST receive any witness entry for the attempt.

**Acceptance Scenarios**:

1. **Given** a player in a room with the NPC Garrick, **When** they submit `take garrick`, **Then** the world is unchanged (Garrick remains in the room, inventory empty) and the log appends a refusal entry of the same shape as the existing fixed-object refusal (FR-010 in feature 003).
2. **Given** a player in a room with the NPC Garrick, **When** they submit `pick up the innkeeper` or another natural-language variant of "take," **Then** the AI resolver routes it to the take action, which produces the same refusal as the canonical form.
3. **Given** a player in a room with the NPC Garrick, **When** the player attempts to take Garrick and the attempt is refused, **Then** no other player in the room receives a witness entry (consistent with feature 003 — only successful state changes emit witness entries).

---

### Edge Cases

- **NPC name collides with a player or object in the same room**: handled by the existing examination disambiguation rules from feature 006 (FR-006 / FR-006a). NPCs participate in the same name-matching scope as players and objects; cross-type collisions (e.g., an NPC named "Garrick" and a player named "Garrick" in the same room) refuse with a clarification prompt rather than guess. See FR-008 below.
- **NPC examined when not in the same room as the player**: NPCs only exist in rooms, never in inventories, so the only place a player can examine an NPC is from inside the room containing that NPC. Examining an NPC in another room follows feature 006's FR-007 — refused with a "you don't see that here" entry. NPCs are never in the "visible inventory" scope.
- **NPC spawned into a room that does not exist**: the spawn operation is rejected at the seeding/admin layer; no log entries are produced and no partial state is persisted. This is an authoring/seed-time concern, not a player-facing edge case.
- **NPC's long description is empty or missing**: NPCs MUST always have a long description populated (parallel to the requirement on game objects in feature 003). Seeding without a long description is a seeding error, not a runtime branch; the entity model requires the field.
- **Player offline during NPC arrival**: a player whose session has dropped (per feature 003a) is not in the room for delivery purposes — they receive no witness entry. When they reconnect, the room view (Story 1) reflects the current occupants including the NPC, which is sufficient signal that the NPC is present. There is no replay of missed arrival entries (consistent with feature 003 — witness entries are live, not historical).
- **Concurrent spawn while a player is examining**: examination is a read against the persisted world; if an NPC is spawned into the room while a player is mid-input, the existing event-projection model from feature 003 (FR-030) handles ordering — the player's `look <something else>` produces its result based on the world state at processing time, and the arrival entry interleaves with the player's command results in log order.
- **`look` with no target in a room containing only NPCs**: produces the standard room view (feature 003 FR-005) with the NPC listed — same behavior as a room containing only objects or only players. The no-target form of `look` is unaffected.
- **NPC examined via self-reference variants (`look me`, `look self`)**: NPCs are NOT the player, so these variants continue to resolve to the player themselves (per feature 006). NPCs do not participate in self-examination grammar.
- **Take attempt against an NPC by ambiguous name** (e.g., `take garrick` when both an NPC Garrick and a player Garrick are in the room): the disambiguation rules from feature 003's existing take command (which already handles ambiguous object names in a room) apply; if the resolution lands on the NPC, the refusal from Story 4 fires. If the resolution lands on a player, the existing take refusal for "you cannot take a person" applies (existing behavior, unchanged). Either way the attempt fails.

## Requirements *(mandatory)*

### Functional Requirements

**Entity model**:

- **FR-001**: System MUST introduce a new first-class entity type called NPC. An NPC has at minimum a stable identifier, a display name, a short description (used when the NPC is listed in a room view), and a long description (used when the NPC is examined). The long description field MUST be populated for every NPC; an NPC with a missing or empty long description is a seeding/authoring error and MUST NOT be permitted in the persisted world.
- **FR-001a**: NPC display names MUST be unique within a single room — no two NPCs in the same room MAY share a display name. Display names MAY be reused across different rooms (e.g., two innkeepers both named "Garrick" in different taverns is valid). The uniqueness rule MUST be enforced at the seeding/spawn layer; the persisted world MUST NOT accept an NPC into a room that already contains another NPC with the same display name. This is distinct from cross-type collisions (NPC vs player vs object), which continue to be handled by the FR-006 / FR-008 disambiguation rules at examination time.
- **FR-002**: NPCs MUST be persisted as part of the world state alongside rooms, game objects, and players (feature 003's persisted world). At any moment an NPC has exactly one location: a specific room. NPCs MUST NOT be locatable in a player's inventory, in another NPC, or "nowhere"; if no valid room location exists, the NPC MUST NOT exist in persisted state.
- **FR-003**: NPCs MUST be flagged un-gettable using the same mechanism as the "fixed" flag on game objects (feature 003 FR-009 / FR-010). The intent is that no new un-gettable code path is introduced — NPCs are routed through whatever mechanism already refuses takes on fixed objects, with the only behavior difference being the entity type involved.

**Room rendering**:

- **FR-004**: The existing room view rendered by `look` (feature 003 FR-005) MUST be extended so that, in addition to listing objects and other players, it also lists NPCs currently present in the room. NPCs MUST be listed in their own labeled section in the room view, parallel to the existing sections for objects and other players. The section label MUST be the literal string `Also here` (case preserved). The "Also here" section MUST appear only when at least one NPC is present in the room — when a room contains zero NPCs, the room view MUST NOT include an empty "Also here" section (consistent with how the existing view handles empty object and player categories).
- **FR-005**: The "Also here" section MUST display each NPC by its display name. The NPC's short description MAY also be shown alongside the display name in the room view at the team's discretion, but the long description MUST NOT appear in the room view — long descriptions are reserved for the examination path (FR-006), matching how feature 003 / 006 separate game-object short vs. long descriptions.

**Examination**:

- **FR-006**: When a player submits `look <target>` (or any natural-language variant accepted by the AI resolver per feature 005 / 006) and the target resolves to an NPC in the player's current room, the system MUST append a detail entry to the player's narrative log containing the NPC's long description. The detail entry MUST be of the same render contract as the object detail entry from feature 006 (FR-008) — a long-description body with the NPC's name shown alongside so the player can confirm which target was matched.
- **FR-007**: The set of examinable targets visible to a player MUST be extended to include NPCs in the player's current room, in addition to the three categories already defined in feature 006 (FR-004): room objects, inventory objects, and players in the room. NPCs in OTHER rooms MUST NOT be examinable; attempting to examine such a target follows feature 006's FR-007 refusal path. NPCs MUST NOT be examinable as inventory targets — NPCs cannot exist in inventories (FR-002).
- **FR-008**: NPC name matching MUST follow the same rules as object and player name matching established in feature 006 (FR-005, FR-006, FR-006a) — case-insensitive, unambiguous substring matching, deterministic disambiguation, with cross-type ambiguity (e.g., NPC name colliding with player name or object name in the same visible scope) producing a clarification refusal rather than a silent guess.
- **FR-009**: The AI resolver from feature 005 MUST be updated so that natural-language references to NPCs (by display name, by role nouns from their short description, or by descriptive paraphrase such as "the old man," "the innkeeper") are routed to the look-at-target action with the NPC as the resolved target. This is an extension of the resolver updates feature 006 made to support `examine` / `inspect` / `study`; NPCs simply enter the resolution pool of valid look-at-target outputs.
- **FR-010**: Examining an NPC MUST NOT change the world state: no NPC moves, no player is notified, no event is broadcast, no witness entry appears for any other player in the room. Examination remains a private read, identical to feature 006's FR-010.

**Arrival witness**:

- **FR-011**: When an NPC is spawned into a room that has one or more live player sessions present, the system MUST append a system entry to the narrative log of every player session currently in that room, of the form `<NPC display name> arrives.` (case of the NPC's display name preserved). The entry MUST be delivered live (at the moment of the spawn, not deferred to the player's next command), consistent with feature 003's FR-030.
- **FR-012**: The NPC arrival entry MUST use the directionless form of the existing player-arrival entry from feature 003 (FR-027) — `<name> arrives.` — NOT the `<name> arrives from the south.` form. NPCs in this feature do not move and have no source room, so no direction context exists.
- **FR-013**: When an NPC is spawned into a room with zero live player sessions, no log entries MUST be produced; the world state still reflects the NPC's presence so that any later-arriving player sees the NPC via the room view (FR-004). There MUST NOT be a replay of missed arrival entries when a player reconnects to that room (consistent with feature 003's live-witness model).
- **FR-014**: Arrival entries MUST be delivered to every concurrent session a player has in the destination room (consistent with feature 003's FR-035 multi-session delivery rules).

**Refusal (take)**:

- **FR-015**: Attempting to `take` an NPC (via the canonical command from feature 003 OR via any natural-language variant routed to the take action by the AI resolver from feature 005) MUST be refused. The refusal MUST follow the exact same code path and produce the same shape of refusal entry as the existing fixed-object refusal (feature 003 FR-010), driven by the un-gettable flag from FR-003 above. The system MUST NOT introduce a separate "you cannot take an NPC" refusal language unless the existing fixed-object refusal would already differentiate by entity type.
- **FR-016**: A refused take attempt against an NPC MUST NOT change world state and MUST NOT emit any witness entry to other players in the room (consistent with feature 003 — only successful state changes emit witness entries).

**Out of scope (this feature)**:

- **FR-017**: NPCs MUST NOT be able to move between rooms in this feature. There is no movement command path, no AI-driven movement, no scripted patrol, and no exit traversal applicable to NPCs.
- **FR-017a**: Runtime spawning (via an admin command, scripted hook, or any in-session trigger) MUST NOT be exposed in this feature. The only path that creates an NPC is the seed-time spawn operation that runs as part of world initialization or world reset. The arrival-witness pipeline from FR-011..FR-014 MUST still be fully implemented and exercised by seed-time spawn events that fire while live sessions are present, so the broadcast contract is proven for a future feature that introduces runtime spawning.
- **FR-017b**: Runtime NPC removal (despawn, kill, banish, etc.) MUST NOT be exposed in this feature. A world-reset / re-seed operation MAY rewrite the persisted world wholesale and in doing so MAY remove or replace existing NPCs as a side effect of that wholesale rewrite, but the system MUST NOT emit a departure witness entry of any form when an NPC ceases to exist. There is no `<name> leaves.` counterpart to the FR-011 arrival entry in this feature. Players in a room whose NPCs were removed by a reset discover the new state via the room view on their next `look` (FR-004), consistent with how feature 003 / 003a handles offline-player visibility transitions.
- **FR-018**: NPCs MUST NOT be able to speak, emote, whisper, tell, or otherwise participate in the player communication verbs introduced in feature 004. The communication verbs MUST continue to operate only against players (their existing recipient resolution scope is unchanged).
- **FR-019**: NPCs MUST NOT participate in combat. There is no combat system in this feature; combat (and any interaction beyond examination and ungettable refusal) is deferred to future features. If a future feature introduces combat verbs, NPCs MAY become valid targets at that time — but this feature establishes no combat affordance.

### Key Entities

- **NPC**: A persisted, room-bound, non-player character. Has a stable identifier, a display name, a short description (room-view rendering), a long description (examination rendering), and an un-gettable flag that reuses the same mechanism as the "fixed" flag on game objects. At any moment an NPC has exactly one room as its location and never appears in inventories or other locations.
- **NPC Arrival Event**: A world event emitted when an NPC enters a room. In this feature, the only generator of this event is the seeding/spawn mechanism (there is no movement). The event drives the witness entries described in FR-011 and is delivered to every live player session in the destination room.
- **Examinable Target (extended)**: The set defined in feature 006's data model, now extended to include NPCs in the player's current room. The render contract for an NPC target is "show the NPC's long description as the detail entry body, with the NPC's display name shown alongside" — identical in shape to the game-object render contract.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of NPCs present in a room appear in that room's `look` output under the "Also here" section, separate from the existing sections for other players and game objects. A reviewer scanning the room entry MUST be able to tell within one read which listed entities are NPCs (those under "Also here"), which are other players, and which are objects.
- **SC-002**: 100% of `look <NPC name>` invocations (canonical fast-parser form) where the named NPC is in the player's current room render a detail entry containing that NPC's full long description, with zero false refusals. Measured by submitting `look <name>` for every NPC in the seeded starter map.
- **SC-003**: 90% of natural-language variants meaning "examine this NPC" (covering display name references, role-noun references like "the innkeeper," and short-description paraphrases like "the old man behind the bar") correctly resolve to the matching NPC's detail entry on first attempt. Measured against a curated test set of at least 20 inputs across at least 3 distinct NPCs.
- **SC-004**: 100% of `take <NPC name>` attempts (canonical and natural-language variants) produce a refusal entry consistent with the fixed-object refusal pattern from feature 003, leave the NPC in the room, and emit zero witness entries to other players in the room.
- **SC-005**: 100% of NPC spawns into a room with N>=1 live player sessions produce arrival entries delivered live (before the next player command in any of those sessions) with body `<NPC display name> arrives.` to every one of those sessions. Verified by parallel-session integration tests covering 1, 2, and 3 sessions per player.
- **SC-006**: 0 cases in regression testing where an NPC is found located somewhere other than a room (no NPCs in inventories, no NPCs without a location, no NPCs duplicated across rooms). The persisted world's single-location invariant for NPCs holds under all seeding and spawning operations.
- **SC-007**: 0 cases where examining an NPC, attempting to take an NPC, or witnessing an NPC arrival produces a witness entry on a session OTHER than the intended recipients (i.e., no leakage across rooms; arrival entries delivered only to the destination room; examination producing zero witness entries anywhere).

## Assumptions

- The persisted world from feature 003 supports adding a new entity type alongside rooms, game objects, and players without re-architecting the storage model. NPCs are added as a parallel entity rather than as a subtype of game object or a subtype of player — the user's feature description explicitly calls them "a first class citizen."
- The "fixed" / un-gettable flag from feature 003 is implemented in a way that can be reused for a new entity type without forking the take-refusal code path. The implementation plan will confirm this; if reuse turns out to require trivial refactoring (e.g., the flag was object-only and needs to be lifted to a shared trait), that refactoring is in scope.
- The seeded starter map will be amended to include at least one NPC in at least one room so that the feature is demonstrable end-to-end from a fresh login. The choice of which room and which NPC is left to the implementation/content-authoring phase.
- The AI resolver from feature 005 / 006 can be extended to include NPC display names and role nouns in its candidate-target pool without re-architecture — i.e., the tool definition for look-at-target already accepts an arbitrary noun phrase and resolves it server-side against the visible scope. NPC names simply enter that scope.
- NPC arrivals are infrequent events (typically only at seed time, or rare admin-triggered spawns) — performance characteristics of arrival broadcast do not need to scale to player-movement-level event volume. The existing FR-030 live-witness delivery infrastructure from feature 003 handles them at the same fidelity as player arrivals.
- Player communication verbs from feature 004 (`say`, `emote`, `tell`, `whisper`) explicitly do NOT need to be aware of NPCs in this feature. NPCs do not speak and cannot be addressed as a `tell` / `whisper` recipient. The communication verbs' recipient resolution scope (other players only) is unchanged.
- Combat, NPC dialogue, NPC movement, NPC scripts/behaviors, and any "active" NPC behavior are explicitly out of scope and are deferred to future features. This feature establishes the entity, its visibility, its examination affordance, and its un-gettability — nothing more.
- The 500-character input cap from feature 004 / 005 continues to apply to all player input.
- Desktop web only, English-language input only, matching the scope of all prior features (001–006).
- Offline-player handling follows feature 003a — players whose sessions have dropped do not receive live NPC arrival entries and re-discover NPC presence via room view on reconnect. There is no replay queue.
