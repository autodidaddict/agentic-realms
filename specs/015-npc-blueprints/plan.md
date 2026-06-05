# Implementation Plan: Wizard-Created NPC Blueprints (Milestone 2)

**Branch**: `015-npc-blueprints` | **Date**: 2026-06-05 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/015-npc-blueprints/spec.md`

## Summary

Extend the feature-014 wizard-authoring pipeline to **NPCs** as a second blueprint `kind`, riding on
the merged clone/move substrate (spec 016). A wizard can author an NPC blueprint in a trance
(name, descriptions, **lore**, **behaviors**, **composable toolsets**), edit it (revision +
optimistic lock), spawn clones into a room (`clone_into(:npc, …)` with toolset-composed behaviors),
freeform one-offs, edit an in-world clone in place, extract a blueprint from a clone, and browse a
**unified registry** filterable by kind.

Key reuse / build-on:
- **Mirror milestone 1**: add `revision` + `EditNPCBlueprint` to the `NPCBlueprint` aggregate; a
  `NPCBlueprintProjector`; create/edit/spawn/freeform/edit/extract `Commands` wrappers; the LLM
  resolver tools + GameLive wizard handlers + `game_components` wizard view; the
  `WizardBlueprintRegistryChanged` broadcast. (R1)
- **Ride spec 016**: spawning is `clone_into(:npc, …)`; the in-place clone edit is `EditEntity` (wire
  the `EntityProjector` `:npc` `EntityEdited` branch, currently a no-op). The feature-008 fold-in is
  already done in 016. (R6)
- **Toolsets** (new): a seed-populated cross-entity `toolsets` table; blueprints reference toolsets by
  name; effective behaviors = union(toolsets ++ direct), composed and **frozen at spawn**; a
  `list_toolsets` LLM tool + picker (LLM-proposes / wizard-confirms). (R3–R5)
- **Unified registry**: a read-layer UNION over `object_blueprints` + `npc_blueprints`. (R2)

Resolved decisions and rationale: [research.md](./research.md). Concrete shapes:
[data-model.md](./data-model.md), [contracts/](./contracts/).

## Technical Context

**Language/Version**: Elixir 1.20 on OTP 26+ (project baseline).

**Primary Dependencies (existing, reused — no new dependencies)**:
- `commanded ~> 1.4` — `NPCBlueprint` aggregate gains `EditNPCBlueprint`/`revision`; spawn rides the
  `Entity` aggregate (016).
- `ecto_sql ~> 3.11` + `postgrex` — migrations: `npc_blueprints` (+`kind`/`fixed`/`revision`/
  `toolsets`), `npc_clones` (+`fixed`/`toolsets`/`direct_behaviors`), new `toolsets` table.
- `phoenix_live_view ~> 1.1` — wizard authoring surface extended for `kind: :npc`.
- `req`/Anthropic client — the existing wizard `IntentResolver` gains NPC draft tools + `list_toolsets`.

**Reused project infrastructure** (extend, don't rebuild):
- `AgenticRealms.World.NPCBlueprint`, `Commands`, `IntentResolver` (+`WizardTools`),
  `GameLive` + `GameComponents` wizard view, `UIEventBroadcaster` (`WizardBlueprintRegistryChanged`),
  `Queries`, `Seed`.
- Spec 016: `Entity` aggregate, `Commands.clone_into/4` / `move_entity/4` / `EditEntity`,
  `EntityProjector` (wire the `:npc` edit branch).

**Storage**: see data-model §1 — two altered tables + one new `toolsets` table; all replay-safe;
`toolsets` is plain seed data (not event-sourced). Slug uniqueness spans **both** blueprint tables.

**Testing** (`ExUnit`):
- `NPCBlueprint` aggregate: create (kind/fixed/toolsets/revision 1), edit (revision bump, no-op skip,
  stale-revision, invalid-field).
- `NPCBlueprintProjector`: create/edit projections, replay-safe.
- Toolset service: `resolve`/`compose` (union, attachment order, lossless), unknown-toolset refusal,
  behavior-vocabulary validation.
- Wrappers: create (slug uniqueness across both kinds, toolset/behavior validation, authz),
  edit (optimistic lock), `spawn_npc_from_blueprint` (effective-behavior composition + clone in room),
  freeform, `edit_npc` (in-place), `extract_npc_essence` (fidelity incl. toolsets; source untouched).
- LiveView: trance authoring (mocked LLM), toolset picker pre-selected from proposal, spawn-here,
  edit, extract, unified registry filter.
- Non-regression: 007–010 NPC behavior + the 016 suite stay green.

**Target Platform**: Linux server BEAM (prod); macOS single-node (dev). **Project Type**: Phoenix
LiveView web app.

**Performance Goals**: author end-to-end ≤ 120s p95 (LLM-dominated, SC-001); spawn→arrival ≤ 2s p95
(SC-002, the substrate budget); registry union query sub-ms at milestone scale.

**Constraints**: No new dependencies. No regression to 006/007/008/009/010/013/014/016. Effective
behaviors frozen at spawn (no retro-propagation).

**Scale/Scope**: ~1 altered aggregate (+edit), 1 new projector, 3 migrations, 1 new toolset
service + table, ~6 command wrappers, LLM resolver + LiveView + components extension, seed toolsets.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The project constitution (`.specify/memory/constitution.md`) is an **unratified template** — no
enumerated gates. Against the de-facto conventions (features 012–016): no new dependencies ✓;
event-sourced aggregates + replay-safe projectors ✓ (toolsets are seed read-data, justified by
no-runtime-writes per R3); reuse-over-rebuild ✓; test surface ships with the feature ✓; no
player-visible regression ✓. **Result: PASS** — no Complexity Tracking entries required.

*Post-Phase-1 re-check*: design adds one aggregate command, one projector, one seed table, and
extends shipped surfaces; rides the substrate for all world mutation. PASS.

## Project Structure

### Documentation (this feature)

```text
specs/015-npc-blueprints/
├── plan.md · research.md · data-model.md · quickstart.md
├── contracts/{commands,events}.md
└── tasks.md   # Phase 2 (/speckit.tasks — not created here)
```

### Source Code (existing single Phoenix project)

```text
lib/agenticrealms/world/
├── npc_blueprint.ex                  # ALTERED — +revision, +EditNPCBlueprint, +kind/fixed/toolsets
├── toolsets.ex                       # NEW — list/resolve/compose/validate
├── commands.ex                       # ALTERED — create/edit_npc_blueprint, spawn_npc_from_blueprint
│                                     #   (compose), spawn_npc_freeform, edit_npc, extract_npc_essence
├── commands/{create_npc_blueprint(alt),edit_npc_blueprint(new)}.ex
├── events/{npc_blueprint_created(alt),npc_blueprint_edited(new)}.ex
├── intent_resolver.ex + intent_resolver/wizard_tools.ex  # ALTERED — draft_npc_blueprint,
│                                     #   manifest_npc_freeform, list_toolsets
├── projections/{npc_blueprint_projector(new), entity_projector(wire :npc edit)}.ex
├── queries.ex                        # ALTERED — list_blueprints union; get_npc_blueprint
├── seed.ex                           # ALTERED — seed ≥2 toolsets
└── schemas/{npc_blueprint(alt), npc_clone(alt), toolset(new)}.ex

lib/agenticrealms_web/live/game_live.ex (+ game_live/*)   # ALTERED — kind-aware draft/commit/spawn/edit/extract
lib/agenticrealms_web/components/game/wizard_authoring.ex # ALTERED — NPC fields + toolset picker
priv/repo/migrations/
├── <ts>_extend_npc_blueprints_authoring.exs   # NEW (kind/fixed/revision/toolsets)
├── <ts>_extend_npc_clones_authoring.exs        # NEW (fixed/toolsets/direct_behaviors)
└── <ts>_create_toolsets.exs                    # NEW
```

**Structure Decision**: Existing single Phoenix layout (identical to 012–016). All under
`lib/agenticrealms/world/`, `…_web/`, and `priv/repo/migrations/`.

## Phasing (for /speckit.tasks)

1. **Foundational** — migrations (npc_blueprints, npc_clones, toolsets) + schemas; `toolsets` service;
   seed ≥2 toolsets. (Blocks the rest.)
2. **Blueprint authoring (US1)** — `NPCBlueprint` create with kind/fixed/toolsets; `NPCBlueprintProjector`;
   `create_npc_blueprint` wrapper (slug uniqueness across kinds, validation); LLM `draft_npc_blueprint`
   + `list_toolsets`; GameLive draft + toolset picker; commit.
3. **Toolset composition (US4)** — `compose/2`; spawn carries effective behaviors + provenance.
4. **Spawn / freeform (US2/US5)** — `spawn_npc_from_blueprint` (compose → clone_into), `spawn_npc_freeform`;
   registry "Spawn here".
5. **Edit / extract (US6/US7)** — `EditNPCBlueprint` (+optimistic lock); wire `EntityProjector` `:npc`
   edit; `edit_npc`; `extract_npc_essence`.
6. **Unified registry (US8)** — `list_blueprints` union + kind filter in the registry UI.
7. **Polish** — non-regression gate (007–010 + 016), quickstart, format.

## Complexity Tracking

No Constitution Check violations — section intentionally empty.
