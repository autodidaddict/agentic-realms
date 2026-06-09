# Implementation Plan: Transient Regions

**Branch**: `017-transient-regions` | **Date**: 2026-06-08 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/017-transient-regions/spec.md`

## Summary

Provision a private, on-demand **transient region** (a `Region` aggregate flagged `kind: :transient`) for a single *provision-owner*. A simulated generator hand-codes a few interconnected, durable rooms (normal event-sourced `Room` aggregates), and an **owner-only entry exit** links a permanent source room to the region's origin room. The region's rooms survive process crashes exactly like permanent rooms (Commanded + EventStore replay). The region is destroyed — and **all of its data hard-purged from the event store and read models** — when the provision-owner fully logs off (after a ~2-minute reconnect grace) or 60 minutes after provisioning, whichever comes first.

Three facts from Phase 0 research shape the whole approach:

1. **Aggregate lifespan ≠ purge.** `Commanded.Aggregates.AggregateLifespan` only stops the aggregate GenServer; it never deletes persisted events or snapshots. Purging requires explicit, destructive calls.
2. **Purge bypasses Commanded.** The Commanded event-store adapter exposes no `delete_stream`. We must call `AgenticRealms.EventStore.delete_stream("region-<id>", :any_version, :hard)` (and per transient `room-`/`entity-` stream) directly, after enabling `enable_hard_deletes: true` (currently off). Snapshots and read-model rows are deleted separately.
3. **Owner-only exit collapses occupancy.** Because the entry exit is visible/traversable only to the provision-owner, the owner is the *only* possible occupant in the MVP. Pre-entry-location capture (FR-022) therefore reduces to a single durable field recorded at provision time — no multi-occupant tracking needed yet.

## Technical Context

**Language/Version**: Elixir ~1.20 (OTP), Phoenix 1.8 / LiveView 1.1
**Primary Dependencies**: Commanded 1.4.10, commanded_eventstore_adapter 1.4.2, eventstore 1.4.8 (PostgreSQL), Horde 0.10, Ecto/Postgrex, Phoenix.Presence
**Storage**: Two PostgreSQL databases — event store (`AgenticRealms.EventStore`, db `agenticrealms_eventstore*`) and read-model (`AgenticRealms.Repo`, db `agenticrealms*`)
**Testing**: ExUnit; `AgenticRealms.DataCase` (Ecto SQL Sandbox + per-test Commanded chain via `@moduletag :commanded`). Note: the test config uses the **in-memory** Commanded adapter, which has **no `delete_stream`** — the hard-purge execution path needs a Postgres-backed/tagged test or an injectable seam (see research).
**Target Platform**: Linux server (single-node MVP; Horde present for future multi-node)
**Project Type**: Web application (Phoenix LiveView front end + event-sourced domain backend)
**Performance Goals**: Provision→owner-in-region < 5 s (SC-001); purge within 1 min of full logoff (SC-003); destroy within 1 min of the 60-min cap (SC-004)
**Constraints**: Crash durability equal to permanent rooms; complete purge of current + historical data; owner-only entry exit; exactly one active transient region per owner (MVP); 60-min absolute lifetime from provisioning; ~2-min logoff grace
**Scale/Scope**: MVP — a few rooms per region, low concurrent region count; provisioning is dispatched programmatically (no UI)

**Unknowns resolved in Phase 0**: event purge mechanism (hard delete + enable flag), aggregate-lifespan semantics, owner-only-exit data shape, logoff signal source, timer/crash-recovery precedent. No `NEEDS CLARIFICATION` remain.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The project constitution (`.specify/memory/constitution.md`) is an **unpopulated template** — no ratified principles or gates exist. In their absence I apply the engineering norms evident in the codebase and prior specs:

| Principle (inferred) | Assessment |
|---|---|
| **Consistency with existing event-sourced patterns** | PASS — reuses `Region`/`Room`/`Player` aggregates, Commanded router, `Commanded.Event.Handler` projectors, `world_exits` read-model query path, and the feature-011 presence + grace-timer precedent. No new architectural style. |
| **No unnecessary new dependencies** | PASS — adds zero deps; reuses Commanded, EventStore, Horde, Phoenix.Presence already in `mix.exs`. |
| **Simplicity / YAGNI** | PASS (with noted scope reductions) — owner-only exit reduces occupancy to one player; a single cluster-singleton manager (mirroring `Ticks.Lifecycle`) instead of per-region Horde processes; read-model-only entry exit avoids touching the permanent source room's stream. |
| **Test-first / observability** | PASS — pure aggregate/generator/purge-target unit tests precede integration; purge and lifecycle emit log + witness entries. |

**One capability worth flagging** (tracked in Complexity Tracking): enabling `enable_hard_deletes: true` introduces an irreversible, destructive event-store operation. Justified by the spec's hard requirement to purge current **and historical** data, and by the project's current "event log is destroyable" phase.

**Post-Design re-check**: PASS — design stays within existing patterns; the only cross-cutting addition is the new `Transient` context + one supervised singleton; see Complexity Tracking for the hard-delete justification.

## Project Structure

### Documentation (this feature)

```text
specs/017-transient-regions/
├── plan.md              # This file
├── research.md          # Phase 0 — decisions & rationale (incl. purge mechanism)
├── data-model.md        # Phase 1 — aggregate/event/read-model/state changes
├── quickstart.md        # Phase 1 — provision & verify (durability + purge) via IEx
├── contracts/
│   └── transient-regions.md   # Commands, events, context API, query/config changes
├── checklists/
│   └── requirements.md  # Spec quality checklist (from /speckit.specify)
└── tasks.md             # Phase 2 — created by /speckit.tasks (NOT here)
```

### Source Code (repository root)

New `Transient` context plus targeted edits to Region, exits, movement queries, presence/lifecycle, config, and migrations.

```text
lib/agenticrealms/world/
├── transient/
│   ├── transient.ex                 # NEW context API: provision/2, destroy/1
│   ├── generator.ex                 # NEW simulated generator (hand-coded room layout)
│   ├── manager.ex                   # NEW cluster-singleton GenServer: presence-stamps owner_offline_since + periodic reap sweep (no per-region timers)
│   └── purge.ex                     # NEW hard-delete streams/snapshots + read-model row cleanup (rows last, idempotent)
├── commands/
│   ├── provision_transient_region.ex  # NEW → Region
│   ├── open_transient_entry_exit.ex   # NEW → Region (read-model-only owner exit)
│   └── destroy_region.ex              # NEW → Region
├── events/
│   ├── transient_region_provisioned.ex  # NEW
│   ├── transient_entry_exit_opened.ex   # NEW
│   └── region_destroyed.ex              # NEW
├── region.ex                        # EDIT struct (+kind, provision_owner_id, provisioned_at, source_room_id, origin_room_id), +execute/apply for provision/open-exit/destroy, +lifespan :stop on RegionDestroyed
├── router.ex                        # EDIT route new commands → Region; attach lifespan module
├── direction.ex                     # EDIT add :rift portal direction (non-geographic)
├── exits/validator.ex               # EDIT skip geometry for :rift
├── queries.ex                       # EDIT list_exits/2 viewer-aware (filter visible_to_user_id)
├── commands.ex                      # EDIT resolve_exit/3 viewer-aware (owner-only traversal)
├── projections/world_projector.ex   # EDIT +handlers: TransientRegionProvisioned, TransientEntryExitOpened, RegionDestroyed
└── schemas/
    ├── region.ex                    # EDIT +kind, +provision_owner_id, +provisioned_at, +source_room_id, +origin_room_id
    └── exit.ex                      # EDIT +visible_to_user_id

lib/agenticrealms_web/
├── live/game_live.ex                # EDIT thread viewer player_id into exit listing (already available at look_room)
├── live/game_live/*                 # EDIT intent parsing for `rift`/portal move + destruction notice
└── components/game/log_entry.ex     # EDIT render owner-only rift exit chip distinctly

lib/agenticrealms/application.ex     # EDIT add Transient.Manager to supervision tree (after Ticks block)
config/config.exs, config/runtime.exs # EDIT enable_hard_deletes on EventStore; transient lifetime/grace config keys
priv/repo/migrations/                # NEW migrations: alter regions (+cols), alter world_exits (+visible_to_user_id, partial unique index), extend direction CHECK (+rift)

test/agenticrealms/world/transient/  # NEW unit + integration tests (generator, aggregate, purge-target, manager, end-to-end)
```

**Structure Decision**: Single Phoenix app; new domain logic lives in a cohesive `AgenticRealms.World.Transient` context alongside the existing `World` aggregates, following the established command/event/projector/read-model layering. Lifecycle is two-phase (per design feedback): **cheap aggregate eviction** via `AggregateLifespan` `:stop`/idle-timeout, and a **timed reaper job** (a supervised singleton mirroring the feature-011 `Ticks.Lifecycle`) that stamps `owner_offline_since` from presence and periodically purges regions that are due — deriving "due" from durable read-model state, so crash recovery needs no rehydration.

## Complexity Tracking

| Violation / Deviation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| Enable `enable_hard_deletes: true` (irreversible event-store deletes) | Spec requires purging **current and historical** region data; soft delete leaves events in `$all` and on disk | Soft delete / "leave events, drop read model" fails the explicit "no residual historical data" requirement (SC-003, SC-006) |
| Read-model-only entry exit (projected from Region stream, not a `Room.AddExit` on the permanent source room) | The owner-only door's history must vanish on purge; recording it on the permanent source room's stream would leave un-deletable history (can't hard-delete a single event without destroying the permanent room) | An `AddExit`+compensating `ExitRemoved` on the permanent room leaves the add/remove pair permanently in that room's stream — violates the purge guarantee |
| New `:rift` portal direction (non-geographic) | Avoids the `world_exits (source_room_id, direction)` unique-index collision and the geometry validator for a cross-boundary owner-only door; self-documenting in UI | Reusing a free compass direction requires runtime "find a free direction" logic on the source room and risks ambiguous `(source, direction)` resolution between a global and an owned exit |
