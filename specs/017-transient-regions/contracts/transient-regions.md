# Contracts: Transient Regions

This feature exposes no HTTP/external API. Its "contracts" are the **commands/events** the domain accepts/emits, the **`Transient` context API** (the programmatic provisioning surface — FR-001 "system-initiated, no player command"), the **query/movement changes** that enforce owner-only exits, the **lifecycle/purge** module surface, and the **config keys**.

---

## 1. Commands (dispatched via `AgenticRealms.World.Router` → `Region`)

```text
ProvisionTransientRegion
  region_id          :: binary_id      # generated
  name               :: String.t()
  provision_owner_id :: binary_id      # the player the region belongs to
  provisioned_at     :: DateTime.t()   # set by dispatcher (lifetime anchor)
  source_room_id     :: binary_id      # permanent room the owner provisions from
  origin_room_id     :: binary_id      # transient entry room (generated)
  → emits TransientRegionProvisioned | {:error, :region_already_exists}

OpenTransientEntryExit
  region_id          :: binary_id
  source_room_id     :: binary_id      # permanent source room
  direction          :: :rift
  origin_room_id     :: binary_id      # transient target
  provision_owner_id :: binary_id      # becomes visible_to_user_id
  → emits TransientEntryExitOpened | {:error, :region_not_found | :not_transient}

DestroyRegion
  region_id          :: binary_id
  → emits RegionDestroyed | :ok (no-op if already destroyed — idempotent, FR-015)
```

Transient rooms + their intra-region/return exits are created with the **existing** `CreateRoom` / `AddExit` commands (no new contracts).

---

## 2. Events

```text
TransientRegionProvisioned {region_id, name, provision_owner_id, provisioned_at, source_room_id, origin_room_id, version: 1}
TransientEntryExitOpened    {region_id, source_room_id, direction, target_room_id, visible_to_user_id, version: 1}
RegionDestroyed             {region_id, version: 1}
```

**Projector reactions** (`WorldProjector`):
- `TransientRegionProvisioned` → insert `regions` row (`kind: "transient"`, owner/provisioned_at/source/origin).
- `TransientEntryExitOpened` → insert `world_exits` row (`visible_to_user_id` = owner, `direction = "rift"`).
- `RegionDestroyed` → **evict only** (lifespan `:stop`); optionally stamp `regions.destroyed_at`. Row deletion is owned by `Transient.Purge` (see §5), not this handler.

---

## 3. `AgenticRealms.World.Transient` context API (NEW)

```elixir
@doc "Provision a transient region for `owner_id`, sourced from `source_room_id`. Orchestrates generate → guard → dispatch(region, rooms, exits, entry-exit) → place owner. Returns the new region id."
@spec provision(owner_id :: binary, source_room_id :: binary) ::
        {:ok, region_id :: binary}
        | {:error, :already_provisioned}      # FR-021 (one active region per owner)
        | {:error, term}

@doc "Force-destroy + purge a transient region now (used by the reaper and by tests/ops)."
@spec destroy(region_id :: binary) :: :ok

@doc "Generate (but do not dispatch) a deterministic region spec — pure, testable."
@spec Generator.generate(owner_id :: binary, source_room_id :: binary) :: region_spec
```

`region_spec` (pure, from `Transient.Generator`):
```text
%{region_id, name, origin_room_id,
  rooms: [%{room_id, name, description}],
  intra_exits: [%{from, direction, to}],     # incl. origin→source return exit
  entry_exit: %{source_room_id, direction: :rift, target_room_id: origin_room_id}}
```

---

## 4. Query / movement contract changes (owner-only enforcement)

```elixir
# Queries.list_exits/2  (was /1) — viewer-aware visibility (FR: owner-only exit visible only to owner)
list_exits(room_id, viewer_player_id)
  # adds: where is_nil(e.visible_to_user_id) or e.visible_to_user_id == ^viewer_player_id

# Commands.resolve_exit/3  (was /2) — viewer-aware traversal
resolve_exit(from_room_id, direction, viewer_player_id)
  # non-owner → :no_exit_in_direction → existing "You can't go that way."
```

Both callers (`look_room/1`, `move/2`) already hold the viewer `player_id`. A `:rift` exit with `visible_to_user_id = owner` is therefore listed and traversable **only** for the owner; everyone else sees/gets nothing.

---

## 5. Lifecycle & purge surface (NEW)

```elixir
# AgenticRealms.World.Transient.Manager (supervised singleton)
#   - presence: stamps regions.owner_offline_since on owner last-leave / clears on join
#   - sweep:    every transient_reap_interval_ms, reaps due regions (D5/D6)

# AgenticRealms.World.Transient.Purge
@spec run(region_id :: binary) :: :ok        # idempotent; safe to retry
#   1. capture room_ids + entity_ids from read model
#   2. hard-delete event streams (entity-*, room-*, region-*) + room snapshots
#   3. delete read-model rows LAST: world_objects, npc_clones,
#      player_discovered_rooms, world_exits, world_rooms, regions

# Injectable seam for tests (in-memory adapter has no delete_stream):
#   @event_store Application.compile_env(:agenticrealms, :transient_event_store, AgenticRealms.EventStore)
```

`due?(region, now)` (reaper predicate): `owner_offline_since && now - owner_offline_since >= grace_ms` **or** `now - provisioned_at >= lifetime_ms`.

---

## 6. Config keys (NEW / CHANGED)

```elixir
# config/config.exs (+ runtime.exs for prod) — ENABLE destructive purge:
config :agenticrealms, AgenticRealms.EventStore, enable_hard_deletes: true

# Tunables (defaults shown); keep grace + reap_interval <= 60_000 for SC-003/SC-004
config :agenticrealms, AgenticRealms.World.Transient,
  region_lifetime_ms: 3_600_000,   # 60-min absolute cap
  logoff_grace_ms:    120_000,     # ~2-min reconnect grace
  reap_interval_ms:   30_000
```

---

## 7. Behavioural guarantees (traceability to spec)

| Guarantee | Mechanism |
|---|---|
| FR-001 system-initiated provisioning | `Transient.provision/2` (dispatch, no UI) |
| FR-005 transient vs permanent | `regions.kind` |
| FR-007/FR-008 crash durability | rooms are ordinary `Room` aggregates (event store replay) — no special work |
| FR-009 navigation | reuses `world_exits` + `MovePlayer` |
| FR-011 no entry during teardown | row removed by purge → `resolve_exit` finds nothing |
| FR-012/FR-013 logoff + ~2-min grace | presence stamps `owner_offline_since`; reaper applies `grace_ms` |
| FR-014 60-min cap | reaper compares `provisioned_at + lifetime_ms` |
| FR-015 idempotent destroy | `destroyed?` guard + retry-safe purge |
| FR-016 full purge, no residue | §5 hard-deletes streams + snapshots + all read-model rows |
| FR-017/SC-006 isolation | purge targets only the region's ids; permanent data untouched |
| FR-018 orphan cleanup on recovery | reaper re-derives `due?` from durable state each tick |
| FR-019/FR-022/SC-007 relocation | owner relocated to `source_room_id` before purge; FR-022 nilify safety net |
| FR-020 clean provisioning failure | `provision/2` returns `{:error, _}`; partial dispatches reaped as a never-completed region |
| FR-021 one region per owner | read-model guard before provisioning |
