# Command Contracts: Entity Lifecycle (016)

All commands route to the `Entity` aggregate (`identify(Entity, by: :entity_id, prefix: "entity-")`).
`ContainerRef` = `%{type: :void|:room|:player|:npc, id: term|nil}` (void ⇒ id nil).

## CloneEntity
- **Fields**: `entity_id` (binary_id, required), `kind` (`:object|:npc`, required), `fields` (map,
  required — kind-shaped frozen read-model fields).
- **Aggregate guard**: `id == nil` ⇒ emit `EntityCloned`; else `{:error, :already_exists}`.
- **Result**: entity exists with `container = void`.

## MoveEntity
- **Fields**: `entity_id` (required), `from` (ContainerRef), `to` (ContainerRef, required), `cause`
  (`:spawned|:placed|:taken|:dropped|:relocated`).
- **Aggregate guards**:
  - not created ⇒ `{:error, :not_found}`
  - `to.type` not in supported set ⇒ `{:error, :unsupported_container}`
  - `to == current container` ⇒ `:ok` (no event) *(FR-009)*
  - else emit `EntityMoved{from: <current>, to, cause}` — current container authoritative over
    supplied `from` *(FR-005)*.
- **Wrapper pre-checks (`move_entity/3`)**: destination container row exists; for `to.type=:room`,
  no name collision in destination *(feature 007, FR-010/FR-012b)*; `ensure_wizard/1` on wizard-only
  callers.

## EditEntity
- **Fields**: `entity_id` (required), `fields_changed` (sparse map).
- **Aggregate guards**: not created ⇒ `{:error, :not_found}`; empty/no-op diff ⇒ `:ok` (no event);
  else emit `EntityEdited`.

## Service wrappers (thin world service, not commands)
- `clone_entity(kind, fields) ⇒ {:ok, entity_id}` — mints id, dispatches `CloneEntity`.
- `move_entity(entity_id, to, cause) ⇒ :ok | {:error, reason}`.
- `clone_into(kind, fields, to, cause) ⇒ {:ok, entity_id}` — clone then move; move failure leaves the
  entity in the void *(FR-003)*.

## Removed commands (retrofit)
`PlaceObject`, `SpawnObjectFromBlueprint`, `SpawnObjectFreeform`, `TakeObject`, `DropObject`,
`EditObject`, `SpawnNPCClone` — all re-expressed via the wrappers above.
