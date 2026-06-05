# Event Contracts: NPC Blueprints (015)

Blueprint-lifecycle events (this milestone). NPC spawn/move/edit of clones use the substrate's
`EntityCloned`/`EntityMoved`/`EntityEdited` (spec 016) — unchanged here.

## NPCBlueprintCreated (altered)
- **Payload**: `blueprint_id, kind` (`"npc"`), `name, short_description, long_description, fixed,
  lore, behaviors` (direct), `toolsets` (names), `quests, revision` (= 1). `version: 1`.
- **Projection** (`NPCBlueprintProjector`): insert `npc_blueprints` row with all fields. Idempotent
  (`on_conflict: :nothing`).

## NPCBlueprintEdited (new)
- **Payload**: `blueprint_id, fields_changed` (sparse), `revision`. `version: 1`.
- **Projection**: merge `fields_changed` + set `revision`, guarded `existing.revision <
  event.revision` (replay-safe).
- **UI**: `WizardBlueprintRegistryChanged` on the `blueprints` topic (reuse feature 014) so open
  wizard registries patch live.

## Substrate events consumed (spec 016) — not defined here
- `EntityCloned{kind: :npc, fields}` → `EntityProjector` inserts `npc_clones` (fields incl.
  `blueprint_id, serial, name, short, long, lore, behaviors` (effective), `fixed, toolsets,
  direct_behaviors`); born in the void.
- `EntityMoved{kind: :npc, …, cause: :spawned}` → set `room_id`; `UIEventBroadcaster` → `RoomNPCArrived`.
- `EntityEdited{kind: :npc, fields_changed}` → apply sparse diff to `npc_clones` (**branch to be
  wired** — 016 left it a no-op).

## Invariant checks (test surface)
- Blueprint create → `npc_blueprints` row at `revision: 1`, `kind: "npc"`.
- Edit bumps revision only on a real diff; stale edit → `:stale_revision`.
- Effective behaviors on a spawned clone = union(toolsets ++ direct), no dupes dropped (FR-016/SC-004).
- Blueprint/toolset edit does not alter previously-spawned clones (FR-009/FR-017/SC-003).
- Extract draft == source clone fields (incl. toolsets/direct); source unchanged (FR-012/SC-005).
- Slug unique across both blueprint kinds (FR-004/SC-008).
