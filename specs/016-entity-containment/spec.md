# Feature Specification: Entity Lifecycle — Clone & Move with Typed Containment

**Feature Branch**: `016-entity-containment`
**Created**: 2026-06-04
**Status**: Draft
**Input**: User description: "Entity lifecycle — clone() & move() with typed containment (foundational world-model substrate). Introduce the classic MUD entity-lifecycle model: clone() brings an entity into existence in 'the void'; move(entity, from, to) relocates it between typed containers (void, room, player inventory, NPC inventory) with one uniform 'arrived' pathway; clone_into(target) = clone + move. Spawning is a containment concern, not a room concern. Retrofit the spec-014 object spawn path (and fold the feature-007/008 NPC spawn path) onto clone+move so there are not two spawn models. Inventory FEATURES are deferred; this establishes the containment MODEL and the move pathway with the room container wired."

> **⚠️ Sequencing note:** Although numbered 016, this milestone is a **prerequisite of milestone
> 015 (Wizard-Created NPC Blueprints)** and ships **before** it. The number reflects creation
> order, not dependency order. Spec 015 rebases onto this substrate: its "spawn an NPC" becomes
> `clone_into(room)` here, and the feature-008 NPC event fold-in originally scoped into 015 is
> subsumed by this milestone's retrofit.

## Overview

Today the world already moves objects between a **room** and a **player's inventory** — `take`,
`drop`, and `inventory` all work. But location is modeled ad-hoc as **two nullable foreign keys
(`room_id`, `player_id`) with an XOR constraint** ("exactly one location"), and every spawn/move is
a bespoke event owned by the `Room` aggregate. That ad-hoc model has hard structural limits:

- It can express only *room* or *player inventory* — it **cannot represent "the void"** (the XOR
  forbids both-null, so an object can never exist unplaced) and **cannot represent an NPC's
  possession** (there is no NPC-inventory location).
- Entity *creation* is conflated with *room-placement*: objects (spec 014) are born already in a
  room via `ObjectSpawned`; NPCs (spec 007/008) are born in a room via a clone-from-blueprint event
  carrying a blueprint lineage. Neither can exist before placement.
- `take`/`drop` are bespoke `Room`-aggregate events (`ObjectTakenFromRoom`/`ObjectDroppedInRoom`)
  rather than instances of one general relocation. Adding a third container type would mean inventing
  yet more bespoke events.

In short: placement is treated as a *room* operation when it is really a *containment* operation,
and the location model can only hold two of the container types the world actually needs.

This milestone introduces one uniform entity lifecycle, borrowed from the MUD tradition:

- **clone()** brings a world entity into existence with its (frozen) fields. A freshly cloned
  entity is in **"the void"** — it exists but is in no container and is visible nowhere.
- **move(entity, from, to)** relocates an entity from one container to another. The **destination
  container's "arrived" pathway fires** regardless of container type; the source container's
  "departed" pathway fires when the origin is a real container. The origin or destination may be
  the void.
- **clone_into(target)** is a convenience wrapper: `clone()` then `move(entity, void → target)`.

**Containers are typed and uniform:** the void, a **room**, a **player's inventory**, or an
**NPC's inventory**. A single typed container reference `(type, id)` replaces the two-FK-XOR model.
The same move operation and the same single relocation pathway serve every container type — there
is no room-specific spawn concept anywhere in the model. Each container type keeps its own *witness
convention* (rooms announce arrivals/departures to occupants; player inventory updates the owning
player and stays silent to others, exactly as today), so a uniform *mechanism* does not change
existing observable behavior.

This milestone delivers the **model** and the **move pathway**, and retrofits **every existing
spawn and relocation path** onto it so only one model exists: object spawn (spec 014), NPC spawn
(spec 007/008), and the live **`take`/`drop`** pair (which become ordinary moves between room and
player-inventory). The **room** and **player-inventory** containers are therefore both wired and in
scope (they already carry real behavior that must not regress). What is deferred is **inventory
*features* layered on top** — NPC shop stock, `give`, and any new carry/transfer verbs — not the
basic carry that already exists. Whether the **NPC-inventory** container type is wired now or merely
defined in the model is the one open scope question (FR-017).

## Clarifications

### Session 2026-06-04

- Q: Where does `clone()` live and what owns container membership? → A: **Entity-as-aggregate + thin
  service.** Each entity owns its own event stream and current container; a move is dispatched to the
  entity. `clone()` is a thin global world-service wrapper that mints the entity's stream (created in
  the void); `clone_into` is the clone-then-move wrapper. (FR-016, FR-018.)
- Q: How much of the spec-014 object spawn path is retrofitted now? → A: **Full retrofit now** —
  object spawn, NPC spawn, and the live `take`/`drop` pair are all reworked onto clone + move in this
  milestone; exactly one spawn/relocation model exists at the end. (FR-012/FR-012a/FR-012b/FR-015.)
- Q: Which container types are wired end-to-end? → A: **Void + room + player-inventory wired;
  NPC-inventory defined-but-dormant.** Room and player inventory already carry live behavior and must
  not regress; NPC-inventory is a valid container in the model but has no read model/pathway yet.
  (FR-017.)
- Correction (same session): an earlier draft wrongly treated player inventory as a deferred/dormant
  feature. `take`/`drop`/`inventory` are live today (modeled as `room_id`/`player_id` nullable FKs
  with an `exactly_one_location` XOR). This substrate generalizes that into a typed container
  reference and folds take/drop into the uniform move pathway (FR-012a/FR-012b).

### Carried context (pre-launch phase)

- The event log is destroyable in the current pre-launch phase, so spawn-related event shapes may
  be renamed/restructured without stream-migration tooling. (Re-evaluate if "production" status
  changes before ship.)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - An Entity Is Brought Into the World at a Location (Priority: P1) 🎯 MVP

A new entity (say, a brass lantern, or an NPC) is created and placed into a room in one step
(`clone_into(room)`). It comes into existence, is moved out of the void into the room, and the
room's occupants witness its arrival exactly as they witness any arrival today.

**Why this priority**: This is the headline replacement for "spawn." Until creating-and-placing an
entity works end to end through clone + move, the substrate has shipped nothing observable and
nothing else can build on it.

**Independent Test**: Invoke `clone_into(room)` for a new entity; verify (a) the entity exists,
(b) it is reported as contained by that room, (c) co-present players' room view and narrative log
show its arrival within the existing arrival latency budget, and (d) examining it shows its fields.

**Acceptance Scenarios**:

1. **Given** a target room with co-present players, **When** an entity is cloned into that room,
   **Then** the entity exists, is contained by the room, and co-present players witness its arrival.
2. **Given** the same operation, **When** the entity is examined, **Then** its frozen fields are
   shown (identical to how entities are examined today).
3. **Given** a clone-into that fails after the entity is created but before placement, **Then** the
   entity is left in the void (existing but unplaced), not half-placed in the destination.

---

### User Story 2 - Existing Objects and NPCs Are Unchanged After the Retrofit (Priority: P1)

A returning player logs in after the object (and NPC) spawn paths are reworked onto clone + move.
The seeded world looks and behaves exactly as before: objects are in their rooms and examinable;
NPCs appear in "Also here," are examinable, ungettable, greet on entry, and converse.

**Why this priority**: This is a refactor of two shipped spawn paths (specs 014 and 007/008). The
non-regression of all existing behavior is the release-blocking property — a player-visible change
means the retrofit went wrong. Like spec 008's own US1, "nothing changed for players" is the value.

**Independent Test**: After a fresh world reset, log in as a new player. Confirm seeded objects and
NPCs render, examine, and behave identically to before, and that taking an object, checking
`inventory`, and dropping it all still work. Run the full specs 006/007/008/009/010/013/014 automated
suites — including the `take`/`drop`/`inventory` tests — against the reworked events and confirm they
pass (with only mechanical event-shape updates, no behavioral changes).

**Acceptance Scenarios**:

1. **Given** a freshly reset world, **When** a player logs in, **Then** seeded objects appear in
   their rooms and examine identically to before the retrofit.
2. **Given** the same world, **When** a player enters a room with a seeded NPC, **Then** the NPC
   appears in "Also here," examines, is ungettable, and fires its greeting — unchanged.
3. **Given** the existing specs 007/008/009/010/014 suites, **When** they run against the reworked
   spawn events, **Then** they pass.

---

### User Story 3 - An Entity Relocates Between Containers (Priority: P2)

An existing entity is moved from one container to another — e.g., from one room to another room, or
back into the void — through the single move operation. Observers in the source container witness
its departure; observers in the destination witness its arrival.

**Why this priority**: Movement is the capability the old spawn model couldn't express. It proves
the uniform departure/arrival pathway and is the foundation every future relocation (wandering
NPCs, dropping/taking items, giving) rides on. Secondary to bringing entities into the world (US1).

**Independent Test**: Move an entity from room A to room B; verify it leaves A (departure witnessed
by A's occupants, no longer in A's view) and arrives in B (arrival witnessed, now in B's view).
Move it to the void; verify it leaves B and is then contained by nothing and visible nowhere.

**Acceptance Scenarios**:

1. **Given** an entity in room A, **When** it is moved to room B, **Then** A's occupants witness a
   departure and B's occupants witness an arrival, and the entity is contained by B only.
2. **Given** an entity in a room, **When** it is moved to the void, **Then** the room's occupants
   witness a departure and the entity is thereafter contained by nothing and visible nowhere.
3. **Given** any move, **When** it completes, **Then** the entity is in exactly one container (the
   destination) — never in two, never in none unless the destination is the void.
4. **Given** the live `take`/`drop` verbs (now ordinary moves), **When** a player takes an object
   from a room and later drops it, **Then** the object moves room → player-inventory → room through
   the same move pathway, the `inventory` listing reflects it while carried, and the observable
   behavior is identical to today (room keeps its witness convention; inventory stays silent to
   others).

---

### User Story 4 - A Cloned-But-Unplaced Entity Exists Only in the Void (Priority: P2)

An entity is cloned without being placed. It exists and can be referenced, but it is contained by
nothing — it appears in no room, no inventory, and is witnessed by no one until it is moved.

**Why this priority**: The void is what makes "exist before placement" real (the property the old
model lacked). It must be a well-defined, observable state, not an accident. Lower than US1/US2
because most callers will use the `clone_into` wrapper, but the void is the conceptual core.

**Independent Test**: Clone an entity without moving it; verify it exists, is reported as in the
void, appears in no container's listing, and produces no arrival witness anywhere. Then move it into
a room and verify the normal arrival pathway fires.

**Acceptance Scenarios**:

1. **Given** a freshly cloned, unplaced entity, **When** any room or container is viewed, **Then**
   the entity appears in none of them and no arrival was witnessed.
2. **Given** a void-resident entity, **When** it is moved into a room, **Then** the standard arrival
   pathway fires for that room.

---

### User Story 5 - The Containment Model Is Uniform Across Container Types (Priority: P3)

The model treats a room, a player's inventory, and an NPC's inventory as interchangeable container
types for the purpose of move. Even though inventory *features* are not built in this milestone,
the model accepts inventory container references through the same move operation and the same
arrival pathway, so future inventory work needs no model change.

**Why this priority**: This is the design guarantee that prevents a future re-architecture. It is
validated at the model level (not via player-facing inventory UX, which is deferred), so it is P3.

**Independent Test**: Exercise the move operation with each defined container type as destination
(room and — per the wired-scope clarification — at least one inventory type at the model level),
and verify the operation and arrival pathway are the same code path for each, differing only by the
container's type tag.

**Acceptance Scenarios**:

1. **Given** the move operation, **When** it is given a room destination versus an inventory
   destination, **Then** both are accepted and routed through the same arrival pathway, differing
   only by container type.
2. **Given** a container reference of an unknown/unsupported type, **When** a move targets it,
   **Then** the move is rejected with a clear error rather than silently succeeding.

---

### Edge Cases

- **Move to the same container** (no-op move): the entity stays put; no spurious departure/arrival
  is witnessed.
- **Move of a void-resident entity with origin stated as a real container** (stale origin): the
  move is rejected or reconciled — an entity's actual current container is authoritative, not the
  caller-supplied origin.
- **Concurrent moves of the same entity**: the entity ends in exactly one container; the model
  serializes moves of a single entity so it cannot be double-placed.
- **Arrival into a destination that no longer exists** (e.g., a room removed): the move is rejected;
  the entity is not stranded.
- **Per-room name uniqueness** (feature 007): moving/cloning an entity whose name collides with one
  already in the destination room is handled consistently with the existing uniqueness rule.
- **Retrofit replay**: with the destroyable event log, historical spawn events need not remain
  projectable; a fresh reseed produces clean clone/move event streams.

## Requirements *(mandatory)*

### Functional Requirements — Entity lifecycle

- **FR-001**: The system MUST support creating a world entity ("clone") that comes into existence
  with a stable identity and its frozen fields, initially contained by **the void** (no container).
- **FR-002**: The system MUST support relocating an entity between containers ("move") via a single
  operation that takes the entity, its origin, and its destination, where origin and destination may
  each be the void or any supported container type.
- **FR-003**: The system MUST provide a `clone_into(target)` convenience path equivalent to a clone
  followed by a move from the void to the target, such that a failure between the two steps leaves
  the entity in the void (created, unplaced) rather than partially placed.
- **FR-004**: At all times an entity MUST be contained by **exactly one** container (where the void
  counts as a container). It MUST never be simultaneously in two containers, and never in none.
- **FR-005**: Moves of a single entity MUST be serialized so concurrent moves cannot place it in two
  containers; the entity's actual current container is authoritative over any caller-supplied origin.

### Functional Requirements — Containers & the arrival/departure pathway

- **FR-006**: The model MUST define typed containers: **void**, **room**, **player inventory**, and
  **NPC inventory**. A container reference MUST carry its type and the id of the specific container.
- **FR-007**: A move into a real (non-void) destination container MUST trigger **one uniform
  "arrived" pathway** that is identical across container types, differing only by the destination's
  type tag. There MUST NOT be a room-specific spawn/arrival concept separate from this pathway.
- **FR-008**: A move out of a real (non-void) source container MUST trigger a corresponding
  "departed" pathway for that source. A move into or out of the void MUST NOT fire the
  void-side arrival/departure.
- **FR-009**: A no-op move (destination equals current container) MUST NOT fire any
  arrival/departure and MUST leave the entity unchanged.
- **FR-010**: A move targeting an unknown/unsupported container type, or a destination that does not
  exist, MUST be rejected with a clear error; the entity MUST remain in its prior container.
- **FR-011**: For room destinations, the arrival/departure pathway MUST be observationally identical
  to the existing room arrival/departure witnessing (the live-witness model from feature 003 / the
  NPC arrival from feature 007 / the object arrival from feature 014) — co-present players see the
  same entries within the same latency budget.

### Functional Requirements — Retrofit of existing spawn paths

- **FR-012**: The existing **object** spawn path (spec 014, currently the `Room` aggregate emitting
  an object-spawned event) MUST be reworked onto clone + move so that objects come into existence via
  the same lifecycle as every other entity. There MUST NOT be two spawn models after this milestone.
- **FR-012a**: The existing **`take`/`drop`** path (currently `ObjectTakenFromRoom` /
  `ObjectDroppedInRoom` bespoke `Room`-aggregate events) MUST be reworked into ordinary moves —
  `take` = move(object, room → player-inventory), `drop` = move(object, player-inventory → room) —
  so relocation between a room and a player's inventory uses the one uniform move pathway, not
  bespoke events.
- **FR-012b**: The ad-hoc location representation (two nullable foreign keys `room_id`/`player_id`
  with the `exactly_one_location` XOR constraint) MUST be replaced by a single typed container
  reference `(type, id)` that can also express the void and an NPC-inventory, while preserving the
  per-room name-uniqueness rule (feature 007) and the invariant that an object is in exactly one
  container.
- **FR-013**: The existing **NPC** spawn path (spec 007/008, currently a clone-from-blueprint event
  carrying a blueprint lineage) MUST be reworked onto clone + move. The blueprint lineage on the spawn
  event/instance is dropped (the instance remains a frozen full copy). This subsumes the
  "feature-008 event fold-in" originally scoped into spec 015.
- **FR-014**: After the retrofit, all existing player-facing behavior for objects (specs 006/013/014),
  **`take`/`drop`/`inventory`**, and NPCs (specs 007/008/009/010) MUST be non-regressed. Each
  container type retains its current witness convention (no new "X picks up Y" announcement is
  introduced by the mechanism change).
- **FR-015**: The object retrofit (FR-012/FR-012a/FR-012b) MUST be completed in **this** milestone —
  i.e., a full retrofit, not a temporary coexistence of the old and new models. At the end of this
  milestone exactly one spawn/relocation model exists (per FR-012 and SC-003). *(Resolved: full
  retrofit now.)*

### Functional Requirements — Architecture & scope decisions (to confirm)

- **FR-016**: `clone()` lives in a **thin global world service** that is purely the
  dispatcher/wrapper; the **entity owns its own event stream and its current container**
  (entity-as-aggregate), and a move is dispatched to the entity. `clone()` mints the entity's stream
  (entity created in the void); `clone_into` is the service-level clone-then-move wrapper. *(Resolved:
  entity-as-aggregate + thin service.)*
- **FR-017**: The **room** and **player-inventory** container types MUST be wired end-to-end in this
  milestone (they already carry live behavior — room presence and `take`/`drop`/`inventory` — that
  must not regress). The **void** is also wired (it is the clone origin). The **NPC-inventory**
  container type MUST be **defined in the model** (a valid container reference the move operation
  accepts and validates) but is **left dormant** — no NPC-inventory read model, arrival pathway, or
  query is built in this milestone, and it attaches in a later NPC-inventory feature with no model
  rework. *(Resolved: define-but-dormant for NPC inventory; room + player inventory wired.)*
- **FR-018**: The entity MUST own the consistency boundary for its own container membership (its
  current container is a property of the entity), so that "where is this entity" has a single
  authoritative source regardless of container type.
- **FR-019**: Inventory **features** (players picking up/carrying items, NPC shop stock, give/take
  verbs) are explicitly OUT OF SCOPE; only the containment model and the move pathway ship here.

### Key Entities

- **World Entity**: Anything that can exist in the world and be contained — currently objects and
  NPCs. Has a stable identity, frozen fields, and exactly one current container (possibly the void).
- **Container**: A typed location that holds entities — **void** (the null container), **room**,
  **player inventory**, **NPC inventory**. Identified by `(type, id)`.
- **The Void**: The distinguished null container holding entities that exist but are placed nowhere.
- **Clone**: The act of bringing an entity into existence (into the void) with its frozen fields.
- **Move**: The act of relocating an entity from one container to another, firing the destination's
  arrival pathway and the source's departure pathway.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Bringing a new entity into a room via clone + move reflects in every co-present
  player's room view and narrative log within 2 seconds (matching the existing spawn/arrival budget).
- **SC-002**: 100% of the existing specs 006/007/008/009/010/013/014 automated tests — **including
  the `take`/`drop`/`inventory` suites** — pass after the retrofit (with only mechanical event-shape
  updates), and a fresh-world walkthrough shows no player-visible change to seeded objects, carried
  items, or NPCs.
- **SC-003**: There is exactly **one** spawn/placement code path after this milestone; an audit finds
  zero remaining room-specific spawn events distinct from the uniform move/arrival pathway.
- **SC-004**: For 100% of moves, the entity is contained by exactly one container at completion
  (verified by invariant checks), including under concurrent-move tests.
- **SC-005**: The move operation and arrival pathway are the same code path for every wired container
  type, differing only by the container's type tag (verified by test coverage across types).
- **SC-006**: A cloned-but-unplaced entity appears in zero container listings and produces zero
  arrival witnesses, in 100% of void-state tests.

## Assumptions

- The event log remains destroyable in the current pre-launch phase, so the object and NPC spawn
  events may be renamed/restructured and historical streams discarded via reseed (no stream-migration
  tooling). Re-evaluate if "production"/"real users" status changes before ship.
- Entities remain a frozen full copy after placement (no live link back to a blueprint), consistent
  with specs 008/014 — the retrofit changes *how* entities are created/placed, not the full-copy
  denormalization semantics.
- This milestone ships **before** spec 015 (NPC blueprints); spec 015 rebases its spawn onto
  `clone_into(room)` here, and its feature-008 event fold-in is subsumed by FR-013.
- The existing `take`/`drop`/`inventory` behavior is **in scope and preserved** (reworked into moves,
  not removed). What is deferred: *new* inventory features layered on top — NPC shop stock, a `give`
  verb, container nesting (objects inside objects), and any transfer UX beyond today's take/drop.
- Out of scope / deferred: blueprint authoring (spec 015), new behavior triggers/actions, region-based
  permissions, and any rename of the existing NPC-instance table beyond dropping the lineage.
- NPCs continue to live only in rooms (feature 007); the NPC-inventory container type concerns objects
  an NPC might *hold*, not relocating the NPC itself.
