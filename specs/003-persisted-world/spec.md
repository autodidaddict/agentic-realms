# Feature Specification: Persisted Interactive World — Rooms, Objects & Inventory

**Feature Branch**: `003-persisted-world`
**Created**: 2026-05-18
**Status**: Draft
**Input**: User description: "Create the 003 feature as you described. This is the minimal viable persisted and interactive game world. It should have rooms, exits, and simple game objects that are DB-backed. It should contain a small starter map to illustrate the use of rooms, exits, objects, and inventory. Players should be able to see objects in their inventory, which is already represented in the player mode UI. They should be able to look at their current environment which will scroll description in the text log window. They should be able to take and drop objects. In this feature there are no triggers, no automated reactions from game entities. The persistence design will need to accommodate asking a room for its contents, asking a player for its contents, and obtaining the room in which a player resides. Implementation details for that will be left to the plan phase."

## Clarifications

### Session 2026-05-18

- Q: How is a concurrent `take` race resolved when two players in the same room try to take the same object at nearly the same time? → A: First-arrival wins; the losing player sees the standard FR-011 message ("no such object is here"). No distinct "someone else just took that" variant is added. Rationale: the planned use of an event-sourcing library (to be specified in the plan phase) gives the system global awareness that the object is no longer in the room when the losing command is processed, so the existing FR-011 path applies without modification.
- Q: When another player acts in the witness's current room, what does the witness see passively (before their next `look`)? → A: All observable events — take, drop, arrival, and departure — are pushed to every other player currently in the relevant room as system log entries at the moment the event occurs. Take/drop are pushed to the room where the object changes hands; departures are pushed to the origin room; arrivals are pushed to the destination room. The acting player does not receive a witness entry for their own action (they already get the actor-side confirmation or arrival entry). Rationale: this aligns with the event-sourcing approach planned for persistence — every world-changing command emits an event with room context, and same-room subscribers project it into their log.
- Q: How does the Inventory HUD card (originally mocked in feature 001 with equipped markers, carried/worn status, quantity badges, and a filter input) adapt to the simpler Game Object data this feature introduces? → A: Strip every UI affordance whose underlying data does not exist in this feature. The HUD card shows one tile per carried object with the object's name and short description only — no equipped marker, no carried/worn status badge, no quantity badge, no filter input. Rationale: rendering perpetual stub values ("Carried", quantity 1, etc.) promises functionality the system does not yet provide; the affordances can be reintroduced when equipment, stacks, or large inventories actually exist.
- Q: Should the seeded starter map allow asymmetric (one-way) exits between rooms, or restrict to bidirectional connections? → A: Every exit is uniformly one-way at the data-model level — each Exit belongs to a single source room and references a single target room. "Bidirectional" is a seed-authoring convention realized by storing two one-way exits, not a property of the Exit entity. For this feature's seed, every connection between rooms MUST be paired in both directions so no player can be trapped in a dead-end room. Automated detection of orphan or trap rooms (e.g., warning a wizard before saving) is deferred to the future wizard-authoring feature; in this feature the no-trap guarantee is enforced solely by seed-authoring discipline.
- Q: Can a single Player have multiple concurrent authenticated sessions (e.g., two browser tabs or laptop + phone), and if so how does state behave across them? → A: Multiple concurrent sessions per Player are permitted. All sessions for a Player share a single underlying player state (current room, inventory), so a command issued from any session mutates the same Player and the resulting world change is observable from every session on its next query or live update. Actor-side log entries (confirmations, arrivals, the `inventory` listing, and refusal/system messages produced by the command-handling FRs) appear only in the originating session — they are not echoed to the Player's other sessions. Witness entries from OTHER players' actions are delivered to every one of the Player's sessions that is currently in the relevant room. Witness entries for the Player's own actions remain undelivered to that Player per FR-029, regardless of session count.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Player Looks at Their Surroundings (Priority: P1)

An authenticated player enters the game (from the "Play" nav item) and arrives in a starting room. They type `look` (or click a `Look` suggestion chip) and the narrative log scrolls a fresh description of their current room: the room name, its description text, the available exits, and any objects or other players present. They can issue `look` again at any time and see the current state of that room, including objects that have been added or removed since their last look.

**Why this priority**: "Look" is the foundational read operation for any interactive world. Without it the player has no sense of place, no awareness of objects to interact with, and no way to discover exits. Every other interaction in this feature (and every future feature) depends on the player being able to perceive their environment from real data.

**Independent Test**: Can be fully tested by logging in, navigating to the Play view, issuing the `look` command, and verifying the log appends a room entry whose name, description, exits, and listed contents match the seeded starter map data for the player's current room.

**Acceptance Scenarios**:

1. **Given** a newly registered player with no prior game state, **When** they navigate to the Play view for the first time, **Then** they are placed in the designated starting room of the seeded starter map and the log shows an initial room description for that room.
2. **Given** an authenticated player in any room, **When** they submit `look`, **Then** the narrative log appends a room entry containing the room's name, description, a list of exits (with directions), a list of objects currently in the room, and a list of other players currently in the room.
3. **Given** a room that contains no objects and no other players, **When** the player issues `look`, **Then** the room entry renders with the name, description, and exits, and indicates that the room is otherwise empty (no objects, no other players).
4. **Given** an object that has been removed from a room since the player's last `look`, **When** the player issues `look` again, **Then** the room entry no longer lists that object.
5. **Given** a player who has returned to the home landing page and later clicks Play again, **When** the Play view re-loads, **Then** the player is restored to the room they last occupied (not reset to the starting room).

---

### User Story 2 - Player Moves Between Rooms (Priority: P1)

A player uses an exit listed in their current room to move to an adjacent room. They submit a movement command (e.g., `go north`, or a directional shortcut like `north` / `n`, or click the corresponding exit chip in the rendered room entry). The system updates which room the player is in and the log appends a fresh room entry for the room they arrived in. Movement only succeeds if the chosen direction matches a real exit from the current room.

**Why this priority**: Movement is what turns a single room into a "world." Without it the starter map is just one fixed location and the existence of multiple rooms and exits is unobservable to the player. Movement is also a prerequisite for demonstrating that objects belong to specific rooms (taking an object in room A, walking to room B, dropping it there).

**Independent Test**: Can be fully tested by issuing a movement command toward a valid exit and verifying both that the log shows an arrival entry for the destination room and that a subsequent `look` describes the destination room (not the origin room).

**Acceptance Scenarios**:

1. **Given** a player in a room with an exit to the north, **When** they submit `go north` (or `north` / `n`, or click the north exit chip), **Then** their current-room state is updated to the room on the other side of that exit and the log appends an arrival entry describing the new room.
2. **Given** a player in a room, **When** they submit a movement command for a direction that is not a listed exit from that room, **Then** their location does not change and the log appends a system message indicating there is no exit in that direction.
3. **Given** two rooms A and B connected by a bidirectional exit, **When** the player moves from A to B and then issues the reverse direction, **Then** they arrive back in room A.
4. **Given** a player has moved into a new room, **When** they immediately issue `look`, **Then** the rendered room entry corresponds to the new room's contents, not the room they left.

---

### User Story 3 - Player Takes and Drops Objects (Priority: P1)

A player sees an object listed in their current room (via the `look` output or the rendered room entry) and picks it up with `take <object>`. The object disappears from the room and now appears in their personal inventory. They can later issue `drop <object>` while in any room to remove the object from their inventory and place it in their current room, where it becomes visible to other players who `look` there. Some objects are designated as fixed (not takeable) and refuse to be picked up.

**Why this priority**: Take and drop are the minimum interactions that prove the world is *interactive*, not just readable. They are also what makes the inventory UI (already mocked in 001) meaningful — without take/drop the inventory has nothing real to display. Together with `look`, they form the smallest possible loop of "perceive → act → perceive change" that demonstrates real persistence.

**Independent Test**: Can be fully tested by entering a room containing a takeable object, issuing `take <object>`, opening the Inventory HUD card, verifying the object is listed there and no longer in the room (via a follow-up `look`); then issuing `drop <object>`, verifying it disappears from the inventory and reappears in the current room's contents.

**Acceptance Scenarios**:

1. **Given** a player in a room that contains a takeable object, **When** they submit `take <object name>`, **Then** the object is removed from the room's contents, added to the player's inventory, and the log appends a confirmation entry.
2. **Given** a player who has just taken an object, **When** they open the Inventory HUD card, **Then** the taken object appears in the inventory list with its name and description.
3. **Given** a player who has taken an object in room A, **When** they move to room B and submit `drop <object name>`, **Then** the object is removed from their inventory and added to room B's contents, and a subsequent `look` in room B includes the object.
4. **Given** a room object that is designated as fixed (not takeable), **When** the player issues `take <object name>` for it, **Then** the object remains in the room, the inventory is unchanged, and the log appends a system message indicating the object cannot be taken.
5. **Given** a player who does not carry a given object, **When** they issue `drop <object name>` for it, **Then** the world state is unchanged and the log appends a system message indicating they are not carrying that object.
6. **Given** a player in a room that does not contain a given object, **When** they issue `take <object name>` for it, **Then** the world state is unchanged and the log appends a system message indicating no such object is here.
7. **Given** two players in the same room, **When** player A takes an object and player B later issues `look` in that room, **Then** player B's room entry does not list the object (the object now belongs to player A's inventory).

---

### User Story 4 - Player Inspects Inventory (Priority: P2)

A player wants to see what they are carrying without opening the HUD modal. They submit `inventory` (or `inv` / `i`) and the log appends a system entry listing every object currently held, each with its name and short description. The same data also drives the existing Inventory HUD card so that the modal and the log entry always agree.

**Why this priority**: Inventory inspection is a quality-of-life command that keeps the player in the text-driven flow rather than forcing them to open a modal for every check. The HUD card already exists from 001 and must be wired to the same underlying data, so this story is mostly about command-side coverage and making the HUD reflect real state instead of mock state.

**Independent Test**: Can be fully tested by taking one or more objects, issuing `inventory`, and verifying the resulting log entry lists exactly those objects; independently open the Inventory HUD card and confirm it shows the identical list.

**Acceptance Scenarios**:

1. **Given** a player carrying at least one object, **When** they submit `inventory` (or `inv` / `i`), **Then** the log appends a system entry listing each carried object with its name and short description.
2. **Given** a player carrying no objects, **When** they submit `inventory`, **Then** the log appends a system entry indicating the inventory is empty.
3. **Given** a player who has just taken or dropped an object, **When** the Inventory HUD card is open (or re-opened), **Then** its listed contents match the result of issuing `inventory` at the same moment.

---

### User Story 5 - Seeded Starter Map Exists (Priority: P1)

The world has a small, hand-authored starter map that ships with the system so that any newly created player has somewhere to play. The map must exercise every capability in this feature: multiple rooms, multiple bidirectional exits (so movement and reversibility are both demonstrable), at least one room containing a takeable object, at least one fixed (non-takeable) object, and at least one room that is initially empty. The starter map is the ground truth for testing all other stories in this feature.

**Why this priority**: Without a seeded map there is nothing for any of the other commands to operate on. This is a P1 because every other story in this feature implicitly assumes it. Once seeded, the same data also stands in as a regression fixture for future features.

**Independent Test**: Can be fully tested by inspecting the persisted world state after seeding and verifying the map contains at least three connected rooms, at least one designated starting room, at least one takeable object placed in a room, at least one fixed object placed in a room, and at least one room with no objects.

**Acceptance Scenarios**:

1. **Given** a freshly installed system, **When** the seeding step is run, **Then** the world contains at least three rooms, all reachable from the designated starting room by traversing exits.
2. **Given** the seeded world, **When** any two adjacent rooms are inspected, **Then** the exit between them is traversable in both directions.
3. **Given** the seeded world, **When** room contents are inspected, **Then** at least one room contains a takeable object, at least one room contains a fixed object, and at least one room contains no objects.
4. **Given** a newly registered player who has never played, **When** they first reach the Play view, **Then** they are placed in the designated starting room without any manual setup.

---

### Edge Cases

- **Unknown command**: When the player submits a verb the system does not recognize (e.g., `dance`), the log appends a system message indicating the command is unknown. World state is unchanged.
- **Ambiguous object name**: When the player issues `take <name>` or `drop <name>` and more than one object in the relevant scope matches that name, the log appends a system message asking the player to be more specific. No object is taken or dropped. The seeded starter map MUST NOT introduce ambiguity; this case is defensive coverage only.
- **Case and whitespace**: Commands and object names are matched case-insensitively, with leading and trailing whitespace ignored, so `Take Letter`, `take  LETTER`, and `take letter` all behave the same.
- **Empty input**: Submitting an empty command (or only whitespace) does nothing — no log entry is added and no state changes.
- **Stale view after another player acts**: When another player takes or drops an object in the same room, the current player's already-rendered room entries are not retroactively rewritten. The next `look` reflects the new state.
- **Concurrent `take` race**: When two players in the same room submit `take <object>` for the same object at nearly the same time, the system serializes them: the first to be applied wins and the object enters their inventory; the losing player's command is processed as though the object is no longer in the room and produces the standard FR-011 "no such object is here" message. There is no distinct "someone else just took that" message.
- **Same Player in multiple tabs/devices**: A Player may open the game in multiple concurrent sessions. All sessions share the same current room and inventory. A command issued in one session produces its confirmation entry only in that session, but mutates state visible to all the Player's sessions on their next query or live update, and (where relevant) emits witness events that other players in the room receive. The Player's own other sessions do not receive a witness entry for the Player's own action.
- **Player whose last-known room was deleted**: If the room a player previously occupied no longer exists in the world (e.g., the seed was changed), the next time they reach the Play view they are placed in the designated starting room, and the log notes that their previous location is no longer reachable.
- **Account deletion (from 002)**: When a player's account is deleted, any objects they were carrying return to the world in the room where the player was located at the time of deletion. Objects are world resources and must not be destroyed alongside the player.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST persist rooms, exits between rooms, and game objects in durable storage that survives application restarts.
- **FR-002**: System MUST associate every authenticated player with exactly one current room at all times once they have entered the game.
- **FR-003**: System MUST place every newly registered player who enters the Play view for the first time into a single designated starting room defined by the seeded starter map.
- **FR-004**: System MUST restore a returning player to the room they last occupied when they re-enter the Play view, except when that room no longer exists (in which case FR-022 applies).
- **FR-005**: System MUST support a `look` command that appends a room entry to the player's narrative log describing the player's current room, including the room name, description, the list of exits (with directions), the list of objects currently in the room, and the list of other players currently in the room.
- **FR-006**: System MUST accept movement commands in the forms `go <direction>`, `<direction>` (e.g., `north`), and the single-letter shortcuts `n`, `s`, `e`, `w`, `u`, `d` for north, south, east, west, up, and down respectively, when those directions correspond to exits supported by the starter map.
- **FR-007**: System MUST allow a player to move from their current room to an adjacent room only when an exit in the requested direction exists; movement to a non-existent direction MUST NOT change the player's current room and MUST append a system message to the log indicating no exit exists in that direction.
- **FR-008**: System MUST append an arrival entry to the moving player's log on every successful movement, describing the room they have entered using the same content as a `look` in that room.
- **FR-009**: System MUST support a `take <object>` command that, when the named object exists in the player's current room and is not designated as fixed, removes the object from the room's contents, adds it to the player's inventory, and appends a confirmation entry to the log.
- **FR-010**: System MUST refuse a `take` command for an object that is designated as fixed, leaving world state unchanged and appending a system message explaining the object cannot be taken.
- **FR-011**: System MUST refuse a `take` command for an object name that does not match any object in the player's current room, leaving world state unchanged and appending a system message indicating no such object is here.
- **FR-012**: System MUST support a `drop <object>` command that, when the named object is in the player's inventory, removes the object from the player's inventory, adds it to the player's current room's contents, and appends a confirmation entry to the log.
- **FR-013**: System MUST refuse a `drop` command for an object name that is not in the player's inventory, leaving world state unchanged and appending a system message indicating the player is not carrying that object.
- **FR-014**: System MUST support an `inventory` command (with aliases `inv` and `i`) that appends a system entry to the log listing each object the player is currently carrying with its name and short description, or indicates the inventory is empty when the player carries nothing.
- **FR-015**: System MUST drive the existing Inventory HUD card from the same underlying inventory data so that the HUD card and the `inventory` command always present the same set of objects for the same player at any given moment.
- **FR-016**: System MUST drive the existing room-entry rendering in the player view's narrative log from the persisted room data described in FR-001, replacing the static/mocked room content used in 001 for any room that is part of the seeded map.
- **FR-017**: System MUST treat command verbs and object names case-insensitively and ignore leading and trailing whitespace when matching commands and object names.
- **FR-018**: System MUST append a system message to the log when the player submits an unknown command, leaving world state unchanged.
- **FR-019**: System MUST take no action and append no log entry when the player submits an empty or whitespace-only command.
- **FR-020**: System MUST ship a seeded starter map containing at least three rooms, all reachable from the designated starting room, where every connection between two adjacent rooms is realized as a pair of one-way exits (one stored on each room pointing to the other) so that no player can be trapped in a dead-end room and movement reversibility is demonstrable. The seeded map MUST also include a designated starting room, at least one room with a takeable object, at least one room with a fixed object, and at least one room with no objects.
- **FR-021**: System MUST provide a way to ask the persisted world: (a) what objects and players are currently in a given room, (b) what objects are currently carried by a given player, and (c) which room a given player currently occupies. These queries form the foundation on which the `look`, `inventory`, take/drop, and movement commands are built.
- **FR-022**: System MUST place a player in the designated starting room (and append a system message noting that their previous location is no longer reachable) on the next entry to the Play view when their previously occupied room no longer exists in the world.
- **FR-023**: System MUST return any objects carried by a player to the room where that player was located at the time of account deletion, rather than deleting those objects with the player's account.
- **FR-024**: System MUST detect the case in which a `take` or `drop` command names an object that matches more than one object in the relevant scope (room contents for `take`, inventory for `drop`) and respond with a system message asking the player to be more specific, without changing world state.
- **FR-025**: System MUST append a system entry to the narrative log of every other player currently in a room whenever an object is taken from that room, identifying the actor and the object (e.g., "Alice takes the brass key.").
- **FR-026**: System MUST append a system entry to the narrative log of every other player currently in a room whenever an object is dropped into that room, identifying the actor and the object (e.g., "Alice drops the letter.").
- **FR-027**: System MUST append a system entry to the narrative log of every other player currently in a destination room whenever a player arrives in that room. When the arrival was via a movement command from an adjacent room, the entry MUST identify the direction the arriving player came from (e.g., "Alice arrives from the south."); when the arrival has no direction context (initial first-time placement in the starting room, or restoration to a previously occupied room on re-entry to the Play view), the entry MUST simply identify the arrival (e.g., "Alice arrives.").
- **FR-028**: System MUST append a system entry to the narrative log of every other player remaining in the origin room whenever a player departs that room via a movement command, identifying the direction the departing player headed (e.g., "Alice leaves to the north.").
- **FR-029**: System MUST NOT deliver the witness entries described in FR-025 through FR-028 to the acting player themselves; the acting player only receives the actor-side confirmation or arrival entry produced by FR-008, FR-009, or FR-012.
- **FR-030**: System MUST deliver every witness entry produced by FR-025 through FR-028 at the moment the underlying event is applied — not deferred to the witness's next command — so that witnesses see passive activity in their log without issuing any input themselves.
- **FR-031**: System MUST render the Inventory HUD card (introduced as a mock in feature 001) using only the fields modeled by this feature — one tile or row per carried object showing the object's name and short description — and MUST remove the equipped marker, carried/worn status badge, quantity badge, and filter input that appeared in the 001 mockup, because those fields have no underlying data in this feature.
- **FR-032**: System MUST permit a single Player to have multiple concurrent authenticated sessions; all such sessions share a single underlying player state — the same current room and the same inventory — and all queries (`look`, `inventory`, the Inventory HUD card) from any session MUST reflect that shared state.
- **FR-033**: System MUST treat a command issued from any of a Player's sessions as mutating that single Player's state, so that the resulting world change (current room, inventory contents, presence in a room) is reflected in every one of that Player's sessions on its next query or live update.
- **FR-034**: System MUST deliver actor-side log entries that result directly from a command — including the confirmation and arrival entries from FR-008, FR-009, and FR-012, the inventory listing from FR-014, and the refusal/system messages from FR-007, FR-010, FR-011, FR-013, FR-018, and FR-024 — only to the session that issued the command, never to the Player's other sessions.
- **FR-035**: System MUST deliver witness entries produced by FR-025 through FR-028 — when generated by OTHER players' actions — to every one of a Player's sessions that is currently in the relevant room. Witness entries for the Player's own actions remain undelivered to that Player per FR-029, regardless of how many sessions they have.

### Key Entities *(include if feature involves data)*

- **Room**: A persisted location in the world. Has a stable identifier, a display name, a description used by `look` and arrival entries, and a set of exits to other rooms. Holds a (queryable) collection of game objects currently in the room and is associated with the set of players currently located there.
- **Exit**: A one-directional connection stored on a source room and pointing to a target room. Has a direction (one of north, south, east, west, up, down) and references the destination room. Exits are uniformly one-way at the data-model level — a "bidirectional" connection between rooms A and B is implemented by storing two separate exits (one from A toward B, one from B toward A) and is purely a seed-data convention with no special entity support. (Future wizard-authoring tooling is expected to detect orphan/trap rooms; this feature relies on seed-authoring discipline instead.)
- **Game Object**: A persisted item that may exist in a room or in a player's inventory, but never in both at the same time. Has a stable identifier, a display name, a short description, a long description (used when listing in `look`), and a "fixed" flag indicating whether it can be taken. At any moment a game object has exactly one location: either a specific room or a specific player's inventory.
- **Player Location**: The association between a player (introduced in 002) and their current room. Each player has at most one current room. Used to answer "which room is this player in?" and "which players are in this room?".
- **Player Inventory**: The set of game objects currently carried by a player (introduced in 002). Used to answer "what is this player carrying?" and to drive the Inventory HUD card. A given game object appears in at most one player's inventory at a time.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A newly registered player can issue `look`, see a real room description rendered from persisted data, and successfully move to an adjacent room within 30 seconds of first reaching the Play view, without any onboarding instructions.
- **SC-002**: 100% of `look`, `go`/`<direction>`, `take`, `drop`, and `inventory` commands issued in any state of the seeded starter map result in either the documented success outcome or a documented system message — there is no command in this feature's vocabulary that produces an undefined or silent failure.
- **SC-003**: After a take/drop sequence, the contents of the affected room as seen by a fresh `look` and the contents of the player's inventory as seen by a fresh `inventory` command always agree with each other and with the underlying persisted state, with zero observed drift.
- **SC-004**: After a full application restart, every player's current room, every room's object contents, and every player's inventory match the state they were in immediately before the restart.
- **SC-005**: The seeded starter map demonstrates every capability in this feature (multiple rooms, bidirectional movement, a takeable object, a fixed object, and an empty room) and a tester can verify each of those capabilities in fewer than ten commands starting from the designated starting room.
- **SC-006**: The Inventory HUD card and the `inventory` command produce identical lists for the same player at the same moment in 100% of trials.
- **SC-007**: When two players occupy the same room and one takes, drops, arrives, or departs, the other player receives a passive system log entry describing the event at the moment it occurs (with no input on their part and no page refresh), and a subsequent `look` reflects the resulting room contents and occupant list consistently with that entry.

## Assumptions

- Player accounts, sessions, and the authenticated Play route from feature 002 are reused as-is. This feature only adds world state and the commands that read and mutate it.
- The narrative log, room-entry rendering, suggestion chips, and Inventory HUD card from feature 001 are reused as the presentation layer. Mocked room/inventory content from 001 is replaced by persisted data for any rooms in the seeded starter map; unrelated mocked UI (HUD cards other than Inventory, wizard view, themes, layout variants) is unaffected by this feature.
- The starter map ships as seed data maintained by developers, not edited at runtime. Wizard-driven authoring of rooms/objects is out of scope for this feature and will be addressed in a later feature.
- Triggers, NPCs, combat, dialogue, quests, spells, and any automated reactions from game entities are out of scope. The only actors that change world state in this feature are players issuing commands.
- Object weight, capacity limits on inventories, room capacity limits, and any other resource-economy rules are out of scope. A player can carry any number of objects and a room can hold any number of objects.
- Object adjectives and disambiguation modifiers (e.g., `take rusty key` vs. `take iron key`) are out of scope; the seeded starter map avoids name collisions so simple name matching is sufficient. FR-024 covers the defensive case if it ever occurs.
- "Other players present in the room" listings in `look` and the passive witness entries required by FR-025 through FR-030 imply real-time delivery of world events to connected sessions. The behavior is fully specified by those FRs; the mechanism by which events are projected to subscribers (pubsub, channels, event-sourcing read models, etc.) is an implementation detail for the plan phase.
- Movement is between adjacent rooms only. There is no fast-travel, teleportation, or pathfinding command in this feature.
- All commands described here are issued through the existing text input bar (or, where applicable, by clicking existing suggestion chips and exit chips). No new input controls beyond what 001 provides are introduced by this feature.
