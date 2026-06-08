# Quickstart: Transient Regions

How to provision a transient region and verify the four behaviors (provision/explore, crash durability, logoff purge, 60-min cap) — there is no UI, so provisioning is dispatched from IEx (FR-001 "system-initiated").

## Prerequisites

```bash
mix setup            # deps, event store + read model, migrate, seed
# (after this feature's migrations exist)
iex -S mix phx.server
```

A logged-in player session is needed to act as the provision-owner. Note the owner's `player_id` and current room id (the **source room**) from the running session.

## 1. Provision and explore (User Story 1 / SC-001)

```elixir
owner_id = "<player_id>"
source_room_id = "<owner's current room id>"

{:ok, region_id} = AgenticRealms.World.Transient.provision(owner_id, source_room_id)
```

In the player's browser session the owner now sees a shimmering **rift** exit. Take it (`rift`) → the owner is in the transient region's origin room and can move among the few generated rooms. Verify:

```elixir
# region exists and is transient
AgenticRealms.Repo.get(AgenticRealms.World.Schemas.Region, region_id).kind   #=> "transient"
# its rooms exist and are off-map (map_visible: false, nil coords)
import Ecto.Query
AgenticRealms.Repo.all(from r in AgenticRealms.World.Schemas.Room, where: r.region_id == ^region_id) |> length()   #=> a few
```

**Owner-only exit check**: from a *different* player's session standing in the same source room, the rift exit is **not** listed, and attempting `rift` yields "You can't go that way." (FR: owner-only visibility + traversal).

**Re-provision guard (FR-021)**:
```elixir
AgenticRealms.World.Transient.provision(owner_id, source_room_id)   #=> {:error, :already_provisioned}
```

## 2. Crash durability (User Story 2 / SC-002)

```elixir
# note the region's room ids, then simulate a crash:
# Ctrl-C twice to kill the BEAM, then restart:
#   iex -S mix phx.server
```

After restart, the rooms are still present and navigable (rooms are ordinary event-sourced `Room` aggregates; the event store replays them). Confirm the read model still has the rooms and the rift exit:

```elixir
AgenticRealms.Repo.all(from e in AgenticRealms.World.Schemas.Exit, where: e.direction == "rift") |> length()   #=> 1
```

The 60-min cap is measured from the original `provisioned_at` (a persisted column) — a crash does not reset it.

## 3. Purge on logoff (User Story 3 / SC-003)

```elixir
# Lower the grace + reap interval for a quick demo (config/dev.exs):
#   config :agenticrealms, AgenticRealms.World.Transient,
#     logoff_grace_ms: 5_000, reap_interval_ms: 3_000
```

Log the owner fully out (close all their tabs). Within a few seconds the presence monitor stamps `owner_offline_since`; after the grace + next sweep the reaper destroys and purges the region. Verify **nothing remains**:

```elixir
AgenticRealms.Repo.get(AgenticRealms.World.Schemas.Region, region_id)   #=> nil
AgenticRealms.Repo.all(from r in AgenticRealms.World.Schemas.Room, where: r.region_id == ^region_id)   #=> []
# event streams are hard-deleted:
AgenticRealms.EventStore.stream_forward("region-" <> region_id)   #=> {:error, :stream_not_found} (or :stream_deleted)
```

If the owner *reconnects* within the grace window, `owner_offline_since` is cleared and the region survives (User Story 3 scenario 5).

While the owner is logged in elsewhere, an **empty** region (no one inside) is **not** purged (FR-010 / SC-005).

## 4. Purge on 60-min cap (User Story 4 / SC-004)

```elixir
# config/dev.exs: shrink the cap for a demo
#   config :agenticrealms, AgenticRealms.World.Transient, region_lifetime_ms: 10_000
```

Provision a region and keep the owner logged in. After ~`region_lifetime_ms` + one sweep, the reaper purges it regardless of activity — same verification as §3.

## Notes / gotchas

- **Enable hard deletes**: purge requires `config :agenticrealms, AgenticRealms.EventStore, enable_hard_deletes: true`. Without it, `delete_stream(..., :hard)` errors and streams are not removed.
- **Tests**: the `:test` env uses the in-memory Commanded adapter, which has **no `delete_stream`**. Use the `:transient_event_store` injectable seam to assert purge *targets* in unit tests; verify true hard-delete against the Postgres event store (tagged integration test) or via this quickstart.
- **Owner relocation**: when a region is purged while the owner is inside, they are moved back to `source_room_id` first; if they were offline, the FR-022 nilify guard re-spawns them at the starter room on next login. Either way, no one is stranded.
