# Feature Specification: Wizard-Created NPC Blueprints (Milestone 2)

**Feature Branch**: `015-npc-blueprints`
**Created**: 2026-06-04
**Status**: Draft
**Input**: User description: "Wizard-Created NPC Blueprints (Milestone 2 of the wizard-authoring arc). Extend the feature 014 wizard-authoring substrate to NPCs as a second blueprint kind. Reuse the wizard role/authz, trance/authoring-mode toggle, the Interpreted Data card, the registry, monotonic revision + optimistic-locking, the LLM extraction entry points, and the freeform-spawn / spawn-from-blueprint / in-place-edit / essence-extraction flows. NPC blueprints carry display name, short/long description, the fixed/ungettable flag, a dedicated lore field, the behaviors list, and one or more composable toolsets. Toolsets are named groups of behaviors that compose via union and can be applied to items, NPCs, or rooms. Fold in the feature 008 event/lineage design by renaming its NPC events to the simpler NPCSpawned shape and dropping the lineage FK. Out of scope: republish-to-clones, new behavior triggers/actions, room digging, blueprint deletion, conversation-system changes."

> **✅ Substrate shipped (updated 2026-06-05):** The foundational clone/move/containment substrate
> this milestone builds on is **implemented and merged** (spec 016, PR #36). Entities are cloned
> into "the void" then moved into a typed container via the `Entity` aggregate; **spawning an NPC is
> now `clone_into(room)`**, and the feature-008 event fold-in is done (NPC spawn flows through
> `EntityCloned`/`EntityMoved`; the blueprint→clone lineage *coupling* — FK + per-blueprint serial
> counter — was dropped, though the clone keeps a **denormalized `blueprint_id`** so feature-010
> conversations and feature-013 NPC quests still resolve their catalog/lore). Consequently the
> fold-in requirements **FR-021–FR-023 below are already delivered by spec 016** and are out of
> scope here. This milestone is **pure NPC authoring**: blueprint create/edit/extract, composable
> toolsets, lore, the wizard trance UX, and the unified registry — riding on the merged substrate.

## Overview

Feature 014 (milestone 1) shipped the wizard-authoring **substrate** for one entity kind — Objects. A wizard drops into a trance (the `:blueprints` authoring mode), describes an item in natural language, watches the LLM extract structured fields into an Interpreted Data card, and commits it to a registry of reusable blueprints. The wizard can then spawn instances into the world, create one-off freeform instances, edit blueprints (revision-tracked, optimistically locked), edit in-world instances in place, and extract a new blueprint from an existing world instance.

This milestone (milestone 2) extends that exact pipeline to **NPCs**, routed through the same machinery as a second blueprint *kind* (`"npc"`) rather than a parallel system. After this ships, a non-engineer wizard can author an NPC — its name, descriptions, lore, behaviors, and composable toolsets — entirely through trance authoring, where before NPCs could only be authored at seed time (features 007–009).

It also folds the divergent NPC substrate from features 007/008 onto the cleaner milestone-1 pattern: feature 008's blueprint/clone event names and lineage foreign key are aligned to the simpler freestanding `NPCSpawned` shape that milestone 1 established for Objects. The project is in the pre-launch phase where the event log is destroyable (event shapes may be renamed/restructured without stream migrations), which is what makes this fold-in tractable now.

A new concept is introduced that is broader than NPCs: a **toolset** — a named, reusable group of behaviors (the `(trigger, [action])` tuples from feature 009) that composes via set union and can be applied to items, NPCs, or rooms. "Orc shopkeeper" becomes the union of an Orc toolset and a Shopkeeper toolset, authored once and reused. Milestone 2 wires toolset authoring onto NPC blueprints; the toolset substrate itself is designed as a cross-entity concept.

## Clarifications

### Session 2026-06-04

- Q: How should a wizard attach toolsets to an NPC blueprint during trance authoring? → A: **LLM proposes + wizard confirms.** The LLM infers likely toolsets from the lore/description prose and pre-selects them on the Interpreted Data card; the wizard adjusts via an explicit picker before commit. Requires both an LLM tool contract that proposes toolsets and a picker UI on the card.
- Q: How far should the toolset substrate be built in this milestone, given toolsets apply to items/NPCs/rooms? → A: **General registry, NPC UI only.** Build the cross-entity toolset model (named behavior groups attachable to items/NPCs/rooms) and its registry now, but wire only the NPC authoring UI in this milestone. Future milestones add item/room attachment UI without model rework.
- Q: How should new toolsets be created in this milestone? → A: **Seed-only.** Toolsets are authored at seed time in code (mirroring feature 009's seed-only behavior authoring). Wizards reference/attach existing toolsets via the picker, and the authoring LLM proposes from the seeded registry via `list_toolsets`. Wizard-authored toolset *creation* (a trance authoring surface for toolsets themselves) is deferred to a future milestone.
- Q: How should the feature 008 NPC event/lineage fold-in be handled? → A: **Full migration (wipe-and-replay).** Rename the NPC events to the `NPCSpawned` shape and drop the lineage FK outright, relying on the pre-launch destroyable-log / wipe-and-replay approach. Old streams need not remain projectable; no compatibility shim.

### Carried decisions from milestone 1 (feature 014) that this milestone reuses unchanged

- Wizard role is the `is_wizard` boolean on the player account; promotion is via `Accounts.promote_to_wizard/1`. Every wizard-only action re-checks `is_wizard` at the command/event-handler boundary.
- Authoring mode (`:world` / `:blueprints`) is a per-session UI state, not persisted; entering/leaving it broadcasts transient "enters a trance." / "appears to come out of a trance." log entries to co-located players.
- Blueprints are identified by a human-typable slug matching `^[a-z][a-z0-9_]*$`; they carry a monotonic `revision`; edits are optimistically locked against a known revision.
- Spawn semantics are **full-copy / denormalize**: a world instance copies every value from the blueprint at spawn time. Editing a blueprint never retroactively changes already-spawned instances.
- Any authenticated wizard may create/edit/extract/spawn from any blueprint. Blueprints carry no `created_by`, region scope, or ownership attribute (region-based authorization is a planned future direction, out of scope here).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Wizard Authors an NPC Blueprint in Trance (Priority: P1) 🎯 MVP

A wizard flips into trance (`:blueprints` mode) and types a natural-language description of a character — "Garrick is a wiry, sharp-eyed innkeeper, a former soldier who deserted the king's army and now keeps a quiet tavern. He greets newcomers warmly but clams up about his past." The LLM extracts the NPC blueprint fields into the Interpreted Data card: display name, short description, long description, lore, the ungettable/`fixed` flag, and any behaviors implied by the prose (e.g., a `player_entered → say "Welcome."` greeting). The wizard reviews/adjusts the card and clicks Commit. A new NPC blueprint appears in the registry at revision 1.

**Why this priority**: This is the headline payoff of the milestone — the first time a non-engineer can bring a new character into existence without touching seed code. Every other NPC-authoring story builds on the ability to produce a blueprint. Without it, the milestone has shipped nothing wizard-facing.

**Independent Test**: Promote a player to wizard, sign in, flip to trance, submit a multi-sentence character description, confirm the Interpreted Data card populates with name/short/long/lore (and any extracted behaviors), click Commit, and verify a `kind: "npc"` blueprint row exists in the registry at `revision: 1` with the expected fields. Verify a co-located player saw the trance entries.

**Acceptance Scenarios**:

1. **Given** a signed-in wizard in trance, **When** they submit a character description and the LLM resolves it, **Then** the Interpreted Data card shows an editable NPC blueprint draft with at least name, short description, long description, and lore populated, and the `kind` is `npc`.
2. **Given** a populated NPC blueprint draft, **When** the wizard clicks Commit, **Then** a new NPC blueprint is registered at `revision: 1` with a slug derived from the NPC's name, and the registry reflects it.
3. **Given** a description that implies a greeting ("she welcomes everyone who enters"), **When** the LLM resolves it, **Then** the draft includes a `player_entered → say` behavior the wizard can review and edit before commit.
4. **Given** a wizard whose draft slug collides with an existing blueprint slug, **When** they Commit, **Then** the commit is refused with a slug-collision message and no blueprint is created.

---

### User Story 2 - Wizard Spawns an NPC into a Room from a Blueprint (Priority: P1)

A wizard in `:world` mode selects an NPC blueprint from the registry and spawns it into their current room. A clone of the NPC appears in the room. Co-located players see it arrive ("Garrick the Innkeeper arrives.") and can examine it, exactly as with seed-spawned NPCs from feature 007. The spawned NPC is a full copy of the blueprint at spawn time — later edits to the blueprint do not change this instance.

**Why this priority**: Authoring a blueprint has no visible world effect until it can be placed. Spawn-from-blueprint is the second half of the MVP loop (author → place) and proves the full-copy denormalization semantics end to end.

**Independent Test**: With an NPC blueprint registered, a wizard in a room clicks "Spawn here" on that registry row; verify a co-located player's room view gains the NPC in the "Also here" section within the latency budget, the arrival witness entry fires, examining the NPC shows the blueprint's long description, and the NPC is ungettable if `fixed`.

**Acceptance Scenarios**:

1. **Given** a registered NPC blueprint and a wizard standing in a room, **When** the wizard spawns it here, **Then** a clone appears in that room and co-located players see the arrival entry and the "Also here" listing.
2. **Given** a spawned NPC clone, **When** a co-located player examines it, **Then** they see the blueprint's long description, identical to feature 007's examine contract.
3. **Given** an NPC blueprint carrying a `player_entered → say` behavior, **When** the clone is spawned and a player enters the room, **Then** the clone speaks per feature 009's behavior pipeline (behaviors are inherited at spawn via full copy).
4. **Given** an NPC clone spawned from blueprint B at revision N, **When** the wizard later edits B to revision N+1, **Then** the already-spawned clone is unchanged.

---

### User Story 3 - Existing NPCs Survive the Event-Shape Fold-In (Priority: P1)

A returning player logs in after this milestone ships and finds the existing seeded NPCs (Garrick the Innkeeper and any others) exactly as before: present in their rooms, examinable, ungettable, greeting on entry (feature 009), and conversable (feature 010). The underlying event names and the blueprint/clone lineage have been refactored onto the milestone-1 pattern, but no player-facing behavior changes.

**Why this priority**: The fold-in renames feature 008's events and drops the lineage FK. This is a refactor with real regression risk across features 007–010. Non-regression of the existing NPC stack is a release-blocking property — shipping new authoring on top of a broken NPC substrate is unacceptable. Like feature 008's own US1, "nothing changed for players" *is* the value of this story.

**Independent Test**: After a fresh world reset, log in as a new player. Confirm the seeded NPC(s) render in their rooms, `look <npc>` shows the long description, `take <npc>` is refused, entering Garrick's room fires his greeting, and `chat <npc>` produces an in-character reply grounded in the wizard-authored lore. Run the full features 007/008/009/010 test suites against the refactored event shapes and confirm they pass.

**Acceptance Scenarios**:

1. **Given** a freshly reset world, **When** a player logs in, **Then** the seeded NPC(s) appear in their rooms identically to before this milestone.
2. **Given** the seeded greeter NPC, **When** a player enters its room, **Then** the greeting behavior fires (feature 009 unchanged from the player's perspective).
3. **Given** the seeded NPC's lore, **When** a player chats with it, **Then** feature 010's conversation produces an in-character reply grounded in that lore.
4. **Given** the existing features 007–010 automated test suites, **When** they run against the refactored event/lineage shapes, **Then** they pass (with only mechanical event-name updates, no behavioral changes).

---

### User Story 4 - Wizard Composes Toolsets onto an NPC Blueprint (Priority: P2)

A wizard authoring an NPC blueprint attaches one or more named toolsets — for example, an "Orc" toolset and a "Shopkeeper" toolset — and the NPC's effective behaviors become the union of those toolsets. An "orc shopkeeper" is expressed by stacking toolsets, not by hand-authoring a bespoke character. The wizard can also assign **individual behaviors directly** on the blueprint, on top of (or instead of) toolsets — e.g., a "cave troll" blueprint attaches the usual `troll` toolset and then adds a one-off "weakness to sunlight" behavior that belongs to no toolset. The blueprint's effective behavior set is the union of all attached toolsets' behaviors and all directly-assigned behaviors. Toolsets are named groups of behaviors and are a cross-entity concept (the same toolset could apply to an item or a room), though this milestone wires the authoring surface for NPC blueprints.

**Why this priority**: Composable toolsets are the design payoff that makes NPC authoring feel additive rather than enumerated. It depends on US1 (a blueprint to attach to) but is not required for the bare author→spawn MVP, so it is P2.

**Independent Test**: With at least two named toolsets seeded (e.g., "orc", "shopkeeper"), author an NPC blueprint, attach both toolsets via the picker, and verify the blueprint's effective behaviors are the union of both toolsets' behaviors with no duplicates. Spawn a clone and confirm it exhibits behaviors from both toolsets.

**Acceptance Scenarios**:

1. **Given** two named toolsets each carrying distinct behaviors, **When** a wizard attaches both to an NPC blueprint, **Then** the blueprint's effective behavior set is the union of the two toolsets' behaviors.
2. **Given** a blueprint with a toolset attached, **When** the wizard also assigns an individual behavior directly on the blueprint, **Then** the effective behavior set is the union of the toolset's behaviors and that directly-assigned behavior, and the direct behavior belongs to no toolset.
3. **Given** two toolsets that both carry a behavior on the same trigger, **When** they are composed, **Then** composition follows a documented, deterministic conflict-resolution rule and produces no silently dropped behaviors.
4. **Given** an NPC blueprint with toolsets attached, **When** a clone is spawned, **Then** the clone inherits the composed (unioned) behaviors via full copy at spawn time.
5. **Given** a toolset is edited after a blueprint referenced it, **When** an existing clone is inspected, **Then** the clone is unaffected (full-copy semantics; toolset edits do not retro-propagate to spawned clones).

---

### User Story 5 - Wizard Creates a Freeform One-Off NPC in the World (Priority: P2)

A wizard in `:world` mode describes an NPC directly into existence in their current room without first creating a blueprint — a one-off character that needs no reuse. The NPC appears in the room with the described fields. No blueprint is created.

**Why this priority**: Mirrors feature 014's freeform-object path. Useful for ad-hoc set dressing and quick storytelling, but secondary to the reusable-blueprint loop.

**Independent Test**: A wizard in a room submits a freeform NPC description in `:world` mode; verify the NPC appears in the room for co-located players, is examinable, and that no new row appears in the blueprint registry.

**Acceptance Scenarios**:

1. **Given** a wizard in `:world` mode, **When** they submit a freeform NPC description, **Then** an NPC appears in their current room and co-located players see it arrive.
2. **Given** a freeform NPC was created, **When** the registry is inspected, **Then** no blueprint was created for it.
3. **Given** a freeform NPC and a blueprint-spawned NPC in the same room, **When** either is examined, **Then** the two are observationally identical as world entities (the creation path is not visible to players).

---

### User Story 6 - Wizard Extracts a Blueprint from an In-World NPC (Priority: P2)

A wizard sees an NPC in the world they want to reuse — perhaps a freeform one they just made, or a clone they edited in place — and extracts its essence into a new NPC blueprint. The wizard flips to trance with the Interpreted Data card pre-populated from the source NPC's fields (including lore, behaviors, and toolset composition), supplies a slug, and commits. The source NPC is untouched — extraction is a one-way distillation.

**Why this priority**: Mirrors feature 014's extract path; closes the loop from freeform/edited world entity back into reusable blueprint. Secondary to the core author→spawn loop.

**Independent Test**: With an in-world NPC present, a wizard clicks "Extract essence"; verify they flip to trance with the card pre-filled from the source NPC's fields, that committing creates a new blueprint at revision 1, and that the source NPC's row is unchanged.

**Acceptance Scenarios**:

1. **Given** an in-world NPC, **When** a wizard extracts its essence, **Then** the trance card pre-populates with the NPC's name, descriptions, lore, behaviors, and toolset composition.
2. **Given** an extracted draft, **When** the wizard commits with a slug, **Then** a new NPC blueprint is created at `revision: 1`.
3. **Given** an extraction, **When** it completes, **Then** the source NPC's fields are byte-for-byte unchanged.

---

### User Story 7 - Wizard Edits an NPC Blueprint or In-World NPC (Priority: P2)

A wizard opens an existing NPC blueprint (or focuses an in-world NPC clone) in the Interpreted Data form and edits a field — adjusts the lore, fixes a typo in the long description, adds a behavior, attaches a toolset. Committing a blueprint edit bumps its revision and is optimistically locked against the wizard's known revision; a stale edit is refused with the current revision surfaced. Editing an in-world clone changes that clone in place. Neither operation retroactively alters other spawned instances.

**Why this priority**: Iterative editing is essential for real authoring, but the create→spawn loop is demonstrable without it, so P2 (matching feature 014's edit story).

**Independent Test**: Edit an NPC blueprint's lore and Commit; verify revision bumps N→N+1 and the registry shows the new value. Have two wizards focus the same blueprint and both commit; verify the second receives a stale-revision refusal showing the current revision. Separately, edit an in-world clone's field and verify only that clone changed.

**Acceptance Scenarios**:

1. **Given** a blueprint at revision N, **When** a wizard commits an edit that changes at least one field, **Then** the blueprint advances to revision N+1; a no-op commit produces no revision bump.
2. **Given** two wizards editing the same blueprint at revision N, **When** both commit, **Then** the first succeeds and the second is refused with the current revision surfaced in their form.
3. **Given** an in-world NPC clone, **When** a wizard edits one of its fields and commits, **Then** that clone's row updates in place and a co-located player's next examination shows the new value.
4. **Given** a blueprint edit, **When** it commits, **Then** no previously spawned clone of that blueprint is altered.

---

### User Story 8 - Wizard Browses the Unified Blueprint Registry (Priority: P3)

A wizard opens the registry and sees both Object blueprints and NPC blueprints, distinguished by kind, and can filter to one kind. Spawn and edit affordances are appropriate to each entry's kind.

**Why this priority**: A quality-of-life view once two blueprint kinds coexist. Useful but not required for the core authoring loop, hence P3.

**Independent Test**: With at least one Object blueprint and one NPC blueprint registered, open the registry; verify both appear with a visible kind distinction and that filtering to "npc" shows only NPC blueprints.

**Acceptance Scenarios**:

1. **Given** registered blueprints of both kinds, **When** the wizard opens the registry, **Then** each entry shows its kind and the list includes both kinds.
2. **Given** the registry is open, **When** the wizard filters by kind `npc`, **Then** only NPC blueprints are listed.
3. **Given** an NPC blueprint row, **When** the wizard chooses "Spawn here," **Then** an NPC clone (not an object) is spawned.

---

### Edge Cases

- **Duplicate display name in a room**: feature 007 requires NPC display names be unique within a room. What happens when a wizard spawns a clone whose name collides with an NPC already in that room? (Expected: refusal or auto-disambiguation consistent with feature 007's rule.)
- **Empty lore**: an NPC blueprint authored with no lore must still spawn and still converse (feature 010 already handles empty lore with a minimal grounded reply).
- **Toolset references a behavior vocabulary not yet shipped**: only feature 009's `player_entered`/`player_left` → `say` primitives exist. What happens if the LLM proposes a behavior outside that vocabulary? (Expected: the unknown primitive is rejected/flagged at extraction or commit, not silently persisted.)
- **Attaching a non-existent toolset**: committing a blueprint that references a toolset name that does not exist must be refused.
- **Editing an in-world NPC that is mid-conversation** (feature 010 ephemeral conversation in flight): the in-place edit must not corrupt or crash an active conversation.
- **Extract essence from a clone whose blueprint was since edited**: extraction copies the *clone's* current fields, not the blueprint's — verify the distinction.
- **Fold-in replay**: replaying the historical event store after the event rename must reconstruct the existing NPC read model correctly (or be handled by the documented wipe-and-replay/destroyable-log approach).

## Requirements *(mandatory)*

### Functional Requirements — NPC blueprint authoring (reuses milestone-1 substrate)

- **FR-001**: The system MUST support `"npc"` as a blueprint kind flowing through the same authoring pipeline (trance authoring, Interpreted Data card, registry, revision/optimistic-lock, spawn, edit, extract) that feature 014 established for `"object"` — not a parallel pipeline.
- **FR-002**: A wizard in `:blueprints` mode MUST be able to author an NPC blueprint from a natural-language prompt, with the LLM extracting structured fields into the Interpreted Data card for review before commit.
- **FR-003**: An NPC blueprint MUST carry: a slug identifier (`^[a-z][a-z0-9_]*$`), display name, short description, long description, the `fixed`/ungettable flag, a dedicated `lore` field (feature 010), a behaviors list of `(trigger, [action])` tuples (feature 009 vocabulary), and zero or more attached toolsets. It MUST carry a monotonic `revision`.
- **FR-004**: The slug for a new NPC blueprint MUST default to a value derived from the NPC's display name and MUST be unique across all blueprints regardless of kind; a colliding slug MUST refuse the commit.
- **FR-005**: Committing an NPC blueprint edit MUST bump `revision` only when at least one content field changed, and MUST be optimistically locked against the wizard's known revision — a stale edit is refused with the current revision surfaced (identical semantics to feature 014).
- **FR-006**: Every NPC-blueprint authoring/edit/extract/spawn action MUST verify `is_wizard` at the command boundary and refuse non-wizards.

### Functional Requirements — NPC world instances (clones)

- **FR-007**: A wizard in `:world` mode MUST be able to spawn an NPC clone from a registered NPC blueprint into their current room. The clone MUST be a full copy of the blueprint's fields at spawn time (full-copy/denormalize semantics from feature 008).
- **FR-008**: A spawned NPC clone MUST be observationally identical to a feature-007 NPC for players: it appears in the room's "Also here" listing, fires an arrival witness entry, is examinable (long description), is ungettable when `fixed`, greets/farewells per any inherited behaviors (feature 009), and is conversable per feature 010.
- **FR-009**: Editing an NPC blueprint MUST NOT alter any previously spawned clone. There is no live propagation of blueprint edits to existing clones in this milestone ("republish to clones" is explicitly deferred).
- **FR-010**: A wizard MUST be able to create a freeform one-off NPC in their current room without creating a blueprint; no blueprint row is created for a freeform NPC.
- **FR-011**: A wizard MUST be able to edit an in-world NPC clone in place; the edit changes only that clone and is visible to co-located players on their next examination.
- **FR-012**: A wizard MUST be able to extract a new NPC blueprint from an in-world NPC, pre-populating a trance draft from the source NPC's current fields (including lore, behaviors, and toolset composition); the source NPC MUST be unchanged by extraction.
- **FR-013**: Spawning a clone whose display name would collide with an NPC already present in the destination room MUST be handled consistently with feature 007's per-room name-uniqueness rule.

### Functional Requirements — Toolsets

- **FR-014**: A toolset MUST be a named group of behaviors (`(trigger, [action])` tuples drawn from the feature-009 vocabulary). Toolset behaviors MUST be limited to the currently-shipped trigger/action vocabulary; a behavior referencing an unshipped primitive MUST be rejected, not silently persisted.
- **FR-014a**: Toolsets MUST be created at seed time in this milestone (mirroring feature 009's seed-only behavior authoring). There is NO wizard-facing toolset *creation* surface in this milestone — wizards only reference/attach toolsets that already exist in the registry. A seed MUST populate at least two distinct named toolsets so US4 (composition) is demonstrable from a fresh world. Wizard-authored toolset creation is explicitly deferred to a future milestone.
- **FR-015**: An NPC blueprint MUST support BOTH attached toolsets AND individually-assigned behaviors, independently and in combination. A wizard MUST be able to (a) attach zero or more named toolsets, (b) assign zero or more individual behaviors directly on the blueprint, or (c) do both at once. The blueprint's effective behavior set MUST be the set union of all referenced toolsets' behaviors and all directly-assigned behaviors. Example: a "cave troll" blueprint attaches the usual `troll` toolset and then adds a one-off "weakness to sunlight" behavior directly, without that behavior having to belong to any toolset.
- **FR-015a**: The authoring surface (Interpreted Data card) MUST let the wizard add and remove individual behaviors directly on the blueprint, alongside the toolset picker — direct-behavior authoring is not gated behind creating a toolset. The LLM extraction MAY propose individual behaviors inferred from the prose (per FR-002); those land as directly-assigned behaviors that the wizard can edit or remove before commit. (Individual behaviors remain limited to the shipped feature-009 trigger/action vocabulary per FR-014; a richer vocabulary — e.g., an actual sunlight-weakness primitive — is future work, so the cave-troll example illustrates the composition *model*, not a claim that arbitrary behaviors ship in this milestone.)
- **FR-016**: Toolset composition MUST follow a documented, deterministic conflict-resolution rule when two toolsets carry behaviors on the same trigger; no behavior may be silently dropped without a defined rule.
- **FR-017**: Composed (unioned) behaviors MUST be inherited by a clone at spawn time via full copy; editing a toolset after spawn MUST NOT retroactively alter already-spawned clones.
- **FR-018**: Referencing a toolset name that does not exist MUST refuse the commit.
- **FR-019**: The toolset substrate MUST be designed as a cross-entity concept — a toolset is a named behavior group conceptually applicable to items, NPCs, or rooms. This milestone MUST build the general cross-entity toolset model and registry (so a toolset row is not NPC-bound), while wiring the authoring UI only for NPC blueprints. Item and room attachment UI is deferred to a later milestone and MUST require no toolset-model rework when added.
- **FR-020**: Toolset attachment during authoring MUST follow an LLM-proposes / wizard-confirms flow: the LLM proposes likely toolsets inferred from the lore/description prose and pre-selects them on the Interpreted Data card, and the wizard MUST be able to add or remove toolsets via an explicit picker before commit. The committed toolset set is whatever the wizard confirms, not the raw LLM proposal.
- **FR-020a**: The authoring LLM client MUST have a read-only `list_toolsets` tool that returns the currently-registered named toolsets, so its proposals (FR-020) are grounded in the real toolset registry rather than invented names. A toolset name the LLM proposes that is not in the registry MUST NOT be silently committed (consistent with the FR-018 refusal on unknown toolset references). The same registry list backs the wizard's explicit picker.

### Functional Requirements — Feature 008 fold-in (✅ delivered by spec 016)

> FR-021–FR-023 were satisfied by the merged clone/move substrate (spec 016) and are **not** in
> scope for this milestone. Retained for traceability.

- **FR-021** *(done in 016)*: NPC spawn no longer carries a blueprint lineage on the spawned-instance event — NPCs are cloned/moved via `EntityCloned`/`EntityMoved`, aligned to the object pattern. (The clone keeps a denormalized non-FK `blueprint_id` for conversation/quest catalog lookup.)
- **FR-022** *(done in 016)*: features 007–010 behaviors (examine, ungettable, arrival witness, greeting behaviors, conversations) verified non-regressed.
- **FR-023** *(done in 016)*: delivered as a full migration over the destroyable log (reseed); no compatibility shim.
- **FR-024**: The blueprint read model MUST hold both `"object"` and `"npc"` kinds in a way that supports listing all blueprints and filtering by kind. *(In scope — the unified registry.)*

### Functional Requirements — Registry & UI

- **FR-025**: The blueprint registry MUST display both Object and NPC blueprints, show each entry's kind, and support filtering by kind.
- **FR-026**: Registry spawn/edit affordances MUST be appropriate to each entry's kind (spawning an NPC blueprint yields an NPC clone, not an object).
- **FR-027**: The Interpreted Data card MUST render the NPC-specific fields (lore, behaviors, toolsets) for editing in addition to the shared name/short/long/fixed fields.

### Key Entities

- **NPC Blueprint**: The authored template for a kind of NPC. Attributes: slug, kind (`npc`), display name, short description, long description, `fixed` flag, `lore`, behaviors list, referenced toolsets, `revision`. Shares the blueprint registry and lifecycle machinery with Object blueprints (milestone 1).
- **NPC Clone (world instance)**: A concrete NPC placed in a room, a full denormalized copy of a blueprint's fields at spawn time (or directly authored for freeform NPCs). Carries no live link back to its blueprint (lineage FK dropped per the fold-in).
- **Toolset**: A named, reusable group of behaviors (feature-009 `(trigger, [action])` tuples). Composes via set union and is conceptually applicable to items, NPCs, or rooms. Referenced by blueprints by name. Created at seed time in this milestone (no wizard-facing creation surface yet); lives in a cross-entity registry the authoring LLM can list via `list_toolsets`.
- **Behavior**: A `(trigger, [action])` tuple from the feature-009 vocabulary (`player_entered`/`player_left` → `say`). Authored directly on a blueprint or grouped into a toolset.
- **Lore**: The dedicated free-text grounding field (feature 010) the conversation system feeds to the LLM to keep an NPC in character.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A wizard can author a new NPC blueprint end-to-end (flip to trance → describe → review card → Commit → see it in the registry) in under 120 seconds for a single-paragraph description (allowing for lore/behavior extraction).
- **SC-002**: Spawning an NPC from a blueprint into the wizard's current room reflects in every co-located player's room view and narrative log within 2 seconds of the wizard's click.
- **SC-003**: A clone spawned from a blueprint at revision N is provably unchanged after the blueprint advances to revision N+1, in 100% of regression tests (full-copy non-propagation).
- **SC-004**: An NPC blueprint with two attached toolsets exposes exactly the set-union of both toolsets' behaviors (no duplicates, no silent drops), verified for 100% of composition test cases.
- **SC-005**: Extracting a blueprint from an in-world NPC produces a draft whose every field exactly matches the source NPC's corresponding field, with zero divergence, and leaves the source NPC byte-for-byte unchanged, in 100% of regression tests.
- **SC-006**: After the event-shape fold-in, 100% of the existing features 007–010 automated tests pass (with only mechanical event-name updates), and a fresh-world manual walkthrough shows no player-visible change to seeded NPCs.
- **SC-007**: Editing an NPC blueprint at revision N produces revision N+1 only when a content field changed, and a stale concurrent edit is refused with the current revision surfaced, in 100% of regression tests.
- **SC-008**: 100% of NPC blueprints carry a slug matching `^[a-z][a-z0-9_]*$` and zero carry a UUID-shaped id; slugs are unique across both blueprint kinds.

## Assumptions

- The feature 014 wizard-authoring substrate (role/authz, trance mode, Interpreted Data card, registry, revision/optimistic-lock, freeform/spawn/edit/extract flows, LLM extraction entry points) is in place and is the foundation this milestone extends — it is not re-built.
- The behavior vocabulary remains exactly feature 009's set (`player_entered`/`player_left` triggers, `say` action). Expanding the vocabulary (new triggers/actions) is out of scope; toolsets in this milestone group only these existing primitives.
- The conversation system (feature 010) is unchanged and simply consumes the wizard-authored `lore`. No conversation-system changes ship here.
- The project remains in the pre-launch "event log is destroyable" phase, so the fold-in may rename/restructure NPC event shapes without stream migration tooling. (Re-evaluate if "production"/"real users" status changes before this ships.)
- Full-copy / denormalize spawn semantics from feature 008 are retained: blueprint and toolset edits never retro-propagate to spawned clones. "Republish to clones" is explicitly deferred to a later milestone.
- Out of scope, deferred: wizard-authored toolset *creation* (toolsets are seed-only here — wizards only attach existing ones); item/room toolset attachment UI (the model is cross-entity but only NPC attachment is wired); republish-to-clones / live propagation; new behavior triggers or actions; room digging / region authoring; blueprint deletion; region-based authorization; any conversation-system change.
- Any authenticated wizard may author/edit/spawn/extract any NPC blueprint; blueprints carry no ownership/region attribute (consistent with milestone 1).
