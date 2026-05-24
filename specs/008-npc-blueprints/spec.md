# Feature Specification: NPC Blueprints (Prelude — Blueprint/Clone Split)

**Feature Branch**: `008-npc-blueprints`
**Created**: 2026-05-23
**Status**: Draft
**Input**: User description: "go with the new addition of the notion of a blueprint as the source of data for when NPCs are cloned or instantiated into the world. Include all the appropriate decisions we've made in this recent conversation. We are doing the full copy of data from prototype to clone and leaving the notion of manual or live update of clones from a new prototype to another feature."

## Background

Feature 007 introduced NPCs as a first-class room-bound entity, but every NPC in the world is its own self-contained row — there is no way to author a "kind of NPC" once and put several of them in the world. The MUD tradition is to separate **blueprints** (the authored template — what an NPC IS) from **clones** (the concrete copies in the world — `Garrick the Innkeeper#1`, `#2`, ...).

This feature is a **refactor-only prelude**. No new player-facing capability ships. After this feature lands, the seeded Garrick the Innkeeper still appears in the Stone Atrium exactly as before — but he now exists as a clone of a `garrick_the_innkeeper` blueprint, identified by a stable per-blueprint serial number. The substrate this builds is the precondition for:

- Future features that let one blueprint produce many clones (e.g., five identical city guards).
- A future behavior system (the next feature) that authors behaviors on the blueprint and lets every clone inherit them.
- A future wizard tab that lets non-engineers author blueprints through natural language.

**Full-copy semantics**: at clone time, every value from the blueprint is denormalized into the clone row. Subsequent edits to a blueprint do NOT propagate to existing clones. The wizard's iterative "edit blueprint → existing clones update" workflow is **explicitly out of scope** for this feature — it is deferred to a later feature that adds a deliberate "republish to clones" operation. The motivation for full-copy is **blast-radius containment**: a mistake on a popular blueprint cannot silently corrupt hundreds of existing clones in the wild.

## Clarifications

### Session 2026-05-23

- Q: Are NPC Blueprints mutable after creation through the command path in this feature? → A: No. Blueprints are immutable through the command path in this feature — no `UpdateBlueprint` (or equivalent) command exists. Story 3's full-copy property is verified via direct persistence-layer writes that bypass the aggregate. A proper update command will land with the wizard tab feature.
- Q: How does the migration handle the existing `world_npcs` table from feature 007? → A: Wipe-and-replay. The Ecto migration drops the existing `world_npcs` table, creates the new blueprint and clone tables, and the projector rebuilds the read model by replaying the event store. Historical `NPCSpawnedInRoom` events project through synthetic blueprints (FR-019..FR-021). No in-place SQL data migration is used.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Players see no change to the world (Priority: P1)

A returning player logs in after this refactor ships and finds the world exactly as they left it. Garrick the Innkeeper still stands in the Stone Atrium with the same display name, the same "Also here:" listing, and the same long description when examined. The `take` refusal, the natural-language examination paths, and every other feature 007 behavior continue to work unchanged. The blueprint/clone substrate is entirely invisible to the player.

**Why this priority**: This is a refactor with no intended player-facing change. The non-regression of feature 007's behavior IS the headline value. Any player-visible difference would indicate the refactor went wrong.

**Independent Test**: After `mix ecto.reset`, log in as a fresh player. The room view of the Stone Atrium MUST render an "Also here:" section listing `Garrick the Innkeeper`. `look garrick` MUST render Garrick's long description. `take Garrick the Innkeeper` MUST produce `You can't take that.` Every feature 007 integration test MUST continue to pass against the refactored schema.

**Acceptance Scenarios**:

1. **Given** a freshly reset world, **When** a player logs in for the first time, **Then** the Stone Atrium's room view includes Garrick the Innkeeper in the "Also here:" section identically to how feature 007 rendered him.
2. **Given** a player in the Stone Atrium, **When** they submit `look garrick`, **Then** the same detail entry as feature 007 is rendered (same long description, same render contract).
3. **Given** a player in the Stone Atrium, **When** they submit `take garrick`, **Then** the same `You can't take that.` refusal is rendered.
4. **Given** the full feature 007 integration test suite, **When** it runs against the refactored schema, **Then** every test passes without modification.

---

### User Story 2 - Author a blueprint once, spawn one or more clones from it (Priority: P1)

A content author (today: the seed code; later: the wizard tab) defines a single blueprint — say, `garrick_the_innkeeper` with a display name, short description, and long description — and then spawns one (or more) clones of that blueprint into specific rooms in the world. Each clone is a fully-realized presence in the world with all of the blueprint's data copied into it at the moment of spawning. The blueprint itself is **not** in the world — it is purely an authored template; players cannot see it, examine it, take it, or interact with it.

**Why this priority**: This is the structural payoff of the feature. Even though the seed only spawns one clone of Garrick today, the mechanism that allows it MUST be the same mechanism that future content authoring uses. Shipping the substrate here means the next feature (behaviors) and the feature after (wizard tab) build cleanly without re-architecting.

**Independent Test**: After `mix ecto.reset`, query the persistence layer directly. There MUST be exactly one row in the blueprint catalog (`garrick_the_innkeeper`), and exactly one row in the clone catalog whose blueprint reference points to that blueprint and whose data fields (name, short description, long description) match the blueprint's data verbatim. The clone MUST have a stable identifier distinct from the blueprint's identifier and a per-blueprint serial number of `1`.

**Acceptance Scenarios**:

1. **Given** the seeded starter map, **When** the persistence layer is inspected, **Then** there is exactly one blueprint named `Garrick the Innkeeper` AND exactly one clone whose blueprint reference points to it AND whose `serial` is `1`.
2. **Given** an authoring API that can create blueprints and spawn clones, **When** two clones are spawned from the same blueprint, **Then** they receive distinct stable identifiers AND consecutive serial numbers (`1`, `2`).
3. **Given** an attempt to spawn a clone referencing a non-existent blueprint identifier, **Then** the operation MUST be refused cleanly and the world state MUST be unchanged.
4. **Given** a clone in the world, **When** the room view is rendered, **Then** the clone's data is sourced from the clone row directly (no fall-through to the blueprint at render time).

---

### User Story 3 - Editing a blueprint does not affect existing clones (Priority: P1)

A content author (in this feature: a developer running tests; in a later feature: a wizard) modifies the `long_description` field of an existing blueprint after a clone has already been spawned from it. The existing clone's `long_description` MUST remain unchanged — its value was captured at the moment of cloning. Only clones spawned AFTER the blueprint edit will reflect the new value.

**Why this priority**: This is the **defining property** of full-copy semantics. The whole reason we chose full-copy over live propagation was to bound the blast radius of authoring mistakes. If a blueprint edit could silently change every existing clone's data, that property would be violated. This scenario must be testable independently of any UI for editing blueprints — a DB-level integration test that mutates a blueprint row and then re-reads a previously-spawned clone confirms the contract.

**Independent Test**: Spawn a clone of `garrick_the_innkeeper`. Read the clone's `long_description` (call it `before`). Mutate the blueprint's `long_description` to a distinctly different value. Read the SAME clone's `long_description` (call it `after`). Assert that `before == after`, NOT that `after` equals the new blueprint value. The clone is a snapshot; the blueprint can change behind it without effect.

**Acceptance Scenarios**:

1. **Given** a clone spawned from a blueprint with `long_description: "Original."`, **When** the blueprint's `long_description` is changed to `"Updated."`, **Then** the clone's `long_description` remains `"Original."`.
2. **Given** a clone spawned from a blueprint, **When** the blueprint is mutated and a SECOND clone is spawned from it, **Then** the first clone retains the pre-edit values AND the second clone has the post-edit values.
3. **Given** the room view rendered for a player, **When** the underlying blueprint of one of the room's NPCs is mutated, **Then** the room view continues to show the original values until the player triggers a re-render — and even then the rendered values come from the clone, not the blueprint.

---

### User Story 4 - Each clone has a debug-visible identity (`name#serial`) (Priority: P2)

A developer or future admin user looking at the world from a debug surface (logs, telemetry events, a future admin console) MUST be able to identify a specific clone uniquely. The clone's debug display takes the LPMud-traditional form `<display_name>#<serial>` — for example, `Garrick the Innkeeper#1`. The serial is monotonic per blueprint, assigned at spawn time, and stable for the lifetime of the clone. Players DO NOT see the `#serial` suffix on any player-facing surface; this is strictly for admin/debug audiences.

**Why this priority**: Operationally important but not user-facing. Once multiple clones of the same blueprint exist in the wild (a future feature), distinguishing them in logs and admin tools without their serials becomes impossible. Shipping the serial as part of the prelude means the moment multi-clone spawning becomes useful, the debug story is already in place.

**Independent Test**: Spawn three clones of the same blueprint. Inspect telemetry events emitted by the spawn operation: each event MUST include `serial` values of `1`, `2`, `3` respectively. Render the world's debug listing (e.g., via an iex one-liner): each clone MUST be identifiable as `<display_name>#<serial>`. Render the room view from a player's session: NO `#serial` suffix MUST appear in player-facing output.

**Acceptance Scenarios**:

1. **Given** three clones spawned from the same blueprint, **When** their debug identities are inspected, **Then** they read `<name>#1`, `<name>#2`, `<name>#3` in spawn order.
2. **Given** any clone in the world, **When** the player-facing room view renders it, **Then** the rendered name is the bare display name with NO `#serial` suffix.
3. **Given** any clone in the world, **When** any log line, telemetry event, or debug surface references it, **Then** the `<name>#<serial>` form is used.
4. **Given** the seed runs once, **When** the seed runs again on a fresh world, **Then** the same blueprint produces a clone with `serial: 1` (the serial counter is deterministic per blueprint within a fresh world).

---

### User Story 5 - Historical event replay still produces the correct world (Priority: P2)

A developer wipes the read-model database and replays the entire event store from scratch. The event store contains both pre-refactor events (feature 007's `NPCSpawnedInRoom` events) and post-refactor events (this feature's new event types). After replay completes, the world's read model MUST contain the same set of NPCs in the same rooms as before the wipe. Historical events do NOT need to be rewritten; the projector handles them as legitimate (legacy) spawn events and produces matching clone rows in the new schema.

**Why this priority**: Event-source purity. The event store is the canonical history of the world; rewriting it would be a serious violation of "the past is immutable." The cost of supporting historical replay through the new schema is a small adjustment to the projection logic — a one-time elaboration paid by this feature's implementation, not a rolling tax.

**Independent Test**: With a populated world (Garrick seeded + maybe a few admin-dispatched spawns from feature 007), wipe the read-model tables. Replay the event store. After replay, the count of NPC clones in each room MUST match the pre-wipe count and every clone MUST have a valid blueprint reference (either to an authored blueprint or to a synthetic blueprint generated from the legacy event's data at projection time). The operation MUST be idempotent — running it twice produces the same result.

**Acceptance Scenarios**:

1. **Given** an event store containing only pre-refactor `NPCSpawnedInRoom` events, **When** the read model is wiped and the event store is replayed, **Then** the post-replay world contains one clone per historical spawn event with full-copied data.
2. **Given** an event store with both pre-refactor and post-refactor spawn events, **When** the event store is replayed, **Then** the world reflects the union of both correctly — pre-refactor events project through a synthetic blueprint, post-refactor events project through their authored blueprint.
3. **Given** a successful replay, **When** the replay is run a second time without changes, **Then** the world state is unchanged (idempotency).

---

### Edge Cases

- **Spawning a clone referencing a non-existent blueprint**: refused with a clean error. World state unchanged.
- **Two clones of the same blueprint targeting the same room with no name override capability**: refused, because feature 007 FR-001a (per-room display name uniqueness) still holds and clones in this feature carry the blueprint's display name verbatim with no override. The seeded world does not exercise this case; it surfaces only when a future authoring path spawns multiple identical-named clones into one room.
- **Attempting to delete a blueprint while clones reference it**: refused. Referential integrity is preserved; blueprint authors must drain clones first or deprecate the blueprint without deleting it. (Note: clone removal is itself out of scope per FR-017; deprecation is the only practical action in this feature.)
- **Blueprint editing in this feature**: not exposed via any UI or command. Blueprints are authored only via the seed. Edit-after-spawn is a property described in Story 3 for completeness, exercised only by direct DB-level tests in this feature.
- **Replaying an event store containing a clone-spawn event whose blueprint was never persisted** (corrupted history): the projector creates a synthetic blueprint from the event's denormalized data so the replay completes successfully. This is the same path used for pre-refactor `NPCSpawnedInRoom` events.
- **Per-blueprint serial counter wraparound**: serial is a monotonic integer; for any realistic blueprint clone count (thousands), no wraparound concern exists.
- **Concurrent spawn races on a shared blueprint**: the blueprint's serial counter is serialized at the aggregate layer so two concurrent spawns receive consecutive distinct serials. No two clones of the same blueprint MAY share a serial.
- **Blueprint with an empty long description**: refused at the authoring layer (matching feature 007's rule that NPC long descriptions MUST NOT be empty).
- **Renaming a blueprint after clones exist**: changes the blueprint's display name. Existing clones retain their original display name (Story 3 / full-copy). The blueprint and its already-spawned clones may now disagree on display name; that is expected behavior under full-copy and is not an error.
- **A clone whose room is deleted**: out of scope. Rooms are not deletable in any current feature; this remains true here.

## Requirements *(mandatory)*

### Functional Requirements

**Blueprint entity**:

- **FR-001**: System MUST introduce a new entity type called NPC Blueprint, distinct from the existing NPC (clone) entity. A blueprint has at minimum: a stable identifier, a display name, a short description, and a long description.
- **FR-002**: NPC Blueprints MUST NOT have a location in the world. They are never returned by room-view queries, never appear in the "Also here:" section, never appear as a valid `look` target, and never appear in any inventory or holder relationship. They exist solely as authored templates.
- **FR-003**: NPC Blueprints' display names need NOT be globally unique. Two distinct blueprints MAY have the same display name (e.g., two different "Goblin Guard" variants). The stable identifier is the only uniqueness constraint at the blueprint level.
- **FR-004**: NPC Blueprints MUST require a non-empty long description (matching feature 007 FR-001). Authoring a blueprint with an empty long description MUST be refused.
- **FR-005**: NPC Blueprints in this feature MUST be authored exclusively via the seeding mechanism. No wizard UI, no in-game command, and no admin REST endpoint MUST be exposed for blueprint authoring in this feature. Future features will introduce authoring surfaces.
- **FR-005a**: NPC Blueprints MUST be immutable through the command path in this feature. No `UpdateBlueprint`-equivalent command MUST be introduced. Story 3's full-copy property is verified via direct persistence-layer writes from tests, NOT through a published command. A wizard-facing update command lands with the wizard tab feature.

**Clone entity**:

- **FR-006**: An NPC Clone MUST reference exactly one NPC Blueprint at the moment of spawning, via a stable blueprint identifier reference.
- **FR-007**: At spawn time, all of the blueprint's authored fields (display name, short description, long description) MUST be copied from the blueprint into the clone's own storage. The clone is a snapshot of the blueprint's state as of that moment.
- **FR-008**: A clone has its own stable identifier, distinct from the blueprint's identifier. The clone MUST be addressable independently (e.g., in `look` resolution, take refusal, future combat targeting, etc.) by its own identifier.
- **FR-009**: Each clone MUST receive a per-blueprint monotonic serial number at spawn time. The serial counter is owned by the blueprint and starts at `1`; the Nth clone of a given blueprint has serial `N`.
- **FR-010**: The pair `(blueprint_id, serial)` MUST uniquely identify a clone within its blueprint family across the lifetime of the world.
- **FR-011**: The clone's debug display takes the form `<display_name>#<serial>` (e.g., `Garrick the Innkeeper#1`). This form MUST appear in telemetry events, log lines, and any future admin/debug surfaces. It MUST NOT appear in any player-facing surface (room view, examination output, communication verbs, etc.).

**Full-copy semantics**:

- **FR-012**: Subsequent edits to a blueprint MUST NOT propagate to existing clones. A clone's data fields, once set at spawn time, are owned by the clone exclusively.
- **FR-013**: This feature explicitly does NOT introduce a "republish to clones" operation. Any mechanism for propagating blueprint edits to existing clones is deferred to a future feature.
- **FR-014**: This feature explicitly does NOT introduce per-clone override fields (no `name_override`, no `description_addendum`, no property bag). Clones carry their full data as denormalized columns sourced from their blueprint at spawn time.

**Per-room uniqueness (preserves feature 007 FR-001a)**:

- **FR-015**: Per-room clone display-name uniqueness MUST continue to hold. The system MUST refuse to spawn a clone into a room that already contains another clone with the same display name (case-insensitive comparison). This is the direct preservation of feature 007 FR-001a, now applied at the clone level rather than the NPC level.

**Lifecycle**:

- **FR-016**: NPC Blueprints MUST NOT be deletable while any clones reference them. Attempting to delete such a blueprint MUST be refused with a clear error. Deletion of a blueprint with zero clones is allowed.
- **FR-017**: Clone removal from the world is out of scope for this feature, mirroring feature 007's posture. Clones, once spawned, persist for the lifetime of the world.

**Authoring path**:

- **FR-018**: The seed mechanism MUST be the only authoring path for blueprints in this feature. The seed MUST be updated so that the existing Garrick-the-Innkeeper content is produced by first creating a `garrick_the_innkeeper` blueprint and then spawning one clone of it into the Stone Atrium. The resulting world content MUST be observationally identical to the pre-refactor seed.

**Backward compatibility (event store)**:

- **FR-019**: Historical NPC spawn events from feature 007 MUST continue to project successfully against the new schema. Each historical event MUST produce a clone row whose data is fully copied from the event's payload AND whose blueprint reference points to a synthetic blueprint generated at projection time from the event's denormalized data.
- **FR-020**: The projection of historical events MUST be idempotent. Replaying the event store twice MUST yield the same world state.
- **FR-021**: Synthetic blueprints created during legacy event projection MUST have deterministic identifiers (a function of the historical event's payload, not a random UUID), so that repeated replays produce the same synthetic blueprints.
- **FR-021a**: The Ecto migration that lands this feature MUST follow a **wipe-and-replay** strategy: it MUST drop the existing `world_npcs` table from feature 007, create the new blueprint and clone tables, and rely on the projector's event-store replay (FR-019..FR-021) to rebuild the read model. No in-place SQL data migration of pre-existing rows MUST be used. This guarantees the synthetic-blueprint path is exercised on every developer's first migration, providing implicit regression coverage of FR-019..FR-021.

**Out of scope (this feature)**:

- **FR-022**: This feature MUST NOT introduce object blueprints. Game objects continue to use their feature 003 schema (one row per object, no template/instance split). Object blueprints are deferred to a future feature.
- **FR-023**: This feature MUST NOT introduce room blueprints. Rooms continue to be unique entities authored individually. Room blueprints are deferred (or may never be needed — rooms are inherently singletons).
- **FR-024**: This feature MUST NOT introduce behaviors, dialogue, movement, combat, or any other dynamic NPC capability. Feature 007's restrictions (NPCs cannot speak, move, or participate in combat) MUST continue to hold.
- **FR-025**: This feature MUST NOT introduce any new player-facing surface, command, or capability. The wizard tab is the subject of a future feature; this feature ships the substrate it will sit on.

### Key Entities

- **NPC Blueprint**: An authored template for a kind of NPC. Has stable identifier, display name, short description, long description, and a serial counter. Never has a location; never appears in the world. The source of data at clone time only; not consulted at render time.
- **NPC Clone**: A concrete instance of an NPC in the world, spawned from a blueprint. Owns its own stable identifier, blueprint reference, per-blueprint serial number, and a denormalized copy of all the blueprint's authored fields as of clone time. The substrate from which the player-facing world is rendered.
- **Synthetic Blueprint**: A blueprint created at projection time by the read-model projector when replaying a historical (pre-refactor) NPC spawn event. Identical in structure to an authored blueprint, but its identifier is derived deterministically from the historical event's payload rather than chosen by a content author.
- **Per-blueprint Serial**: A monotonic integer counter, scoped to one blueprint, that assigns sequential numbers to clones of that blueprint in spawn order. Renders as `#N` in debug surfaces; invisible to players.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of feature 007's integration tests pass against the refactored schema with no modifications to test assertions. (The only allowed test changes are to setup helpers — e.g., updating the seed-NPC fixture to know about blueprints.)
- **SC-002**: A freshly reset world contains exactly one NPC blueprint (`Garrick the Innkeeper`) and exactly one clone of that blueprint (in the Stone Atrium, serial `1`). Both are observable by direct persistence-layer inspection.
- **SC-003**: A blueprint edit applied after a clone is spawned produces zero observable changes to the existing clone (verified by direct persistence-layer comparison of clone fields before and after the blueprint edit).
- **SC-004**: Spawning N clones from the same blueprint produces exactly N distinct clone identifiers with serial values `1` through `N` in spawn order; no duplicates, no gaps, no concurrent-race collisions.
- **SC-005**: Replaying the event store from empty against the post-refactor codebase produces a world that is functionally identical to a world created via the post-refactor seed — same rooms, same exits, same objects, same NPCs, same locations. Idempotent under repeated replay.
- **SC-006**: Every clone of a blueprint, when inspected via any debug surface (telemetry, logs, admin queries), displays its identity in the form `<display_name>#<serial>` (e.g., `Garrick the Innkeeper#1`). The same clone, when rendered in any player-facing surface, displays its bare display name with no `#serial` suffix.
- **SC-007**: Zero references to per-clone override fields, fallback chains, or property bags exist in the implementation. Clone fields are read directly from the clone row in 100% of render paths.
- **SC-008**: An attempt to spawn a clone referencing an unknown blueprint produces a refusal with a clear error and zero persistence-layer side effects (no orphan clone rows, no partial state).

## Assumptions

- Per-blueprint serial counter scope is per-blueprint (LPMud convention — `sword#42` is sword-specific), not globally monotonic. Wraparound is a non-concern in practice.
- The blueprint's display name is the canonical name used for player-facing rendering of its clones. Future per-clone overrides will allow customizing this, but this feature explicitly does not.
- Blueprint identifiers are stable strings (UUIDs or human-readable slugs like `garrick_the_innkeeper`). The choice between UUIDs and slugs is a planning-phase concern; both work.
- The seed's existing Garrick content (display name, short description, long description) is preserved verbatim — only the seeding path changes (CreateBlueprint + SpawnClone instead of a single SpawnNPC command).
- Historical events from feature 007 use deterministic synthetic blueprint identifiers derived from the historical event's payload (e.g., a hash of the (name, short_description, long_description) tuple). This guarantees idempotency under replay.
- The "republish to clones" feature, when it eventually lands, will be opt-in per-edit (a wizard explicitly chooses to push changes), not automatic. This feature explicitly does not prescribe the shape of that future operation; it only states that it is out of scope here.
- The wizard tab is a future feature; this feature does not introduce any UI for blueprint authoring or clone management.
- The blueprint vs. clone split applies in this feature to NPCs only. Objects (feature 003) and rooms (feature 003) retain their current single-table schema; their blueprint/clone splits are independent future features.
- Feature 007's seed-time-only spawn restriction continues to apply — clones are spawned only by the seed mechanism. No runtime spawn command is exposed to players or wizards in this feature.
- The 500-character input cap from features 004 / 005 continues to apply where relevant.
- Desktop web only, English-language only, matching all prior features.
