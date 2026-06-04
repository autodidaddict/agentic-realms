# Event Contracts: Entity Lifecycle (016)

Containers serialize as maps `%{"type" => "...", "id" => ... | null}`. All events `version: 1`.

## EntityCloned
- **Payload**: `entity_id`, `kind` (`"object"|"npc"`), `fields` (kind-shaped map).
- **Meaning**: entity now exists, contained by the void. **No UI broadcast** (silent creation).
- **Projection** (`EntityProjector`): insert a row into `world_objects` (object) or `npc_clones`
  (npc) with `fields` + `container_type="void"`, `container_id=nil`. `on_conflict: :nothing`.

## EntityMoved
- **Payload**: `entity_id`, `from` (ContainerRef map), `to` (ContainerRef map), `cause`
  (`"spawned"|"placed"|"taken"|"dropped"|"relocated"`).
- **Meaning**: entity relocated; `to` is authoritative.
- **Projection**: set the row's `container_type`/`container_id` to `to` (idempotent absolute write).
- **UI** (`UIEventBroadcaster`, maps `(kind, cause, from.type→to.type)`):
  | kind/cause/route | broadcast |
  |---|---|
  | object/spawned/void→room | `RoomObjectArrived` |
  | object/placed/void→room | none (silent; quest scope preserved) |
  | object/taken/room→player | `RoomObjectTaken` + `PlayerInventoryChanged(:added)` (+ quest progress) |
  | object/dropped/player→room | `RoomObjectDropped` + `PlayerInventoryChanged(:removed)` (+ quest progress) |
  | npc/spawned/void→room | `RoomNPCArrived` |
  | */→void | none |
  | object/relocated/room→room | `RoomObjectArrived` in dest (+ minimal departure in source) |

## EntityEdited
- **Payload**: `entity_id`, `fields_changed` (sparse map).
- **Projection**: apply diff to the read row.
- **UI**: `RoomObjectEdited` (quiet) when the entity is in a room, as today.

## Removed events (retrofit; destroyable log — not replayed)
`ObjectPlacedInRoom`, `ObjectSpawned`, `ObjectTakenFromRoom`, `ObjectDroppedInRoom`, `ObjectEdited`,
`NPCClonedFromBlueprint`, `NPCSpawnedInRoom`.

## Invariant checks (test surface)
- Post-clone: row present, `container_type="void"`.
- Post-move: exactly one container; read row reflects `to`.
- No-op move: no `EntityMoved` emitted.
- Concurrent moves of one entity: terminal state is a single container (stream serialization).
