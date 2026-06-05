# Phase 0 Research: Wizard-Created NPC Blueprints (Milestone 2)

**Feature**: 015-npc-blueprints | **Date**: 2026-06-05 | **Spec**: [spec.md](./spec.md)

Resolves the design questions for NPC authoring, now that the **clone/move/containment substrate
(spec 016) is merged**. The dominant constraints: **reuse the feature-014 object-blueprint pipeline**
(mirror it for `kind: "npc"`) and **ride the merged substrate for spawning** (`clone_into(:npc, …)`),
not rebuild either. The spec's three clarifications (toolset UX, toolset scope, toolset creation) plus
the feature-008 fold-in are already settled — see the spec's Clarifications session; this document
realizes them against the current code.

## Starting-state facts (post-016)

| Concern | State after spec 016 (merged) |
|---|---|
| NPC spawn | `Commands.spawn_npc_clone/3` → `clone_into(:npc, fields, room, :spawned)` → `Entity` aggregate → `EntityProjector` writes `npc_clones`. No `SpawnNPCClone`/`NPCClonedFromBlueprint`. |
| `NPCBlueprint` aggregate | **create-only** (`CreateNPCBlueprint` → `NPCBlueprintCreated`). No edit, no revision, no serial/clone tracking. |
| `npc_blueprints` table | `name, short_description, long_description, is_synthetic, behaviors, lore, quests`. **No** `kind`, `fixed`, `revision`, `toolsets`. |
| `npc_clones` table | `name, short_description, long_description, behaviors, lore, serial, blueprint_id` (denormalized non-FK ref), `room_id` (nullable, written by `EntityProjector`). |
| `EntityProjector` `:npc` | `EntityCloned` → insert `npc_clones`; `EntityMoved` → set `room_id`; `EntityEdited` → **currently a no-op** (NPCs not edited yet). |
| Object blueprint authoring (014) | `ObjectBlueprint` aggregate (revision + optimistic lock), `ObjectBlueprintProjector`, `Commands.create/edit/spawn_from/spawn_freeform/edit/extract`, `IntentResolver.resolve_wizard_blueprint/2` + `WizardTools`, `GameLive` wizard handlers + `game_components` wizard view, unified `WizardBlueprintRegistryChanged` broadcast. |

So milestone 2 = extend the NPC blueprint substrate with the milestone-1 authoring affordances, add
toolsets, and wire the wizard UX — all on top of the merged clone/move spawn path.

## R1 — Mirror the `ObjectBlueprint` authoring pipeline for `NPCBlueprint`

**Decision**: Add to the `NPCBlueprint` aggregate the same lifecycle `ObjectBlueprint` has — a
monotonic `revision` and an `EditNPCBlueprint{blueprint_id, wizard_id, expected_revision,
fields_changed}` command → `NPCBlueprintEdited{blueprint_id, fields_changed, revision}`, with
identical no-op-skip and `{:error, :stale_revision, current_revision: N}` semantics (FR-005).
`CreateNPCBlueprint`/`NPCBlueprintCreated` gain `kind: "npc"`, `fixed`, `toolsets`, `revision: 1`.
A dedicated `NPCBlueprintProjector` (mirroring `ObjectBlueprintProjector`) handles
`NPCBlueprintCreated`/`Edited` into `npc_blueprints` (or extend `WorldProjector`'s existing
`NPCBlueprintCreated` handler + add the edit handler — decide in tasks; both are supervised the same
way).

**Rationale**: Direct structural parallel to shipped, tested milestone-1 code; minimal novelty.
Editable blueprint fields: `name, short_description, long_description, fixed, lore, behaviors,
toolsets`. `quests` (feature 013) is **preserved but not wizard-editable** here (no quest authoring
UI in scope). `is_synthetic` is now dead (016 removed the synthetic path) — leave the column, always
`false`; optional cleanup, out of scope.

**Alternatives rejected**: a separate parallel pipeline (defeats reuse); making quests editable
(scope creep).

## R2 — Two blueprint tables + a union registry query (same as 014 R2)

**Decision**: Keep `object_blueprints` and `npc_blueprints` as separate tables behind their own
aggregates/projectors. Add `kind` (CHECK `= 'npc'`) to `npc_blueprints`. Power the unified,
kind-filterable registry (FR-024/FR-025) with a read-layer **UNION** over the common columns
`(id, kind, name, short_description, revision)`.

**Rationale**: NPC blueprints carry fields objects never will (`lore`, `behaviors`, `toolsets`,
`quests`); a shared wide table would rewrite shipped milestone-1 storage for no gain. CQRS already
separates write aggregates from read models, so a union query is the idiomatic heterogeneous list.
(`object_blueprints.kind` already has the CHECK + `kind` column anticipating this.)

**Alternatives rejected**: one unified `blueprints` table (blast radius on shipped 014); a third
registry projector table (extra source of truth; the union query is sub-ms at milestone scale).

## R3 — Toolsets: seed-populated cross-entity table; composition frozen at spawn

**Decision**: A plain Ecto-managed `toolsets` read table (NOT event-sourced, NO aggregate, seed-only
per the spec's resolved clarification): `name` (slug PK), `description`, `behaviors` ({:array,:map}),
`applies_to` ({:array,:string} ⊆ `["item","npc","room"]`), timestamps. An NPC blueprint stores
`toolsets` ({:array,:string} of names) **plus** its own `behaviors` (direct). The **effective**
behavior set = union of (each referenced toolset's behaviors, in attachment order) ++ direct
behaviors, **computed at spawn time** and frozen into the clone.

The clone (`npc_clones`) therefore needs, for faithful extract (FR-012): `behaviors` (frozen
**effective** union, executed by feature 009) + `toolsets` (names referenced) + `direct_behaviors`
(the non-toolset behaviors). `toolsets`/`direct_behaviors` are **new** clone columns added by this
milestone.

**Rationale**: No runtime toolset mutation this milestone ⇒ no aggregate (promote later if wizard
toolset authoring lands). `applies_to` encodes the cross-entity model now (FR-019) though only NPC
attachment UI is wired. Freezing the effective union at spawn honors full-copy (toolset/blueprint
edits never retro-propagate, FR-017) while feature-009 execution keeps reading one `behaviors`
column unchanged. Keeping `toolsets`+`direct_behaviors` on the clone is the minimal provenance for
extract.

**Alternatives rejected**: store only flattened effective behaviors (breaks extract, FR-012);
compute effective at read time (breaks full-copy, FR-017); event-source toolsets (no runtime writes).

## R4 — Toolset composition: additive per trigger, attachment-ordered (FR-016)

**Decision**: Composition is **additive and lossless** — the effective behavior list is the
concatenation, in order, of each referenced toolset's behaviors (in the order toolsets are listed on
the blueprint) followed by the blueprint's direct behaviors. When two sources carry behaviors on the
**same trigger**, all actions are retained and execute in that order; nothing is dropped or
overwritten. Feature 009 already fires all behaviors matching a trigger, so no executor change.

**Rationale**: "No behavior silently dropped" (FR-016) rules out last-wins. Additive union with a
deterministic order (attachment order, then direct) is the simplest rule satisfying deterministic +
lossless, and matches the existing execution model. Exact-duplicate `(trigger, action)` tuples are
not deduped (a seed-authoring smell to surface, not hide) — documented, not silently merged.

## R5 — `list_toolsets` LLM tool + kind-selecting draft tools (spec FR-020/FR-020a)

**Decision**: Extend the existing wizard resolver rather than add a parallel one. `:blueprints`-mode
tool set becomes `{draft_object_blueprint, draft_npc_blueprint, list_toolsets, refuse}`; the system
prompt instructs the LLM to choose `draft_npc_blueprint` for a character/creature and
`draft_object_blueprint` for an item. `:world`-mode: `{manifest_object_freeform,
manifest_npc_freeform, list_toolsets, refuse}`. `draft_npc_blueprint`/`manifest_npc_freeform` extract
`name, short_description, long_description, lore, fixed, behaviors[]` (constrained to the feature-009
vocabulary) and `toolsets[]`. `list_toolsets` is a read tool returning the registered toolsets so
proposals are grounded (FR-020a); proposed names not in the registry are dropped before commit
(FR-018). The resolver returns `{:ok, {:draft_npc_blueprint, fields}}` / `{:ok, {:freeform_npc,
fields}}` / `{:error, refusal}`. The LiveView draft assign gains a `:kind`; `commit_blueprint_draft`
branches on it (`create_object_blueprint` vs `create_npc_blueprint`).

**Rationale**: One resolver with kind-selecting tools keeps draft/commit/registry single-pathed (kind
is just a field on the draft). LLM-proposes / wizard-confirms toolset attachment (FR-020) needs both
the `list_toolsets` grounding tool and the picker on the card.

**Alternatives rejected**: a separate `resolve_wizard_npc_*` entry point (duplicates async-task /
refusal / draft plumbing); free-text toolset names with fuzzy commit-time match (`list_toolsets`
grounding is more reliable and feeds the picker).

## R6 — Spawn / freeform / edit / extract on the merged substrate

**Decision**: All NPC world operations route through the 016 service:
- **Spawn from blueprint** (registry "Spawn here"): a wrapper reads the blueprint, **composes the
  effective behaviors** (R4), and `clone_into(:npc, fields incl. effective `behaviors` + `toolsets` +
  `direct_behaviors` + `lore` + `fixed` + `blueprint_id`, ContainerRef.room(room), :spawned)`.
  (Generalizes the existing `spawn_npc_clone/3` to carry toolsets/direct provenance + composition.)
- **Freeform NPC**: `clone_into(:npc, fields, room, :spawned)` with no blueprint (`blueprint_id`
  nil), behaviors authored directly.
- **Edit in-world NPC**: `EditEntity{entity_id, fields_changed}` (016) → wire the **`EntityProjector`
  `:npc` `EntityEdited` branch** (currently a no-op) to apply the sparse diff to `npc_clones`.
- **Extract essence**: read the clone's `name/short/long/lore/fixed/toolsets/direct_behaviors`,
  populate a `CreateNPCBlueprint` draft; source clone untouched (FR-012).

**Rationale**: The substrate already owns spawn/move/edit; this milestone supplies the NPC-shaped
`fields` and the composition step. Wiring the `:npc` `EntityEdited` branch is the one substrate touch
needed (016 left it a no-op since NPCs weren't edited yet).

**Alternatives rejected**: re-introducing an NPC-specific spawn path (the substrate is the spawn
path now).

## R7 — `fixed` flag carried for parity; per-room NPC name uniqueness preserved

**Decision**: Add `fixed` (boolean, default false) to `npc_blueprints` and the clone fields, for
field/card parity with objects (FR-003). NPC ungettability is already enforced by the existing
`take/2` NPC-resolution refusal; `fixed` is not newly load-bearing. Per-room NPC display-name
uniqueness (feature 007) is preserved by the existing `npc_clones (room_id, lower(name))` index +
the pre-dispatch name-collision check in the spawn wrapper (FR-013).

**Rationale**: FR-003 parity without rewiring the take/examine hot path.

## Resolved unknowns summary

No `NEEDS CLARIFICATION` remain. The spec's clarifications (toolset UX → R5; toolset scope → R3
general-registry-NPC-UI-only; toolset creation → R3 seed-only; fold-in → delivered by 016) and FRs
are all realized above against the merged substrate.
