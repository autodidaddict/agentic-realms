---
description: "Task list for Transient Regions implementation"
---

# Tasks: Transient Regions

**Input**: Design documents from `specs/017-transient-regions/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/transient-regions.md, quickstart.md

**Tests**: INCLUDED. This codebase tests every aggregate (`execute`/`apply`), projector, and integration path (`@moduletag :commanded`), and the plan's Constitution Check mandates test-first. Test tasks precede the implementation they cover within each story.

**Organization**: Tasks are grouped by user story. US1 is the MVP. US2 validates US1's durability. US3 adds the destroy/purge/reaper lifecycle (builds on US1). US4 extends US3 with the 60-minute cap.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1–US4 (user-story phases only)
- All paths are repo-relative; module paths follow `lib/agenticrealms/world/...`

## Path / domain notes

- Event-sourced via Commanded; aggregates emit events, `WorldProjector` builds read models. Movement resolves through the `world_exits` read model (`Queries.list_exits`, `Commands.resolve_exit`), **not** the Room aggregate's in-memory map.
- Two Postgres DBs: read-model `AgenticRealms.Repo`, event store `AgenticRealms.EventStore`. Purge hard-deletes streams directly (Commanded exposes no `delete_stream`) and requires `enable_hard_deletes: true`.
- `:test` env uses the **in-memory** Commanded adapter (no `delete_stream`) → Purge unit tests use the injectable `:transient_event_store` seam; true hard-delete is verified against Postgres (polish phase) or via quickstart.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Cross-cutting config + primitives every story builds on.

- [x] T001 [P] Add `AgenticRealms.World.Transient` config (`region_lifetime_ms: 3_600_000`, `logoff_grace_ms: 120_000`, `reap_interval_ms: 30_000`) and `config :agenticrealms, AgenticRealms.EventStore, enable_hard_deletes: true` in `config/config.exs` and `config/runtime.exs`; add fast demo overrides comment in `config/dev.exs`
- [x] T002 [P] Add non-geographic `:rift` direction (parse/`to_string`, no `(dx,dy)` delta) in `lib/agenticrealms/world/direction.ex`
- [x] T003 Skip geometry-consistency check for `:rift` exits in `lib/agenticrealms/world/exits/validator.ex` (depends on T002)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Schema + aggregate/read-model plumbing required before ANY story can run.

**⚠️ CRITICAL**: No user-story work begins until this phase is complete.

- [x] T004 [P] Migration `add_transient_region_fields` in `priv/repo/migrations/`: add `kind` (string, default "permanent", not null), `provision_owner_id`, `provisioned_at` (utc_datetime_usec), `source_room_id`, `origin_room_id`, `owner_offline_since` (utc_datetime_usec), `destroyed_at` (utc_datetime_usec) to `regions`; add index `(kind, provision_owner_id)`
- [x] T005 [P] Migration `add_exit_visibility_and_rift` in `priv/repo/migrations/`: add `visible_to_user_id` (binary_id, null) to `world_exits`; drop the `(source_room_id, direction)` unique index; add partial unique `world_exits_global_uidx` on `(source_room_id, direction) WHERE visible_to_user_id IS NULL` and `world_exits_owned_uidx` on `(source_room_id, direction, visible_to_user_id) WHERE visible_to_user_id IS NOT NULL`; extend the `direction` CHECK to include `'rift'`
- [x] T006 [P] Add new fields to the Region Ecto schema in `lib/agenticrealms/world/schemas/region.ex`
- [x] T007 [P] Add `visible_to_user_id` to the Exit Ecto schema in `lib/agenticrealms/world/schemas/exit.ex`
- [x] T008 Extend the `Region` aggregate struct with `kind, provision_owner_id, provisioned_at, source_room_id, origin_room_id, destroyed?` (state fields only, no new behavior) in `lib/agenticrealms/world/region.ex`

**Checkpoint**: Schema + base aggregate state ready — user stories can begin.

---

## Phase 3: User Story 1 - Provision a transient region on demand and explore it (Priority: P1) 🎯 MVP

**Goal**: A system-dispatched call provisions a transient region (simulated generator → a few durable rooms), places the provision-owner inside, and exposes an owner-only `:rift` entry exit that only the owner can see and traverse.

**Independent Test**: From IEx call `Transient.provision(owner_id, source_room_id)`; the owner lands in the origin room and can move among generated rooms; a second player in the source room neither sees nor can traverse the rift exit; a second `provision/2` for the same owner returns `{:error, :already_provisioned}`.

### Tests for User Story 1 ⚠️ (write first, ensure they fail)

- [x] T009 [P] [US1] Generator unit test (deterministic spec shape: region_id, rooms, intra/return exits, entry_exit) in `test/agenticrealms/world/transient/generator_test.exs`
- [x] T010 [P] [US1] Region aggregate unit test: `ProvisionTransientRegion` + `OpenTransientEntryExit` `execute`/`apply`, and `:region_already_exists` guard, in `test/agenticrealms/world/region_test.exs`
- [x] T011 [P] [US1] Integration test (`@moduletag :commanded`): provision → owner in origin room & can move; rift exit listed for owner only and `:no_exit_in_direction` for a non-owner; re-provision rejected — in `test/agenticrealms/world/transient/provision_integration_test.exs`

### Implementation for User Story 1

- [x] T012 [P] [US1] `ProvisionTransientRegion` command in `lib/agenticrealms/world/commands/provision_transient_region.ex`
- [x] T013 [P] [US1] `TransientRegionProvisioned` event in `lib/agenticrealms/world/events/transient_region_provisioned.ex`
- [x] T014 [P] [US1] `OpenTransientEntryExit` command in `lib/agenticrealms/world/commands/open_transient_entry_exit.ex`
- [x] T015 [P] [US1] `TransientEntryExitOpened` event in `lib/agenticrealms/world/events/transient_entry_exit_opened.ex`
- [x] T016 [US1] Region aggregate `execute`/`apply` for `ProvisionTransientRegion` and `OpenTransientEntryExit` in `lib/agenticrealms/world/region.ex` (depends on T008, T012–T015)
- [x] T017 [US1] Route `ProvisionTransientRegion` + `OpenTransientEntryExit` → `Region` in `lib/agenticrealms/world/router.ex`
- [x] T018 [US1] `WorldProjector` handlers: `TransientRegionProvisioned` → insert `regions` row (`kind: "transient"`, owner/provisioned_at/source/origin); `TransientEntryExitOpened` → insert owner-scoped `world_exits` row (`direction: "rift"`, `visible_to_user_id`) in `lib/agenticrealms/world/projections/world_projector.ex`
- [x] T019 [P] [US1] `Transient.Generator` — deterministic, hand-coded room/exit layout (no map data; rooms `map_visible: false`, nil coords) in `lib/agenticrealms/world/transient/generator.ex`
- [x] T020 [US1] `Transient.provision/2` orchestration in `lib/agenticrealms/world/transient/transient.ex`: FR-021 read-model guard → dispatch `ProvisionTransientRegion` → `CreateRoom` per generated room → `AddExit` intra-region + origin→source return exits → `OpenTransientEntryExit` (after origin room exists) → `MovePlayer` owner into origin (depends on T016–T019)
- [x] T021 [US1] Make exit listing viewer-aware: `Queries.list_exits/2` filters `is_nil(visible_to_user_id) or == viewer`, and `look_room/1` passes the viewer `player_id`, in `lib/agenticrealms/world/queries.ex`
- [x] T022 [US1] Make traversal viewer-aware: `Commands.resolve_exit/3` adds the same predicate (non-owner → `:no_exit_in_direction`), and `move/2` passes the viewer `player_id`, in `lib/agenticrealms/world/commands.ex`
- [x] T023 [US1] UI: render the owner-only rift exit chip distinctly and accept the `rift` move intent in `lib/agenticrealms_web/live/game_live.ex`, `lib/agenticrealms_web/live/game_live/*`, and `lib/agenticrealms_web/components/game/log_entry.ex`

**Checkpoint**: US1 fully functional — provision, explore, owner-only exit, re-provision guard all testable in isolation.

---

## Phase 4: User Story 2 - Transient region survives a process crash (Priority: P2)

**Goal**: Verify transient rooms are as durable as permanent rooms — present, stateful, and navigable after a process restart, with the lifetime cap anchored to the persisted `provisioned_at`.

**Independent Test**: Provision a region, restart the BEAM/Commanded chain, and confirm the rooms + rift exit replay from the event store and remain navigable; the original `provisioned_at` is unchanged.

> **No new production code is required** — transient rooms are ordinary event-sourced `Room` aggregates and inherit crash durability from the platform. This story is delivered by US1 and proven by the test below.

### Tests for User Story 2 ⚠️

- [x] T024 [US2] Durability integration test (`@moduletag :commanded`): provision → tear down & restart the Commanded/event-store chain → assert all transient rooms, intra-region exits, and the rift exit are restored and navigable, and `provisioned_at` is unchanged — in `test/agenticrealms/world/transient/durability_test.exs`

**Checkpoint**: US1 + US2 — provisioning works and survives restarts.

---

## Phase 5: User Story 3 - Region destroyed and fully purged when its owner logs off (Priority: P2)

**Goal**: When the provision-owner fully logs off (last session gone) and a ~2-minute grace elapses, a timed reaper relocates the owner, evicts the aggregate, and hard-purges every trace of the region (event streams, snapshots, read-model rows). An empty region stays alive while the owner is logged in elsewhere; a reconnect within the grace cancels destruction.

**Independent Test**: Provision a region; with the owner logged in but no one inside, confirm it is NOT purged; log the owner fully off and after grace+sweep confirm region/rooms/exits are gone, the `region-`/`room-` streams are hard-deleted, and the owner was relocated; reconnect within grace → region survives.

### Tests for User Story 3 ⚠️

- [x] T025 [P] [US3] Region aggregate unit test: `DestroyRegion` → `RegionDestroyed`, and idempotent no-op when already `destroyed?`, in `test/agenticrealms/world/region_test.exs`
- [x] T026 [P] [US3] `RegionLifespan` unit test: returns `:stop` on `RegionDestroyed`, finite/`:infinity` otherwise, in `test/agenticrealms/world/region_lifespan_test.exs`
- [x] T027 [P] [US3] `Transient.Purge` unit test via the injectable `:transient_event_store` seam: asserts the exact streams (`entity-*`, `room-*`, `region-*`), snapshots, and read-model rows targeted, deletes rows last, and is idempotent on re-run, in `test/agenticrealms/world/transient/purge_test.exs`
- [x] T028 [P] [US3] `Transient.Manager` unit test: `due?` logoff predicate (`owner_offline_since + grace_ms < now`) and presence stamp/clear of `owner_offline_since`, in `test/agenticrealms/world/transient/manager_test.exs`
- [x] T029 [US3] Purge/logoff integration test (`@moduletag :commanded`): owner full logoff → grace → reap → region/rooms/exits gone + owner relocated to `source_room_id`; empty region with owner online NOT purged; reconnect within grace survives — in `test/agenticrealms/world/transient/purge_integration_test.exs`

### Implementation for User Story 3

- [x] T030 [P] [US3] `DestroyRegion` command in `lib/agenticrealms/world/commands/destroy_region.ex`
- [x] T031 [P] [US3] `RegionDestroyed` event in `lib/agenticrealms/world/events/region_destroyed.ex`
- [x] T032 [US3] Region aggregate `execute`/`apply` for `DestroyRegion` with idempotent `destroyed?` guard in `lib/agenticrealms/world/region.ex` (depends on T016)
- [x] T033 [P] [US3] `RegionLifespan` (`AggregateLifespan` behaviour): `:stop` on `RegionDestroyed`, finite idle timeout otherwise, in `lib/agenticrealms/world/region_lifespan.ex`
- [x] T034 [US3] Router: route `DestroyRegion` → `Region` and attach `lifespan: RegionLifespan` in `lib/agenticrealms/world/router.ex` (depends on T017)
- [x] T035 [US3] `WorldProjector` handler for `RegionDestroyed` (evict-only / stamp `destroyed_at`; row deletion is owned by Purge, not the projector) in `lib/agenticrealms/world/projections/world_projector.ex` (depends on T018)
- [x] T036 [US3] `Transient.Purge.run/1` in `lib/agenticrealms/world/transient/purge.ex`: capture room/entity ids → hard-delete `entity-*`, `room-*`, `region-*` streams + room snapshots → delete read-model rows LAST (`world_objects` → `npc_clones` → `player_discovered_rooms` → `world_exits` → `world_rooms` → `regions`); idempotent; `@event_store` compile-env seam
- [x] T037 [US3] `Transient.Manager` GenServer in `lib/agenticrealms/world/transient/manager.ex`: subscribe to `"connected_players"` (stamp/clear `owner_offline_since`); periodic `:sweep` via `Process.send_after`; reap due (logoff predicate) by orchestrating relocate → `DestroyRegion` → `Purge`
- [x] T038 [US3] Add `Transient.Manager` to the supervision tree after the `Ticks` block in `lib/agenticrealms/application.ex`
- [x] T039 [US3] Owner relocation in the reap path: read `Queries.current_room_of/1` then `MovePlayer` back to `source_room_id` (skip if owner offline — FR-022 nilify safety net covers them) and emit a destruction notice, in `lib/agenticrealms/world/transient/transient.ex` / `manager.ex`
- [x] T040 [US3] `Transient.destroy/1` context function (force destroy + purge now; used by reaper, ops, tests) in `lib/agenticrealms/world/transient/transient.ex`

**Checkpoint**: US1 + US3 — provisioning plus durable purge-on-logoff with relocation and isolation.

---

## Phase 6: User Story 4 - Region destroyed after the 60-minute lifetime cap (Priority: P3)

**Goal**: Regardless of owner login state, a region is reaped no later than 60 minutes after `provisioned_at`. Crash recovery falls out for free — the stateless reaper re-derives `due?` from durable columns after a restart (FR-018).

**Independent Test**: Provision a region, keep the owner logged in, age `provisioned_at` past the cap (or shrink `region_lifetime_ms`), and confirm the reaper purges it; after a restart, an already-overdue region is reaped on the next sweep.

### Tests for User Story 4 ⚠️

- [x] T041 [P] [US4] `Transient.Manager` unit test: `due?` cap predicate (`provisioned_at + lifetime_ms < now`) in `test/agenticrealms/world/transient/manager_test.exs`
- [x] T042 [US4] Cap integration test (`@moduletag :commanded`): owner stays online, cap elapses → region reaped & purged — in `test/agenticrealms/world/transient/cap_integration_test.exs`
- [x] T043 [US4] Recovery integration test: an already-overdue / owner-offline region is reaped on the first sweep after the Manager (re)starts, with no in-memory state (FR-018) — in `test/agenticrealms/world/transient/recovery_test.exs`

### Implementation for User Story 4

- [x] T044 [US4] Add the cap predicate to the `Transient.Manager` sweep (`provisioned_at + lifetime_ms < now`), composed with the logoff predicate, in `lib/agenticrealms/world/transient/manager.ex` (depends on T037)

**Checkpoint**: All four stories independently functional.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [x] T045 [P] Edge-case tests: clean provisioning failure leaves no orphan region (FR-020) and no entry into a region whose teardown has begun (FR-011), in `test/agenticrealms/world/transient/edge_cases_test.exs`
- [ ] T046 [P] Postgres-event-store-backed purge test (`@tag :postgres_eventstore`) proving true hard-delete of streams (not exercisable on the in-memory adapter) in `test/agenticrealms/world/transient/purge_postgres_test.exs`
  - **DEFERRED (not automated).** The `:test` env runs the in-memory Commanded adapter (no `delete_stream`), and a real `AgenticRealms.EventStore` (Postgres) test would be non-hermetic (a shared, un-sandboxed event-store DB). Purge *target computation* (which streams/snapshots/rows) is fully covered by `purge_test.exs` via the recording stub; the actual hard-delete is a thin call into eventstore 1.4 (`delete_stream(..., :hard)`), verified manually via `quickstart.md` §3 against the dev Postgres event store.
- [x] T047 [P] Add witness/log entries for provision + destruction (observability) in `lib/agenticrealms/world/transient/transient.ex` / `manager.ex`
- [x] T048 [P] Run `specs/017-transient-regions/quickstart.md` end-to-end and reconcile any drift
- [x] T049 Run `mix precommit` (`compile --warnings-as-errors`, `deps.unlock --unused`, `format`, `test`) and fix findings

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (P1)** → no deps.
- **Foundational (P2)** → after Setup. **Blocks all stories.**
- **US1 (P3)** → after Foundational. The MVP.
- **US2 (P4)** → after US1 (needs something to crash-test). No new production code.
- **US3 (P5)** → after US1 (destroys/purges what US1 creates; reuses Region aggregate, regions/world_exits).
- **US4 (P6)** → after US3 (reuses `Transient.Manager`/`Purge`; adds the cap predicate).
- **Polish (P7)** → after the desired stories.

> Unlike a greenfield feature, US3/US4 are **not** independent of US1 — they operate on US1's aggregate + read models. The genuinely independent/parallelizable unit is US1 (MVP); US2 is a validation layer; US3 then US4 are incremental.

### Within a story

- Tests first (write, see them fail) → commands/events (`[P]`, separate files) → aggregate `execute`/`apply` → router → projector → context/services → queries/UI.
- Same-file edits are sequential: `region.ex` (T008 → T016 → T032), `router.ex` (T017 → T034), `world_projector.ex` (T018 → T035), `manager.ex` (T037 → T044).

### Parallel opportunities

- Setup: T001, T002 in parallel (T003 after T002).
- Foundational: T004, T005, T006, T007 in parallel; T008 after.
- US1: T009/T010/T011 (tests) in parallel; commands/events T012–T015 and the Generator T019 in parallel; then T016 → T017 → T018; T021 and T022 touch different files and can run in parallel after T018.
- US3: tests T025–T028 in parallel; commands/events T030/T031 and lifespan T033 in parallel; then the same-file chains.

---

## Parallel Example: User Story 1

```bash
# Tests for US1 together:
Task: "Generator unit test in test/agenticrealms/world/transient/generator_test.exs"
Task: "Region aggregate unit test in test/agenticrealms/world/region_test.exs"
Task: "Provision integration test in test/agenticrealms/world/transient/provision_integration_test.exs"

# Commands/events + generator together (separate files):
Task: "ProvisionTransientRegion command"
Task: "TransientRegionProvisioned event"
Task: "OpenTransientEntryExit command"
Task: "TransientEntryExitOpened event"
Task: "Transient.Generator"
```

---

## Implementation Strategy

### MVP first (US1 only)

1. Phase 1 Setup → 2. Phase 2 Foundational → 3. Phase 3 US1 → **STOP & validate**: provision a region from IEx, explore it, confirm owner-only exit. Demo-able MVP (regions linger until US3 lands — acceptable for the increment).

### Incremental delivery

1. Setup + Foundational → foundation ready.
2. US1 → provision & explore (MVP).
3. US2 → prove crash durability.
4. US3 → purge-on-logoff with relocation + isolation.
5. US4 → 60-minute cap + recovery backstop.
6. Polish → edge cases, Postgres hard-delete proof, observability, precommit.

---

## Notes

- `[P]` = different files, no incomplete dependency. `[Story]` = traceability to spec user stories.
- Forbidden in tests: nondeterministic time in *workflow scripts*; app/test code uses `DateTime.utc_now`. Test cap/grace by setting `provisioned_at`/`owner_offline_since` to past values, then triggering a sweep.
- Purge is destructive — keep the `@event_store` seam so unit tests assert targets without a real hard-delete; gate true hard-delete behind the Postgres-backed test (T046).
- Commit after each task or logical group; stop at any checkpoint to validate a story independently.
