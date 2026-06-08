# Phase 0 Research: Transient Regions

All decisions below are grounded in the current codebase (versions from `mix.lock`: commanded 1.4.10, commanded_eventstore_adapter 1.4.2, eventstore 1.4.8, horde 0.10.0). File:line citations point at the real extension points.

---

## D1 — How to actually purge a transient region's events (the open question)

**Decision**: Purge by **explicit, direct hard-deletes against `AgenticRealms.EventStore`**, plus snapshot deletes and read-model row deletes. Enable hard deletes in config first.

**The user's hypothesis — "maybe a final snapshot that goes away with the aggregate"?** — does not hold:

- `Commanded.Aggregates.AggregateLifespan` (`deps/commanded/.../aggregate_lifespan.ex`) controls **only the aggregate GenServer process lifespan** (return `:stop`/`:hibernate`/timeout). It never touches persisted events or snapshots. Stopping the process leaves every event on disk.
- Snapshots are **independent rows** keyed by the prefixed stream UUID; they persist until explicitly deleted (`EventStore.delete_snapshot/2`). They do not "go away with" a stopped aggregate.

**The mechanism that does work** (eventstore 1.4.8):

```elixir
# hard delete — irreversible; removes events from the stream AND the global $all stream
AgenticRealms.EventStore.delete_stream("region-" <> region_id, :any_version, :hard)
AgenticRealms.EventStore.delete_snapshot("region-" <> region_id)   # if ever snapshotted
```

- Stream UUID is `"<prefix><id>"` (Commanded router doc, `deps/commanded/.../commands/router.ex:100-101`). So `region-<id>`, `room-<id>`, `entity-<id>`.
- **`enable_hard_deletes` is OFF today** (not in `lib/agenticrealms/event_store.ex` nor any config). Hard delete will error until we add `enable_hard_deletes: true` to the `AgenticRealms.EventStore` config. (Soft delete is default and removes nothing from disk → fails the spec.)
- **Commanded's adapter has no `delete_stream`** (`deps/commanded/.../event_store/adapter.ex` declares `delete_snapshot`/`delete_subscription` only). We therefore call the `AgenticRealms.EventStore` (eventstore lib) module **directly**, bypassing Commanded, for stream deletion.

**Full purge of a region = three independent operations:**

1. **Event streams (hard delete):** `region-<id>`, every transient `room-<roomid>`, and every contained `entity-<entityid>` (objects/NPCs cloned into those rooms).
2. **Snapshots:** transient rooms are snapshotted (config snapshots `Room` every 100) → `delete_snapshot("room-<roomid>")`. `Region`/`Entity` are not snapshotted, so those calls are no-ops (safe).
3. **Read-model rows:** delete by region/room ids across `world_objects`, `npc_clones`, `world_exits` (including the owner-only entry exit attached to the permanent source room), `player_discovered_rooms`, `world_rooms`, then `regions`. No DB cascade exists for the denormalized containment columns, so deletion is explicit & ordered.

**Rationale**: It is the only mechanism in this stack that removes both current and historical data. **Alternatives rejected**: soft delete (leaves events on disk and in `$all`); "drop read model only" (event history survives → violates SC-003/SC-006); deleting the whole event-store DB (nukes permanent world too).

**Testing caveat**: the in-memory Commanded adapter used in `:test` has no `delete_stream` (`deps/commanded/.../in_memory.ex`). Plan an **injectable purge seam** (a `@purge_event_store` module/behaviour) so unit tests assert *which* streams/rows are targeted, and a separate Postgres-event-store-backed (tagged) test or the quickstart for true end-to-end hard-delete verification.

---

## D2 — Aggregate lifespan for tearing down the transient Region process

**Decision**: Attach an `AggregateLifespan` module to the `Region` (and transient `Room`) dispatches. Return `:stop` on `RegionDestroyed`, and a **finite idle timeout** otherwise so unused transient aggregates evict themselves cheaply. This is the "easy eviction" half of the two-phase model; the timed reaper (D5) + purge (D1) handle the *data*.

- Lifespan is **not used anywhere today** — this is the first use. Wire it via the router `dispatch ... lifespan: AgenticRealms.World.RegionLifespan` (and a `TransientRoomLifespan`/idle timeout for transient rooms).
- Lifespan is **orthogonal** to purge: it frees the process (in-memory) cheaply and immediately; D1 frees the persisted data. Both are needed — evicting the aggregate does **not** remove any events or snapshots.

**Rationale**: Directly matches the design feedback — *"evicting the aggregate from memory is easy"*. Lifespan handles the process; the reaper handles the disk. **Alternative rejected**: leaving aggregates resident forever (resource leak; the spec is explicitly about reclaiming resources).

---

## D3 — Owner-only entry exit: read-model-only, projected from the Region stream

**Decision**: Model the entry exit (permanent **source room → transient origin room**, visible/traversable only by the provision-owner) as a **read-model-only** exit, projected from a `TransientEntryExitOpened` event on the **Region** stream. Do **not** emit `Room.AddExit` on the permanent source room.

Why this works and is safe:

- Movement and exit-listing both resolve via the **`world_exits` read model**, not the Room aggregate's in-memory `exits` map: `Queries.list_exits/1` (`queries.ex:311`) and `Commands.resolve_exit/2` (`commands.ex:300`). So an exit that exists only as a read-model row is fully functional.
- Putting the exit on the permanent source room's aggregate stream would leave an `ExitAdded` (and a compensating `ExitRemoved`) permanently in that stream — un-purgeable without destroying the permanent room. Sourcing it from the **Region** stream means hard-deleting `region-<id>` (D1) erases its history, and the `RegionDestroyed` projector deletes the row.

**Read-model change**: add nullable `visible_to_user_id` to `world_exits`. The existing `unique_index(world_exits, [source_room_id, direction])` is replaced by two **partial** unique indexes — `WHERE visible_to_user_id IS NULL` (global exits) and on `(source_room_id, direction, visible_to_user_id)` (owned exits) — so an owned exit can coexist.

**Enforcement points** (both already have the viewer's `player_id` one frame up):
- **List/visibility** — `Queries.list_exits/1` → take `player_id`, add `where: is_nil(e.visible_to_user_id) or e.visible_to_user_id == ^player_id`. (Same pattern feature 013 used for quest-scoped objects, `queries.ex:48`.)
- **Traversal** — `Commands.resolve_exit/2` → take `player_id`, add the same predicate; a non-owner falls through to `:no_exit_in_direction` → existing "You can't go that way." message (`player_commands.ex:237`).

**Rationale**: satisfies the purge guarantee and the owner-only requirement with the smallest, most consistent change. **Alternatives rejected**: per-exit owner field on the Room aggregate (un-purgeable history on a permanent stream, D-tracked); a separate "doors" table (more surface area; `world_exits` already drives movement).

---

## D4 — A dedicated `:rift` portal direction for the entry exit

**Decision**: Add a non-geographic `:rift` direction used only by transient entry exits.

- `world_exits` has a CHECK constraint pinning `direction` to the six canonical compass strings (`create_world_read_models` migration) and a unique `(source_room_id, direction)` index. A dedicated `:rift` direction (added to the CHECK + `Direction` module) sidesteps both the collision and the geometry validator (`exits/validator.ex` must skip `:rift`, as it already skips off-map/cross-region exits).
- UX: renders as a distinct "shimmering rift" chip (`log_entry.ex`), making the owner-only door visually obvious.

**Rationale**: deterministic and self-documenting; no runtime "find a free compass direction" logic. **Alternative rejected**: reuse a free compass direction — requires probing the source room's exits at provision time and risks ambiguous `(source, direction)` resolution between a global and an owned exit. (Schema from D3 still supports coexistence if we ever want it.)

---

## D5 — Lifecycle orchestration: presence-stamp + a timed reaper job (no per-region timers)

**Decision** (refined per design feedback — *"evicting the aggregate from memory is easy, then use a timed job to purge data from no-longer-used transient regions"*): split the lifecycle into **cheap eviction** (aggregate lifespan, D2) and a **periodic reaper job** that purges data. Drop per-region `Process.send_after` cap/grace timers entirely; derive "due for destruction" from durable read-model state on every sweep.

One cluster-singleton `AgenticRealms.World.Transient.Manager` GenServer (registered by name, supervised under the app supervisor after the `Ticks` block, mirroring `Ticks.Lifecycle`) with two duties:

1. **Presence stamping (event-driven).** Subscribe to the `"connected_players"` presence topic. On the owner's **last-session** `leaves`, stamp `regions.owner_offline_since = <now>` for that owner's transient region; on the owner's `joins`, clear it back to `nil`. This implements the ~2-minute grace *implicitly* — a reconnect clears the stamp, so the reaper never sees the region as due. (`AgenticRealmsWeb.Presence` keys by `player_id` and emits `joins` only on the first tab / `leaves` only on the last, so a `leaves` for the owner key === full logoff — no per-session counting; FR-012/FR-013.)

2. **Timed reaper sweep (periodic, every ~20–30 s via `Process.send_after(self(), :sweep, interval)`).** Each tick, query transient regions and compute `due?` purely from durable fields:
   - `owner_offline_since` is set **and** `now − owner_offline_since ≥ grace_ms` (logoff path), **or**
   - `now − provisioned_at ≥ lifetime_ms` (60-min absolute cap, FR-014).
   For each due region, run destruction + purge (D6).

**Why this is better than per-region timers**: no in-memory timer state to lose, so **crash recovery is automatic** — after a restart the reaper re-evaluates durable state on its next tick and reaps any region whose owner logged off during downtime or whose cap elapsed (**FR-018** with zero special-casing). The sweep is idempotent and self-retrying: a purge that partially fails leaves the `regions` row intact (rows are deleted last, D1), so the next tick simply retries.

**SLA**: offline-to-purge latency = `grace_ms + (≤ one sweep interval)`. A sweep interval ≤ 30 s keeps SC-003/SC-004 (purge "within 1 minute") satisfied.

**Rationale**: matches the two-phase mental model (easy evict, deferred reap), reuses the `Ticks.Lifecycle` singleton precedent, and is strictly simpler than cancellable per-region timers. **Alternative rejected**: per-region `Process.send_after` cap + grace timers with reconnect cancellation — more code, in-memory state that must be rehydrated on every restart, and no resilience to a missed timer. **Alternative deferred**: per-region Horde-supervised processes — unnecessary for an MVP single sweep.

**Durability note**: `provisioned_at` and `owner_offline_since` are persisted `regions` columns; the reaper reads them fresh each tick. Nothing about the timing lives only in memory.

---

## D6 — Destruction & occupant relocation order (reaper-driven, crash-safe)

**Decision**: When the reaper (D5) finds a due region, it runs this order — chosen so a crash at any step leaves the `regions` row intact for an idempotent retry:

1. **Capture** the region's room ids + contained entity ids from the read model (into memory).
2. **Relocate** the owner if still in-region and online (D-below); if the owner is offline, skip — the FR-022 nilify safety net covers them.
3. **Evict** the aggregate: dispatch `DestroyRegion` → `RegionDestroyed` → `RegionLifespan` returns `:stop` (cheap, immediate process eviction; transient `Room` aggregates also carry a short idle-timeout lifespan so they self-evict).
4. **Purge** (`Transient.Purge`, D1): hard-delete `entity-*` then `room-*` then `region-*` streams + room snapshots, **then** delete read-model rows last (`world_objects` → `npc_clones` → `player_discovered_rooms` → `world_exits` → `world_rooms` → `regions`).

Because the `regions` row is deleted **last**, a crash between any earlier step and the final row delete is fully recoverable: the region is still `due?` on the next sweep, and re-deleting already-deleted streams/rows is a no-op (`delete_stream` returns `{:error, :stream_not_found}`/`{:error, :stream_deleted}` → treated as `:ok`). Relocation precedes purge so no player is stranded in a deleted room (FR-019, SC-007).

- **Occupancy collapses to the owner** in the MVP: the entry exit is owner-only, so no one else can be inside. Pre-entry location is therefore a single durable value = the **source room** recorded at provision time (`regions.source_room_id`), not a multi-occupant table.
- Relocate via `MovePlayer{player_id: owner, from_room_id: <current>, to_room_id: source_room_id, direction: :rift}` with `consistency: :strong`. Read `Queries.current_room_of/1` immediately before to set `from_room_id` (the `:stale_from_room` guard, `player.ex:45`); skip relocation if the owner is offline / already outside.
- **Safety net**: even if relocation is missed, the projector's FR-022 nilify guard (`player_state_projector.ex:56`) sets `current_room_id = nil` when the destination room is gone, re-spawning the player into the starter room on next visit — so a player can never be permanently stuck.

**Rationale**: deterministic, single-occupant relocation with an existing fallback. **Alternative rejected**: a general multi-occupant `transient_occupants` table — unnecessary while the entry exit is owner-only; deferred to whenever shared/group regions arrive.

---

## D7 — Provisioning orchestration (command-dispatched, no UI)

**Decision**: `Transient.provision(owner_id, source_room_id)` orchestrates, in order:
1. `Generator.generate/2` → a **deterministic** spec (region_id, name, room specs, origin_room_id, intra-region + return exits). Determinism without `Math.random`/`Date.now` (forbidden) comes from seeding off `owner_id`/`source_room_id`/ids — hand-coded layout for the MVP (no map data, no procedural generation).
2. Reject if the owner already has an active transient region (FR-021) — checked against the `regions` read model.
3. Dispatch `ProvisionTransientRegion` → `regions` row (`kind: :transient`, `provision_owner_id`, `provisioned_at`, `source_room_id`, `origin_room_id`).
4. Dispatch `CreateRoom` for each generated room (`region_id`, `map_visible: false`, no coords — all valid per `commands.ex:514`).
5. Dispatch `AddExit` for intra-region exits and the origin→source **return** exit (normal `Room` events on transient streams — purged with them).
6. Dispatch `TransientEntryExitOpened` (Region stream) → owner-only `world_exits` row (`:rift`, `visible_to_user_id: owner`). Must come **after** the origin room exists (FK `world_exits.target_room_id → world_rooms`, on_delete `:restrict`).
7. Place the owner: `MovePlayer{owner, from_room_id: source_room_id, to_room_id: origin_room_id, direction: :rift}`.
8. No timer to arm — `provisioned_at` is now a durable `regions` column, so the reaper (D5) picks the region up on its next sweep and enforces the cap purely from that timestamp.

**Rationale**: reuses existing seed/command patterns (`seed.ex`) verbatim; provisioning is just orchestrated dispatches, exercisable from IEx or tests (FR-001 "system-initiated, no player command"). **Alternative considered**: a single fat aggregate command that creates rooms too — rejected; rooms are separate aggregates and must be their own `CreateRoom` dispatches.

---

## D8 — Durability across crashes (no new work)

**Decision**: Rely on the existing guarantee. Transient rooms are ordinary `Room` aggregates whose events live in the Postgres event store and project to `world_rooms`; Commanded replays/snapshots them on restart. **Nothing special is required for FR-007/FR-008** beyond marking the region transient and rehydrating the Manager's timers (D5). The crash-before-purge case (FR-018) is handled by the Manager's init-time destroy of regions whose conditions are already met.

**Rationale**: durability is the platform default; the feature only needs to ensure the *lifecycle* survives restarts, which D5's read-model rehydrate provides.

---

## Resolved unknowns summary

| Unknown (from Technical Context) | Resolution |
|---|---|
| How to purge events for a destroyed region | D1 — direct hard `delete_stream` + `delete_snapshot` + read-model deletes; enable `enable_hard_deletes` |
| Whether aggregate lifespan deletes data | D2 — no; it only stops the process. Use it for teardown, purge separately |
| Owner-only exit data shape | D3/D4 — read-model-only exit from Region stream, `visible_to_user_id` column, `:rift` direction |
| How to detect full logoff | D5 — Phoenix.Presence `leaves` on the owner key = last session gone |
| Per-region 60-min timer + crash recovery | D5 — **no per-region timers**; presence stamps `owner_offline_since`, a periodic reaper computes `due?` from durable `provisioned_at`/`owner_offline_since` each tick (auto crash recovery) |
| Pre-entry location capture | D6 — single durable `source_room_id` (owner-only occupancy) |
| Manual room creation without map data | D7 — `CreateRoom` with `map_visible: false`, nil coords (already supported) |
