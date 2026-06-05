# Command Contracts: NPC Blueprints (015)

Blueprint commands route to the `NPCBlueprint` aggregate (`identify(NPCBlueprint, by: :blueprint_id,
prefix: "npc-blueprint-")`, existing). NPC world operations (spawn/move/edit of a clone) route through
the merged **clone/move substrate** (spec 016 — `Entity` aggregate), not a new aggregate.

## CreateNPCBlueprint (altered)
- **Fields**: `blueprint_id, wizard_id, name, short_description, long_description, kind` (`"npc"`),
  `fixed?`, `lore?`, `behaviors?` (direct), `toolsets?` (names), `quests?`.
- **Aggregate**: `id == nil` ⇒ validate required (`name`/`short`/`long`) ⇒ `NPCBlueprintCreated`
  (`revision: 1`); else `{:error, :blueprint_already_exists}`.
- **Wrapper `create_npc_blueprint/2`**: `ensure_wizard/1`; slug regex + uniqueness **across object +
  npc** blueprints (FR-004); behavior-vocabulary + toolset-existence validation; dispatch `:strong`.

## EditNPCBlueprint (new)
- **Fields**: `blueprint_id, wizard_id, expected_revision, fields_changed` (sparse; keys ⊆
  `name, short_description, long_description, fixed, lore, behaviors, toolsets`).
- **Aggregate**: not created ⇒ `:blueprint_not_found`; `expected_revision != current` ⇒
  `{:error, :stale_revision, current_revision: N}`; unknown key ⇒ `:invalid_field`; no-op diff ⇒
  `:ok`; else `NPCBlueprintEdited{fields_changed, revision: N+1}`.
- **Wrapper `edit_npc_blueprint/3`**: `ensure_wizard/1`; surfaces stale revision to the form.

## NPC world operations (via the 016 service)
- `spawn_npc_from_blueprint(wizard_id, blueprint_id, room_id)` — `ensure_wizard`; read blueprint;
  `compose(toolsets, direct_behaviors)` → effective behaviors; `clone_into(:npc, %{name, short,
  long, lore, fixed, behaviors: effective, toolsets, direct_behaviors, blueprint_id},
  ContainerRef.room(room_id), :spawned)`; ⇒ `{:ok, clone_id}`. Pre-check: blueprint exists, room
  exists, no per-room name collision (FR-013).
- `spawn_npc_freeform(wizard_id, room_id, attrs)` — `ensure_wizard`; `clone_into(:npc, attrs, room,
  :spawned)` (no `blueprint_id`).
- `edit_npc(wizard_id, npc_id, fields_changed)` — `ensure_wizard` + co-location; `EditEntity{entity_id:
  npc_id, fields_changed}`. (Requires wiring the `EntityProjector` `:npc` `EntityEdited` branch.)
- `extract_npc_essence(wizard_id, npc_id, proposed_slug)` — `ensure_wizard`; read clone fields (incl.
  `toolsets`/`direct_behaviors`); `create_npc_blueprint` at revision 1; **source clone untouched**.

## Toolset service (read-only; seed-populated)
- `list_toolsets/0` ⇒ `[%{name, description, behaviors, applies_to}]` (backs LLM tool + picker).
- `resolve(names)` ⇒ `{:ok, [behaviors]} | {:error, {:unknown_toolset, name}}`.
- `compose(toolset_names, direct_behaviors)` ⇒ effective behavior list (additive, attachment-ordered).

## Refusals (shared)
`:not_a_wizard`, `:unknown_player`, `:invalid_slug`, `:slug_already_exists`, `:name_required` /
`:short_description_required` / `:long_description_required`, `:unknown_toolset`,
`:invalid_behavior`, `:stale_revision`, `:invalid_field`, `:blueprint_not_found`,
`:clone_name_taken_in_room`.
