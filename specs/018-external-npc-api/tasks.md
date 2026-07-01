---
description: "Task list for External NPC Brains — Game-Side Contract API"
---

# Tasks: External NPC Brains — Game-Side Contract API

**Input**: Design documents from `specs/018-external-npc-api/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: INCLUDED — Constitution Principle IV (Test-First, Green-Before-Merge) is
non-negotiable for this repo, so every aggregate/projector/context/integration
path gets tests written alongside or before its implementation.

**Organization**: Grouped by user story (spec.md priorities). MVP = US1+US2+US3+US4
(the P1 secure, self-starting enact loop). US5 (P2) and US6 (P3) follow.

**Paths**: repo root `/media/kevin/ExtraDrive1/code/autodidaddict/agentic-realms/`.
`lib/agenticrealms/...` = domain; `lib/agenticrealms_web/...` = web; `test/...` = ExUnit.

**Agreed constants** (must not drift from `agentic-realms-npc` feature 001): workflow
type `NpcWorkflow`, workflow id `npc-<entity_id>`, task queue `npc-minds`, input
`{entity_id}`, conflict policy `USE_EXISTING`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Config plumbing and the new context skeleton. No new dependencies
(Req, Commanded, Ecto, Horde already present).

- [x] T001 [P] Add compile-time defaults in `config/config.exs` under `:agenticrealms`: `temporal_base_url` (`http://localhost:7243`), `temporal_namespace` (`default`), `temporal_task_queue` (`npc-minds`), `npc_workflow_type` (`NpcWorkflow`), `npc_mind_reconcile_interval_ms` (`60000`).
- [x] T002 [P] Add runtime env wiring in the non-`:test` block of `config/runtime.exs`: `NPC_SERVICE_SECRET`, `TEMPORAL_HTTP_URL`, `TEMPORAL_NAMESPACE`, `NPC_TASK_QUEUE`, `TEMPORAL_API_KEY` (optional), `NPC_MIND_RECONCILE_MS` → the `:agenticrealms` keys.
- [x] T003 [P] Create `AgenticRealms.NpcMinds.Config` in `lib/agenticrealms/npc_minds/config.ex` reading the `:agenticrealms` app-env keys with defaults + helpers (`workflow_id(entity_id)` → `"npc-" <> id`), plus unit test `test/agenticrealms/npc_minds/config_test.exs`.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The `/api` surface and the shared read query that multiple HTTP
stories depend on. **⚠️ No HTTP user story can be completed until this phase is done.**

- [x] T004 Add `scope "/api", AgenticRealmsWeb` (pipe_through `[:api]`) with routes `get "/npc/:id/identity"`, `get "/npc/:id/surroundings"`, `post "/npc/:id/move"` in `lib/agenticrealms_web/router.ex`, and create `AgenticRealmsWeb.NpcServiceController` in `lib/agenticrealms_web/controllers/npc_service_controller.ex` with three stub actions (`identity/2`, `surroundings/2`, `move/2`) returning a placeholder JSON (filled per story). Auth plug is added in US3.
- [x] T005 [P] Add `AgenticRealms.World.Queries.list_global_exits/1` in `lib/agenticrealms/world/queries.ex` returning `[%{direction, target_room_id}]` for `source_room_id == room AND is_nil(visible_to_user_id)` (global exits only — excludes owner-only transient exits), with test `test/agenticrealms/world/queries_global_exits_test.exs`.

**Checkpoint**: `/api` routes resolve (unauthenticated stubs); shared exits query ready.

---

## Phase 3: User Story 1 - Enact an externally-decided move that players witness (Priority: P1) 🎯 MVP

**Goal**: A move submitted for an NPC relocates it via the existing command path with
the origin-room compare-and-swap guard, and players in both rooms witness leave/arrive
exactly like any NPC move; stale/invalid moves are refused.

**Independent Test**: `POST /api/npc/:id/move` with a valid direction + current room →
`{result: ok, from_room_id, to_room_id}` and watching players see "<name> leaves." /
arrival; stale `expected_room_id` → `409`; bad direction → `422`.

### Tests for User Story 1 ⚠️ (write first, must fail)

- [x] T006 [P] [US1] Contract tests for `POST /api/npc/:id/move` (200 ok; 409 conflict on stale origin; 422 no_such_exit on bad direction; 404 unknown entity) in `test/agenticrealms_web/npc_service_controller_move_test.exs`.
- [x] T007 [P] [US1] Broadcaster test: an `EntityMoved{kind: :npc, cause: :relocated, from: room, to: room}` fans out `RoomNPCLeft` to origin + `RoomNPCArrived` to destination in `test/agenticrealms/world/ui_event_broadcaster_npc_relocate_test.exs`.

### Implementation for User Story 1

- [x] T008 [US1] Implement `move/2` in `lib/agenticrealms_web/controllers/npc_service_controller.ex`: resolve `direction` against `Queries.list_global_exits(expected_room_id)` (absent → 422 `no_such_exit`); dispatch `Commands.move_entity(id, ContainerRef.room(expected_room_id), ContainerRef.room(to_room_id), :relocated)`; map `:ok`→200 `{result: ok, from_room_id, to_room_id}`, `{:error, :container_conflict}`→409 `{result: conflict}`, `{:error, :not_found}`→404, `{:error, :unsupported_container}`→422 `{result: no_such_exit}`.
- [x] T009 [US1] Add `witness_object_move(:npc, :relocated, %ContainerRef{type: :room, id: from}, %ContainerRef{type: :room, id: to}, npc_id)` clause in `lib/agenticrealms/world/ui_event_broadcaster.ex` → broadcast `RoomNPCLeft` to `room:from` + `RoomNPCArrived` to `room:to` (name via `lookup_npc_name/1`).
- [x] T010 [US1] Add `handle_info(%RoomNPCLeft{} = msg, socket)` → `UIEvents.npc_left(socket, msg)` in `lib/agenticrealms_web/live/game_live.ex`, and `npc_left/2` in `lib/agenticrealms_web/live/game_live/ui_events.ex` (append "<name> leaves." log; no Presence mutation — NPCs aren't in Presence).

**Checkpoint**: US1 fully functional and independently testable.

---

## Phase 4: User Story 2 - Provide an NPC's live surroundings (Priority: P1)

**Goal**: A pure read returns the NPC's current room, that room's global exits with
directions + destinations, and every occupant tagged by kind; void/removed → empty
snapshot, not an error.

**Independent Test**: `GET /api/npc/:id/surroundings` for an in-room NPC returns the
room, `exits:[{direction,to_room_id}]`, and `occupants:[{id,kind,name}]`; for a
void/removed NPC returns `{room_id:null, exits:[], occupants:[]}`; unknown → 404.

### Tests for User Story 2 ⚠️ (write first, must fail)

- [x] T011 [P] [US2] Contract tests for `GET /api/npc/:id/surroundings` (200 in-room with exits+occupants tagged by kind; 200 empty snapshot for void/removed; 404 unknown) in `test/agenticrealms_web/npc_service_controller_surroundings_test.exs`.
- [x] T012 [P] [US2] Add `AgenticRealms.World.Queries.list_players_in_room/1` (public) returning `[%{id, username}]` for players present in the room in `lib/agenticrealms/world/queries.ex` + test `test/agenticrealms/world/queries_players_in_room_test.exs`.

### Implementation for User Story 2

- [x] T013 [US2] Implement `surroundings/2` in `lib/agenticrealms_web/controllers/npc_service_controller.ex`: `room_id` = `NPCClone.room_id` (nil → empty snapshot); `exits` = `Queries.list_global_exits/1` mapped to `{direction, to_room_id}`; `occupants` = merge of `list_npcs_in_room` (kind `npc`), `list_objects_in_room` (kind `object`, all), `list_players_in_room` (kind `player`, `username` as name, **id stringified**); 404 when the entity is not an NPC.

**Checkpoint**: US1 + US2 both work independently.

---

## Phase 5: User Story 3 - Guard the contract with a shared secret (Priority: P1)

**Goal**: Every route requires a valid bearer token; missing/malformed/wrong → 401
before any read/write, not disclosing missing-vs-wrong; secret is config and rotatable;
fail-closed when unset.

**Independent Test**: Each of the 3 routes rejects no/incorrect token (401) and honors
the correct one; changing the configured secret rejects the old and accepts the new; an
unset secret rejects all.

### Tests for User Story 3 ⚠️ (write first, must fail)

- [x] T014 [P] [US3] Unit tests for the auth plug (missing header → 401; wrong token → 401; correct token → pass; unset secret → 401; no missing-vs-wrong disclosure) in `test/agenticrealms_web/plugs/require_service_token_test.exs`.
- [x] T015 [P] [US3] Integration tests across all 3 `/api/npc` routes: missing/wrong → 401, correct → non-401; secret rotation (reconfigure → old rejected, new accepted) in `test/agenticrealms_web/npc_service_auth_test.exs`.

### Implementation for User Story 3

- [x] T016 [US3] Implement `AgenticRealmsWeb.Plugs.RequireServiceToken` in `lib/agenticrealms_web/plugs/require_service_token.ex`: read `Application.get_env(:agenticrealms, :npc_service_secret)`; require `authorization: "Bearer <token>"`; `Plug.Crypto.secure_compare/2`; else `put_status(:unauthorized) |> json(...) |> halt()`; fail-closed when secret is nil/"".
- [x] T017 [US3] Add `AgenticRealmsWeb.Plugs.RequireServiceToken` to the `/api` scope's `pipe_through` in `lib/agenticrealms_web/router.ex` (→ `[:api, ...RequireServiceToken]`).

**Checkpoint**: All three routes are authenticated; US1–US3 = secure read+move MVP.

---

## Phase 6: User Story 4 - Automatically start a mind when an NPC is spawned (Priority: P1)

**Goal**: Every `EntityCloned{kind: :npc}` triggers a best-effort Temporal
`StartWorkflowExecution` (`npc-<id>`, `USE_EXISTING`); no game-side dedup — Temporal
enforces exactly-one.

**Independent Test**: Spawn an NPC → workflow `npc-<id>` is Running in Temporal; a
retried/replayed spawn starts no second mind; a Temporal outage doesn't block the spawn.

### Tests for User Story 4 ⚠️ (write first, must fail)

- [x] T018 [P] [US4] `TemporalClient.start_workflow/1` tests via `Req.Test` stub: asserts `POST .../workflows/npc-<id>`, body has `workflowType NpcWorkflow`, `taskQueue npc-minds`, `workflowIdConflictPolicy USE_EXISTING`, and base64 `input` payload (encoding + data); 2xx → `:ok`; non-2xx/transport error → `{:error, _}` in `test/agenticrealms/npc_minds/temporal_client_test.exs`.
- [x] T019 [P] [US4] `LifecycleManager` test: fed `EntityCloned{kind: :npc}` it calls `start_workflow(entity_id)`; `EntityCloned{kind: :object}` is ignored (inject a stub/mock client) in `test/agenticrealms/npc_minds/lifecycle_manager_test.exs`.

### Implementation for User Story 4

- [x] T020 [US4] Implement `AgenticRealms.NpcMinds.TemporalClient` in `lib/agenticrealms/npc_minds/temporal_client.ex`: `start_workflow/1` using `Req` (URL/namespace/queue/api-key from `NpcMinds.Config`), a Temporal `Payload` encoder (base64 `json/plain` + base64 data), `USE_EXISTING`, optional `Authorization: Bearer`; return `:ok | {:error, reason}` with logging (never raises).
- [x] T021 [US4] Implement `AgenticRealms.NpcMinds.LifecycleManager` (`use Commanded.Event.Handler, application: AgenticRealms.World.Application, name: __MODULE__, consistency: :eventual`) in `lib/agenticrealms/npc_minds/lifecycle_manager.ex` with `handle(%EntityCloned{kind: :npc}, _)` → `TemporalClient.start_workflow/1`; catch-all `→ :ok`.
- [x] T022 [US4] Register `AgenticRealms.NpcMinds.LifecycleManager` in the supervision tree in `lib/agenticrealms/application.ex` (after the World handlers block, e.g. beside `UIEventBroadcaster`).

**Checkpoint**: Spawning an NPC starts exactly one mind; MVP (US1–US4) complete.

---

## Phase 7: User Story 5 - Automatically terminate a mind when an NPC is removed (Priority: P2)

**Goal**: Introduce a first-class event-sourced NPC removal (`RemoveEntity` →
`EntityRemoved`) that deletes the read-model row, witnesses `RoomNPCLeft`, and triggers
`TerminateWorkflowExecution`; the transient purge also terminates out-of-band.

**Independent Test**: `Commands.remove_npc(id)` → `npc-<id>` Terminated + `npc_clones`
row gone + players see "<name> leaves."; removing an already-removed id → `{:error,
:not_found}`; terminating an absent mind is a no-op; a transient-region purge terminates
its NPCs' minds.

### Tests for User Story 5 ⚠️ (write first, must fail)

- [x] T023 [P] [US5] `Entity` aggregate tests: `RemoveEntity` on an existing entity emits `EntityRemoved{kind, from}`; on unknown/already-removed → `{:error, :not_found}`; `apply` marks removed; lifespan `:stop` on `EntityRemoved` in `test/agenticrealms/world/entity_remove_test.exs`.
- [x] T024 [P] [US5] Projector test: `EntityRemoved{kind: :npc}` deletes the `npc_clones` row and is idempotent/replay-safe (re-handle = no-op) in `test/agenticrealms/world/entity_removed_projector_test.exs`.
- [x] T025 [P] [US5] `TemporalClient.terminate_workflow/1` test (`POST .../workflows/npc-<id>/terminate`; absent/closed workflow → `:ok`) — extend `test/agenticrealms/npc_minds/temporal_client_test.exs`.
- [x] T026 [P] [US5] Purge test: `Transient.Purge` calls `terminate_workflow` for each removed NPC id (stub client) and still completes if a terminate fails in `test/agenticrealms/world/transient/purge_terminate_test.exs`.

### Implementation for User Story 5

- [x] T027 [P] [US5] Add `AgenticRealms.World.Commands.RemoveEntity` (`%{entity_id}`) in `lib/agenticrealms/world/commands/remove_entity.ex` and `AgenticRealms.World.Events.EntityRemoved` (`%{entity_id, kind, from, version: 1}`, `@derive Jason.Encoder`) in `lib/agenticrealms/world/events/entity_removed.ex`.
- [x] T028 [US5] `Entity` aggregate in `lib/agenticrealms/world/entity.ex`: `execute(RemoveEntity)` → `EntityRemoved{kind: state.kind, from: state.container}` (unknown/removed → `{:error, :not_found}`); `apply(%EntityRemoved{})` marks removed; add `after_event(%EntityRemoved{})` → `:stop` to the lifespan.
- [x] T029 [US5] Route `[RemoveEntity]` → `Entity` in `lib/agenticrealms/world/router.ex`; add `remove_entity/1` + `remove_npc/1` (dispatch `consistency: :strong`) to `lib/agenticrealms/world/commands.ex`.
- [x] T030 [US5] Handle `EntityRemoved` in the entity/world projector (`lib/agenticrealms/world/projections/...`): delete `npc_clones` row for `:npc` (and `world_objects` for `:object`), delete-by-pk, idempotent.
- [x] T031 [US5] Add `TemporalClient.terminate_workflow/1` to `lib/agenticrealms/npc_minds/temporal_client.ex` (map absent/closed → `:ok`).
- [x] T032 [US5] Add `handle(%EntityRemoved{kind: :npc}, _)` → `TemporalClient.terminate_workflow/1` to `lib/agenticrealms/npc_minds/lifecycle_manager.ex`.
- [x] T033 [US5] Add witness for `EntityRemoved{kind: :npc, from: %{type: :room, id: rid}}` → broadcast `RoomNPCLeft` to `room:rid` in `lib/agenticrealms/world/ui_event_broadcaster.ex` (+ test alongside T007's file or a new one).
- [x] T034 [US5] In `lib/agenticrealms/world/transient/purge.ex`, terminate minds for the collected NPC ids (best-effort `TemporalClient.terminate_workflow/1`) before deleting read-model rows; failures logged, never block the purge.

**Checkpoint**: Removal (command path + purge path) terminates minds and cleans the read model.

---

## Phase 8: User Story 6 - Provide an NPC's identity and lore (Priority: P3)

**Goal**: A stable identity read (name, short/long description, lore) from the NPC clone
read model.

**Independent Test**: `GET /api/npc/:id/identity` returns the four fields for an existing
NPC; unknown → 404.

### Tests for User Story 6 ⚠️ (write first, must fail)

- [x] T035 [P] [US6] Contract tests for `GET /api/npc/:id/identity` (200 with name/short_description/long_description/lore; 404 unknown) in `test/agenticrealms_web/npc_service_controller_identity_test.exs`.

### Implementation for User Story 6

- [x] T036 [US6] Implement `identity/2` in `lib/agenticrealms_web/controllers/npc_service_controller.ex` via `Repo.get(NPCClone, id)` (404 when nil); ensure/reuse `Queries.get_npc_clone_row/1`.

**Checkpoint**: All six user stories independently functional.

---

## Phase 9: Cross-Cutting — Reconciliation & Hardening (required)

**Purpose**: The reconciliation backstop (FR-029a, SC-013) that spans US4+US5, plus
validation. Not optional polish.

- [x] T037 [P] `Reconciler.diff/2` pure-function test (`{to_start: live − running, to_terminate: running − live}`) in `test/agenticrealms/npc_minds/reconciler_test.exs`.
- [x] T038 Add `TemporalClient.list_running_npc_ids/0` (ListWorkflowExecutions visibility query `WorkflowType = 'NpcWorkflow' AND ExecutionStatus = 'Running'`, paginate, strip `npc-` prefix) in `lib/agenticrealms/npc_minds/temporal_client.ex` + test extension.
- [x] T039 Implement `AgenticRealms.NpcMinds.Reconciler` in `lib/agenticrealms/npc_minds/reconciler.ex`: cluster-singleton GenServer with `Process.send_after` sweep; each sweep computes `live` (ids from `npc_clones`) vs `running` (`list_running_npc_ids/0`), starts `to_start`, terminates `to_terminate` (all idempotent).
- [x] T040 Register `Reconciler` as a **cluster singleton** in `lib/agenticrealms/application.ex` via the project's Horde registry/supervisor (one cluster-wide instance; `:global`-named fallback documented in research R5).
- [ ] T041 [P] Execute `specs/018-external-npc-api/quickstart.md` end-to-end (auth gate, identity/surroundings, move + witness, spawn→start, remove→terminate, outage→reconcile).
- [x] T042 Run `mix precommit` (compile `--warnings-as-errors`, `format`, full `test`) — the merge gate (Constitution IV).

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (P1)** → no deps.
- **Foundational (P2)** → after Setup; blocks all HTTP stories (US1, US2, US3, US6).
- **US4/US5 (lifecycle)** depend on Setup config (T001–T003) but NOT on the HTTP
  Foundational routes — they can proceed in parallel with the HTTP stories once Setup
  is done.
- **Phase 9 (reconciler)** depends on US4 (TemporalClient scaffold) and US5 (removal
  semantics + terminate).

### User-story dependencies

- **US1 (move)** → Foundational (T004 routes, T005 exits query). Independent.
- **US2 (surroundings)** → Foundational (T004, T005). Independent of US1.
- **US3 (auth)** → Foundational (T004 routes exist to guard). Independent of US1/US2 bodies.
- **US4 (start)** → Setup (T003 Config). Independent of the HTTP stories.
- **US5 (terminate)** → Setup (T003); reuses TemporalClient (T020) if US4 done first, else T031 creates it. Removal command/event/projector are self-contained.
- **US6 (identity)** → Foundational (T004). Independent.

### Within a story

- Tests before implementation (Constitution IV).
- Structs/commands/events before the aggregate/projector that use them.
- Same-file edits are sequential (not `[P]`): `npc_service_controller.ex` (T008/T013/T036),
  `temporal_client.ex` (T020/T031/T038), `lifecycle_manager.ex` (T021/T032),
  `ui_event_broadcaster.ex` (T009/T033), `application.ex` (T022/T040).

### Parallel opportunities

- Setup T001/T002/T003 all `[P]`.
- Foundational T005 `[P]` (T004 is router+controller, separate file group).
- Within each story, the `[P]` test tasks run together; different stories can be built
  by different developers once Setup+Foundational land.

---

## Parallel Example: User Story 1

```bash
# Tests first, together:
Task: "Contract tests for POST /api/npc/:id/move in test/agenticrealms_web/npc_service_controller_move_test.exs"
Task: "Broadcaster test for :npc :relocated fan-out in test/agenticrealms/world/ui_event_broadcaster_npc_relocate_test.exs"
# Then implementation (T008 → T009 → T010; T009/T010 touch different files, T008 is the controller).
```

## Parallel Example: Lifecycle (US4 + US5 by a second developer)

```bash
# While devs A/B build the HTTP stories, dev C builds the lifecycle half after Setup:
Task: "TemporalClient.start_workflow/1 + tests (T018, T020)"
Task: "RemoveEntity/EntityRemoved + Entity aggregate + projector (T023, T024, T027, T028, T030)"
```

---

## Implementation Strategy

### MVP (secure, self-starting enact loop = US1 + US2 + US3 + US4)

1. Phase 1 Setup → Phase 2 Foundational.
2. US1 (move + witness) → US2 (surroundings) → US3 (auth) → US4 (start on spawn).
3. **STOP & VALIDATE**: an authenticated worker can read identity/surroundings, move an
   NPC that players witness, and every spawned NPC gets a mind. Demo.

### Incremental delivery

4. US5 (terminate on removal) → keeps minds in step with live NPCs.
5. US6 (identity/lore) → richer decisions.
6. Phase 9 reconciler → eventual consistency after Temporal outages (SC-013).

### Notes

- `[P]` = different files, no incomplete-task dependency.
- Commit after each task or logical group (no AI attribution — Constitution V).
- Verify each test fails before implementing (Constitution IV).
- Do not let a Temporal outage block any world change — the handoff is best-effort and
  the reconciler is the backstop.
