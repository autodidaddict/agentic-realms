# Contract — Domain: NPC Removal Command/Event + Lifecycle Subscriptions

The write-side additions and the event subscriptions that drive the mind
lifecycle. All event-sourced through the existing `Entity` aggregate (feature
016). Principle II: aggregate is sole writer; read model changes only via
projector.

## Command → Event

### `RemoveEntity` (new)
```
%AgenticRealms.World.Commands.RemoveEntity{ entity_id: <uuid> }
```
Routed to `Entity`. Facade: `AgenticRealms.World.Commands.remove_entity/1`
(and `remove_npc/1`), `consistency: :strong`. Returns `:ok | {:error, :not_found}`.

`Entity.execute/2`:
- unknown / already removed → `{:error, :not_found}` (idempotent at the aggregate)
- otherwise → emit `EntityRemoved`

### `EntityRemoved` (new)
```
%AgenticRealms.World.Events.EntityRemoved{
  entity_id: <uuid>,
  kind:      :npc | :object,     # from aggregate state
  from:      %{type: :room|:void|..., id: <id|nil>},   # container at removal (for witness)
  version:   1
}
```
`@derive Jason.Encoder`. `Entity.apply/2` marks the aggregate removed;
`AggregateLifespan` returns `:stop` on `EntityRemoved`.

## Projector reaction (read model)

`handle(%EntityRemoved{entity_id: id, kind: :npc}, _)` → delete `npc_clones` row
`id` (delete-by-pk; idempotent/replay-safe). `kind: :object` → delete
`world_objects` row `id`.

**Invariant**: no `npc_clones` row survives an `EntityRemoved{:npc}` — required so
the reconciler does not resurrect the terminated mind.

## Witness reaction (players)

In `UIEventBroadcaster`:
- **new** `witness_object_move(:npc, :relocated, %ContainerRef{type: :room, id: from}, %ContainerRef{type: :room, id: to}, id)`
  → `RoomNPCLeft` to `room:from` + `RoomNPCArrived` to `room:to` (name via
  `lookup_npc_name/1`).
- **new** on `EntityRemoved{kind: :npc, from: %{type: :room, id: rid}}` → broadcast
  `RoomNPCLeft` to `room:rid`.

`GameLive`: add `handle_info(%RoomNPCLeft{})` → `UIEvents.npc_left/2` (append
departure log; no Presence mutation).

## Lifecycle subscriptions (`NpcMinds.LifecycleManager`, Commanded event handler)

`use Commanded.Event.Handler, application: AgenticRealms.World.Application, name:
__MODULE__, consistency: :eventual` (exclusive cluster-wide subscriber).

| Event matched | Action | Contract call |
|---|---|---|
| `EntityCloned{kind: :npc}` | start the NPC's mind | `TemporalClient.start_workflow(entity_id)` |
| `EntityRemoved{kind: :npc}` | terminate the NPC's mind | `TemporalClient.terminate_workflow(entity_id)` |
| (all others) | ignore | `:ok` |

Handler failures are logged and swallowed (best-effort; the reconciler is the
backstop) — a Temporal outage must not stall the subscription or the world.

## Transient-purge terminate (out-of-band)

In `AgenticRealms.World.Transient.Purge`, for each `npc_id` it removes
(collected at the existing npc-ids query), call
`TemporalClient.terminate_workflow(npc_id)` best-effort **before** deleting the
read-model rows. The purge deletes the entity stream, so it cannot carry an
`EntityRemoved` event — hence the direct call. Failure to terminate never blocks
or fails the purge.

## Cluster semantics (Principle I)

- `LifecycleManager` — named Commanded handler ⇒ exactly one node handles each
  event.
- `Reconciler` — cluster-wide singleton (Horde-registered; `:global` fallback).
- Controller/auth plug — stateless, request-scoped (node-local correct).
