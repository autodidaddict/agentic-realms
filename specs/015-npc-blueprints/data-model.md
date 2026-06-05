# Phase 1 Data Model: Wizard-Created NPC Blueprints (Milestone 2)

**Feature**: 015-npc-blueprints | **Date**: 2026-06-05 | **Depends on**: [research.md](./research.md)

Repo-root-relative paths. "Existing" = shipped by 007/008/009/010/013/016; "new"/"altered" describe
this milestone. The shape mirrors milestone-1 Objects ([014 data-model](../014-item-blueprints/data-model.md))
and rides the merged clone/move substrate ([016 data-model](../016-entity-containment/data-model.md)).

---

## 1. Read-model schema changes (Ecto migrations)

### 1.1 `npc_blueprints` — altered (`lib/agenticrealms/world/schemas/npc_blueprint.ex`)

| Column | Change |
|---|---|
| `id` | existing — slug PK; add CHECK `^[a-z][a-z0-9_]*$`, len 1–64 (FR-004) |
| `kind` | **new** — string NOT NULL DEFAULT `'npc'`, CHECK `= 'npc'` (union registry) |
| `name`, `short_description`, `long_description`, `lore`, `behaviors`, `quests` | existing |
| `fixed` | **new** — boolean NOT NULL DEFAULT `false` (parity, R7) |
| `toolsets` | **new** — `{:array,:string}` NOT NULL DEFAULT `[]` — referenced toolset names (R3) |
| `revision` | **new** — integer NOT NULL DEFAULT 1, CHECK `> 0` (optimistic lock, R1) |
| `is_synthetic` | existing — now dead (016); leave, always `false` |

`behaviors` here = **direct** behaviors only. Index on `kind`.

### 1.2 `npc_clones` — altered (`lib/agenticrealms/world/schemas/npc_clone.ex`)

| Column | Change |
|---|---|
| `name, short_description, long_description, lore, behaviors, serial, blueprint_id, room_id` | existing (016) |
| `behaviors` | semantics: the frozen **effective** union (executed by feature 009) |
| `fixed` | **new** — boolean NOT NULL DEFAULT `false` |
| `toolsets` | **new** — `{:array,:string}` — frozen toolset names (extract provenance, R3) |
| `direct_behaviors` | **new** — `{:array,:map}` — frozen direct behaviors (extract provenance, R3) |

### 1.3 `toolsets` — new table (`lib/agenticrealms/world/schemas/toolset.ex`)

Plain Ecto read table, seed-populated, NOT event-sourced (R3).

| Column | Type | Notes |
|---|---|---|
| `name` | string PK | slug `^[a-z][a-z0-9_]*$` |
| `description` | string NULL | picker copy |
| `behaviors` | `{:array,:map}` NOT NULL DEFAULT `[]` | feature-009 `(trigger,[action])` tuples |
| `applies_to` | `{:array,:string}` NOT NULL DEFAULT `['npc']` | ⊆ `{item,npc,room}`, CHECK each elem in set |
| timestamps | utc_datetime | |

Seeded via direct `Repo` upsert in the seed module; ≥2 toolsets so US4 is demonstrable.

---

## 2. Aggregate: `NPCBlueprint` — altered (`lib/agenticrealms/world/npc_blueprint.ex`)

**Struct** (add): `kind: "npc", fixed: false, toolsets: [], revision: 0`.

**`execute/2`**:
- `CreateNPCBlueprint` — validate required (`name`, `short_description`, `long_description`); emit
  `NPCBlueprintCreated` with `kind: "npc"`, `fixed`, `toolsets`, `revision: 1`. Already-created →
  `{:error, :blueprint_already_exists}`.
- `EditNPCBlueprint` — **new** — optimistic lock on `expected_revision` (else `{:error,
  :stale_revision, current_revision: N}`); keys ⊆ `name, short_description, long_description, fixed,
  lore, behaviors, toolsets`; no-op diff → `:ok`; else `NPCBlueprintEdited{fields_changed,
  revision: N+1}`. Unknown key → `{:error, :invalid_field}`. (Mirror `ObjectBlueprint`.)

**`apply/2`**: `NPCBlueprintCreated` sets all fields + `revision`; `NPCBlueprintEdited` merges sparse
diff + updates `revision`.

---

## 3. Commands (`lib/agenticrealms/world/commands/`)

| Command | Routed to | Fields | Status |
|---|---|---|---|
| `CreateNPCBlueprint` | NPCBlueprint | + `wizard_id, kind, fixed, toolsets` (keep `lore/behaviors/quests`) | **altered** |
| `EditNPCBlueprint` | NPCBlueprint | `blueprint_id, wizard_id, expected_revision, fields_changed` | **new** |

**Service wrappers** (`commands.ex`):

| Wrapper | Behavior |
|---|---|
| `create_npc_blueprint/2` | authz `ensure_wizard`; slug validate + uniqueness **across both blueprint tables** (FR-004); toolset-existence + behavior-vocabulary validation; dispatch |
| `edit_npc_blueprint/3` | authz; optimistic-lock edit (mirror `edit_object_blueprint/3`) |
| `spawn_npc_from_blueprint/3` | authz; read blueprint; **compose effective behaviors** (R4); `clone_into(:npc, fields incl. effective behaviors + toolsets + direct_behaviors + lore + fixed + blueprint_id, room, :spawned)` |
| `spawn_npc_freeform/3` | authz; `clone_into(:npc, fields, room, :spawned)` (no blueprint) |
| `edit_npc/3` | authz + co-location; `EditEntity{npc_id, fields_changed}` (016) |
| `extract_npc_essence/3` | authz; read clone (incl. toolsets/direct_behaviors); `CreateNPCBlueprint` at revision 1; source untouched |

(The existing `spawn_npc_clone/3` from 016 is generalized into `spawn_npc_from_blueprint/3` carrying
toolset/composition; the seed keeps working through it.)

---

## 4. Events (`lib/agenticrealms/world/events/`)

| Event | Payload | Status |
|---|---|---|
| `NPCBlueprintCreated` | + `kind, fixed, toolsets, revision` | **altered** |
| `NPCBlueprintEdited` | `blueprint_id, fields_changed, revision` | **new** |

NPC **spawn/move/edit** events are `EntityCloned`/`EntityMoved`/`EntityEdited` (016) — unchanged.

---

## 5. Projectors

- **`NPCBlueprintProjector`** (new, or extend `WorldProjector`): `NPCBlueprintCreated` → upsert
  `npc_blueprints` (now with `kind, fixed, toolsets, revision`); `NPCBlueprintEdited` → merge sparse
  diff + set `revision`, guard `existing.revision < event.revision` (replay-safe). Supervised in
  `application.ex` + `data_case.ex`.
- **`EntityProjector`** (016) — wire the `:npc` `EntityEdited` branch (currently `:ok` no-op) to apply
  the sparse diff to `npc_clones`; `EntityCloned(:npc)` insert gains `fixed/toolsets/direct_behaviors`.

---

## 6. Toolset resolution (new module `lib/agenticrealms/world/toolsets.ex`)

- `list/0` / `list_for(:npc)` — read `toolsets` (backs `list_toolsets` LLM tool + picker).
- `resolve(names)` → `{:ok, [behaviors]} | {:error, {:unknown_toolset, name}}` (FR-018).
- `compose(toolset_names, direct_behaviors)` → effective list = concat(resolved toolsets in order) ++
  direct (R4).
- `validate_behaviors/1` — reuse `Behaviors.Validator`; reject non-feature-009 triggers/actions (FR-014).

---

## 7. Read queries (`lib/agenticrealms/world/queries.ex`)

- `list_blueprints/0` / `list_blueprints(kind)` — **new** UNION over `object_blueprints` +
  `npc_blueprints` projecting `(id, kind, name, short_description, revision)` (FR-024/FR-025).
- `get_npc_blueprint/1` — full row for the edit-focus draft + spawn composition.
- `list_npcs_in_room/1`, `resolve_npc_in_room/2`, `get_npc_clone/1` — existing (read `npc_clones`).

---

## 8. LLM resolver + LiveView (mirror 014)

- `IntentResolver`: `:blueprints` tools `{draft_object_blueprint, draft_npc_blueprint, list_toolsets,
  refuse}`; `:world` tools `{manifest_object_freeform, manifest_npc_freeform, list_toolsets, refuse}`
  (R5). Returns `{:ok, {:draft_npc_blueprint, fields}}` / `{:ok, {:freeform_npc, fields}}`.
- `GameLive`: draft assign gains `:kind`; `commit_blueprint_draft` branches object/npc; new "Spawn
  here" for npc rows; focus/edit for npc clones; extract for npc.
- `game_components` wizard view: render NPC-specific fields (lore, direct behaviors editor, **toolset
  picker** pre-selected from LLM proposal, FR-020).
- `UIEventBroadcaster`: NPC blueprint create/edit → `WizardBlueprintRegistryChanged` on the
  `blueprints` topic (reuse 014); NPC arrival already via `EntityMoved` (016).

---

## 9. Validation rules (consolidated)

- Slug `^[a-z][a-z0-9_]*$`, unique **across both** blueprint tables (FR-004).
- Required: `name`, `short_description`, `long_description` non-empty.
- Behaviors (direct + toolset) validate against the feature-009 vocabulary; else rejected (FR-014).
- Referenced toolset names must exist in `toolsets` (FR-018).
- Per-room NPC name uniqueness preserved (FR-013) — `npc_clones (room_id, lower(name))` + spawn
  pre-check.
- `EditNPCBlueprint.expected_revision` must equal current (FR-005).
- Every wizard wrapper calls `ensure_wizard/1` (FR-006).
- Effective behaviors frozen at spawn; blueprint/toolset edits never retro-propagate (FR-009/FR-017).
