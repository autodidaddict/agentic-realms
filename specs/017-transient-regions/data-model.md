# Phase 1 Data Model: Transient Regions

Covers aggregate state, commands, events, read-model schema/migrations, and the lifecycle-manager runtime state. New fields/modules are marked **NEW**; edits to existing structures are marked **EDIT**.

---

## 1. `Region` aggregate (`lib/agenticrealms/world/region.ex`) — EDIT

Current struct: `id, name`. New fields make a region self-describing as transient and carry everything the projector + relocation need.

| Field | Type | Notes |
|---|---|---|
| `id` | binary id | existing |
| `name` | string | existing |
| `kind` | `:permanent` \| `:transient` | **NEW** — default `:permanent`; permanent regions unaffected |
| `provision_owner_id` | binary id (player) \| nil | **NEW** — set for transient only |
| `provisioned_at` | UTC datetime | **NEW** — absolute lifetime anchor (set by dispatcher, carried on command) |
| `source_room_id` | binary id (permanent room) \| nil | **NEW** — owner's pre-entry/return room |
| `origin_room_id` | binary id (transient room) \| nil | **NEW** — entry target inside the region |
| `destroyed?` | boolean | **NEW** — guards double-destroy (idempotency, FR-015) |

> `owner_offline_since` and `destroyed_at` live on the **read model** (`regions` table, §4a), not the aggregate — they are operational lifecycle fields written by the presence monitor / reaper, not domain decisions made inside the aggregate.

**State transitions**:

```
(absent) --ProvisionTransientRegion--> provisioned(kind: :transient, destroyed?: false)
provisioned --TransientEntryExitOpened--> provisioned (entry exit recorded; no state change beyond bookkeeping)
provisioned --DestroyRegion--> destroyed(destroyed?: true)   # lifespan :stop fires here
destroyed   --DestroyRegion--> (no-op, idempotent)
```

Permanent regions keep the existing `CreateRegion → RegionCreated` path untouched (`kind: :permanent`).

---

## 2. Commands (`lib/agenticrealms/world/commands/`) — all NEW → `Region`

| Command | Fields | Guard |
|---|---|---|
| `ProvisionTransientRegion` | `region_id, name, provision_owner_id, provisioned_at, source_room_id, origin_room_id` | error `:region_already_exists` if region id seen |
| `TransientEntryExitOpened` *(command)* `OpenTransientEntryExit` | `region_id, source_room_id, direction (:rift), origin_room_id, provision_owner_id` | error if region absent / not transient |
| `DestroyRegion` | `region_id` | no-op if `destroyed?` already true |

Router (`router.ex`) **EDIT**: add `dispatch [ProvisionTransientRegion, OpenTransientEntryExit, DestroyRegion], to: Region, identity: :region_id` and attach `lifespan: AgenticRealms.World.RegionLifespan`.

`RegionLifespan` **NEW** (`AggregateLifespan` behaviour): `after_event(%RegionDestroyed{}) -> :stop`; `after_event(_) -> :infinity` (or a finite idle timeout); `after_command/1 -> :infinity`; `after_error/1 -> :stop`.

---

## 3. Events (`lib/agenticrealms/world/events/`) — all NEW

| Event | Fields | Projector effect |
|---|---|---|
| `TransientRegionProvisioned` | `region_id, name, provision_owner_id, provisioned_at, source_room_id, origin_room_id, version: 1` | insert `regions` row with transient fields |
| `TransientEntryExitOpened` | `region_id, source_room_id, direction, target_room_id (origin), visible_to_user_id, version: 1` | insert owner-only `world_exits` row |
| `RegionDestroyed` | `region_id, version: 1` | delete all read-model rows for the region (see §5 purge order); triggers lifespan `:stop` |

(Transient rooms and their intra-region/return exits reuse existing `RoomCreated`/`ExitAdded` events on `room-` streams — no new event types.)

---

## 4. Read-model schemas & migrations

### 4a. `regions` table (`schemas/region.ex` + migration) — EDIT

Add columns: `kind :string` (default `"permanent"`, not null), `provision_owner_id :binary_id` (null), `provisioned_at :utc_datetime_usec` (null), `source_room_id :binary_id` (null), `origin_room_id :binary_id` (null), **`owner_offline_since :utc_datetime_usec` (null)** — stamped by the presence monitor when the owner's last session leaves, cleared on rejoin; drives the reaper's logoff-grace evaluation — and **`destroyed_at :utc_datetime_usec` (null)** — optional tombstone for observability/idempotency. Index `(kind, provision_owner_id)` to enforce/look up "one active transient region per owner" (FR-021) and to drive the reaper sweep + crash-recovery rehydrate.

### 4b. `world_exits` table (`schemas/exit.ex` + migration) — EDIT

Add column: `visible_to_user_id :binary_id` (null = visible to everyone).

Replace the existing `unique_index(:world_exits, [:source_room_id, :direction])` with **two partial unique indexes**:
- `unique_index(:world_exits, [:source_room_id, :direction], where: "visible_to_user_id IS NULL", name: :world_exits_global_uidx)`
- `unique_index(:world_exits, [:source_room_id, :direction, :visible_to_user_id], where: "visible_to_user_id IS NOT NULL", name: :world_exits_owned_uidx)`

Extend the `direction` CHECK constraint to include `'rift'` alongside the six compass strings.

### 4c. Tables touched by purge (no schema change, deletion targets)

`world_objects` (container_id = room id), `npc_clones` (room_id), `world_exits` (source/target room id — incl. the owner-only entry exit), `player_discovered_rooms` (room id), `world_rooms` (region_id), `regions` (id). No DB cascade is wired for the denormalized containment columns → purge deletes them explicitly in dependency order.

---

## 5. Purge target set & order (`Transient.Purge`) — NEW

Given `region_id`, resolve room ids from `world_rooms WHERE region_id = ?`, then:

**Event store (hard delete, requires `enable_hard_deletes: true`):**
1. each `entity-<id>` for entities contained in those rooms
2. each `room-<roomid>`
3. `region-<id>`

**Snapshots:** `delete_snapshot("room-<roomid>")` per transient room (Region/Entity not snapshotted → no-op).

**Read-model rows (ordered):** `world_objects` → `npc_clones` → `player_discovered_rooms` → `world_exits` (by source OR target room id) → `world_rooms` (region) → `regions` (id).

> `Transient.Purge` owns **all** deletion (so it can guarantee the crash-safe order), not the projector. `DestroyRegion`/`RegionDestroyed` is responsible only for **evicting the aggregate** (lifespan `:stop`) and optionally stamping `destroyed_at`. Sequence per reaped region (D6): capture room/entity ids → relocate owner → `DestroyRegion` (evict) → `Purge` hard-deletes streams + snapshots → `Purge` deletes read-model rows **last**. Deleting `regions` last makes the whole operation an idempotent, retry-safe sweep target.

---

## 6. `Transient.Manager` runtime state (`transient/manager.ex`) — NEW

A single supervised singleton GenServer with **no per-region timer state** (that's the point of the timed-job model). It does two things — presence stamping and a periodic reap sweep — driven entirely off durable `regions` columns:

```elixir
%{sweep_interval_ms: 30_000, sweep_timer: reference()}   # that's all the in-memory state
```

- **Presence (event-driven):** subscribes to `"connected_players"`; on the owner's last-session `leaves` → `UPDATE regions SET owner_offline_since = now WHERE provision_owner_id = ? AND kind='transient'`; on `joins` → set it back to `NULL`.
- **Reap sweep (every `sweep_interval_ms`, via `Process.send_after(self(), :sweep, ...)`):** select transient regions and reap those where `owner_offline_since + grace_ms < now` OR `provisioned_at + lifetime_ms < now` (D6 order).

Config keys (`config/config.exs`, overridable): `transient_region_lifetime_ms` (default `3_600_000`), `transient_logoff_grace_ms` (default `120_000`), `transient_reap_interval_ms` (default `30_000` — must keep `grace + interval ≤ 60 s` for SC-003/SC-004).

**Crash recovery is free**: there is nothing to rehydrate — the next sweep after restart re-evaluates durable state and reaps anything already due (FR-018).

---

## 7. `:rift` direction (`direction.ex` + `exits/validator.ex`) — EDIT

Add `:rift` as a non-geographic direction: parses/stringifies to `"rift"`, has **no** `(dx, dy)` delta, and `ExitsValidator` skips geometry consistency for it (as it already does for off-map/cross-region exits). Intent parser + exit-chip rendering recognize `rift` so the owner can traverse and see it.

---

## Validation rules (from spec FRs)

- FR-021: provisioning rejected if a non-destroyed transient region already exists for `provision_owner_id` (read-model check before dispatch).
- FR-013/FR-012: owner "logged off" only when Presence reports `leaves` for the owner key (last session); grace ≈ 2 min before destroy.
- FR-011: a destroying region (`destroyed?: true` / row gone) rejects new entry — `resolve_exit` finds no `world_exits` row.
- FR-016/SC-006: purge deletes only rows/streams scoped to the region; permanent regions, rooms, and history are never targeted.
- FR-008/FR-018: Manager init recomputes remaining lifetime from `provisioned_at`; destroys regions whose conditions are already met.
