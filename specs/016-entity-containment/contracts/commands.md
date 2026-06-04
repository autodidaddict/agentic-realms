# Command Contracts: Entity Lifecycle (016)

All commands route to the `Entity` aggregate (`identify(Entity, by: :entity_id, prefix: "entity-")`).
`ContainerRef` = `%{type: :void|:room|:player|:npc, id: term|nil}` (void ⇒ id nil).

## CloneEntity
- **Fields**: `entity_id` (binary_id, required), `kind` (`:object|:npc`, required), `fields` (map,
  required — kind-shaped frozen read-model fields).
- **Aggregate guard**: `id == nil` ⇒ emit `EntityCloned`; else `{:error, :already_exists}`.
- **Result**: entity exists with `container = void`.

## MoveEntity
- **Fields**: `entity_id` (required), `expected_from` (ContainerRef, required — the container the
  caller resolved the entity in), `to` (ContainerRef, required), `cause`
  (`:spawned|:placed|:taken|:dropped|:relocated`).
- **Aggregate guards** (evaluated in order):
  - not created ⇒ `{:error, :not_found}`
  - `to.type` not in supported set ⇒ `{:error, :unsupported_container}`
  - `to == current container` ⇒ `:ok` (no event) *(FR-009)*
  - `expected_from != current container` ⇒ `{:error, :container_conflict}` *(FR-005 — the entity's
    actual container is authoritative; a stale/concurrent move is refused, not silently applied, so
    a second `take` of an already-taken object fails instead of stealing it)*
  - else emit `EntityMoved{from: <current>, to, cause}`.
- **Wrapper pre-checks (`move_entity/4`)**: destination container row exists; for `to.type=:room`,
  no name collision in destination *(feature 007, FR-010/FR-012b)*; `ensure_wizard/1` on wizard-only
  callers. The wrapper passes the resolved source as `expected_from`; a `:container_conflict`
  surfaces to the caller as "no longer there" (e.g. already taken).

## EditEntity
- **Fields**: `entity_id` (required), `fields_changed` (sparse map).
- **Aggregate guards**: not created ⇒ `{:error, :not_found}`; empty/no-op diff ⇒ `:ok` (no event);
  else emit `EntityEdited`.

## Service wrappers (thin world service, not commands)
- `clone_entity(kind, fields) ⇒ {:ok, entity_id}` — mints id, dispatches `CloneEntity`.
- `move_entity(entity_id, to, cause) ⇒ :ok | {:error, reason}`.
- `move_entity(entity_id, expected_from, to, cause) ⇒ :ok | {:error, reason}` — `:container_conflict`
  when the entity is no longer in `expected_from`.
- `clone_into(kind, fields, to, cause) ⇒ {:ok, entity_id}` — clone then `move_entity(id, void, to,
  cause)`; move failure leaves the entity in the void *(FR-003)*.

## Removed commands (retrofit)
`PlaceObject`, `SpawnObjectFromBlueprint`, `SpawnObjectFreeform`, `TakeObject`, `DropObject`,
`EditObject`, `SpawnNPCClone` — all re-expressed via the wrappers above.
