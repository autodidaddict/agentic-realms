# Phase 0 Research — External NPC Brains (Game-Side)

All decisions below resolve the Technical Context unknowns. No `NEEDS
CLARIFICATION` remain. Concrete code anchors are in the current codebase.

---

## R1. "Process manager" primitive: `Commanded.Event.Handler`

- **Decision**: Implement the lifecycle "process manager" as a named
  `Commanded.Event.Handler` (`AgenticRealms.NpcMinds.LifecycleManager`,
  `consistency: :eventual`), mirroring `AgenticRealms.World.UIEventBroadcaster`.
  It pattern-matches `EntityCloned{kind: :npc}` → `TemporalClient.start_workflow`
  and `EntityRemoved{kind: :npc}` → `TemporalClient.terminate_workflow`.
- **Rationale**: The lifecycle action is an *external HTTP side effect*. Commanded
  `ProcessManager`s exist to route events into **commands** and hold correlation
  state; using one here would force an artificial command and still couldn't do
  HTTP cleanly. A named handler is the idiomatic primitive for "react to an event
  with a side effect" and the codebase already uses exactly this shape.
- **Cluster bonus (Principle I)**: A named Commanded handler is an **exclusive,
  single cluster-wide subscriber** (one node processes each event at the
  subscription position) — so the happy-path start/terminate is already a cluster
  singleton with no extra machinery.
- **Alternatives considered**: (a) real `Commanded.ProcessManager` — rejected,
  awkward for external I/O; (b) subscribe in the reconciler GenServer only —
  rejected, loses the immediate, event-driven handoff and makes the sweep the
  only path.

## R2. Start trigger = `EntityCloned{kind: :npc}`; every NPC

- **Decision**: Start a mind on `EntityCloned` with `kind == :npc`. No gating.
- **Rationale**: `EntityCloned` (`lib/agenticrealms/world/events/entity_cloned.ex`,
  fields `entity_id, kind, fields`) is the canonical "an NPC came into existence"
  event; feature-016 births the entity in the void, then a paired `EntityMoved`
  (`cause: :spawned`) places it. Starting at clone time is correct — the mind's
  first surroundings read returns the empty/void snapshot until placement, which
  the contract already handles. Spec clarification: **every** spawned NPC gets a
  mind; the `fixed` flag means "ungettable", not "stationary", so it does not
  gate.
- **Alternative considered**: trigger on `EntityMoved{cause: :spawned, kind: :npc}`
  — rejected as unnecessarily late and coupled to placement; clone is the cleaner
  existence signal.

## R3. NPC removal → new `RemoveEntity`/`EntityRemoved` (event-sourced)

- **Decision**: Add a generic `RemoveEntity{entity_id}` command → `EntityRemoved{
  entity_id, kind, from}` event on the existing `Entity` aggregate
  (`lib/agenticrealms/world/entity.ex`). The aggregate validates existence
  (`{:error, :not_found}` when unknown/already removed), emits `EntityRemoved`
  carrying its `kind` and current container (`from`), applies a removed marker,
  and stops via `AggregateLifespan` on `EntityRemoved`. A projector reacting to
  `EntityRemoved` **deletes** the read-model row (`npc_clones` for `:npc`,
  `world_objects` for `:object`), idempotently.
- **Rationale**: No removal event exists today (Explore confirmed: NPCs are only
  removed by the transient hard-purge, which deletes streams and emits nothing).
  The spec clarification chose to add a first-class event. Principle II forbids
  deleting the read-model row outside a projector. **The projector delete is
  load-bearing**: the reconciler treats `npc_clones` as the live-NPC set, so a
  removal that left the row would resurrect the terminated mind on the next sweep.
- **Caller (this feature)**: a `Commands.remove_entity/1` (+ `remove_npc/1`)
  facade dispatched with `consistency: :strong`; wired into tests and the
  quickstart. (No admin UI is in scope; the command is the first-class capability.)
- **Transient purge path**: the purge cannot carry an event (it deletes the
  stream), so it terminates minds **out-of-band** — a best-effort
  `TemporalClient.terminate_workflow/1` per collected `npc_id` inside
  `Transient.Purge`, before the read-model rows are deleted. It does not block or
  fail the purge.

## R4. Temporal HTTP API (outbound) — endpoints, payloads, idempotency

The game calls **Temporal's HTTP API** (never the worker). Reached with `Req`
(already a dep; same client as `AgenticRealms.Anthropic`). Base URL, namespace,
task queue, optional API key are config.

- **Start** (`StartWorkflowExecution`):
  `POST {base}/api/v1/namespaces/{ns}/workflows/{workflowId}`
  where `workflowId = "npc-" <> entity_id`. Body (abridged):
  ```json
  {
    "workflowType": { "name": "NpcWorkflow" },
    "taskQueue":    { "name": "npc-minds" },
    "input": [ { "metadata": { "encoding": "<base64 'json/plain'>" },
                 "data": "<base64 of {\"entity_id\":\"<uuid>\"}>" } ],
    "workflowIdConflictPolicy": "WORKFLOW_ID_CONFLICT_POLICY_USE_EXISTING",
    "requestId": "<uuid>"
  }
  ```
  `USE_EXISTING` makes a second start for a running NPC return the existing run
  instead of erroring → **idempotency is the orchestrator's**, matching FR-025.
- **Terminate** (`TerminateWorkflowExecution`):
  `POST {base}/api/v1/namespaces/{ns}/workflows/{workflowId}/terminate`
  Body: `{ "reason": "npc removed", "identity": "agentic-realms" }`.
  Terminating an absent/already-closed workflow returns a benign not-found the
  client treats as success → **tolerance is the orchestrator's**, matching FR-028.
- **List running** (reconciler, `ListWorkflowExecutions`):
  `GET {base}/api/v1/namespaces/{ns}/workflows?query=<visibility>` with
  `query = "WorkflowType = 'NpcWorkflow' AND ExecutionStatus = 'Running'"`;
  extract each `execution.workflowId`, strip the `npc-` prefix → running NPC ids.
- **Payload encoding**: Temporal `Payloads` require base64 `metadata.encoding`
  (`json/plain`) and base64 `data`. This is the one fiddly bit — isolate it in
  `TemporalClient` and unit-test the encoder against a known-good fixture.
- **Auth to Temporal**: local `temporal server start-dev` needs none; Temporal
  Cloud uses `Authorization: Bearer <temporal_api_key>` (config
  `:temporal_api_key`, sent only when set). Transport security is the deployment's.
- **Rationale / alternatives**: The official Temporal Elixir SDK is gRPC-first
  and heavier; the HTTP API + `Req` needs zero new deps and matches the
  `agentic-realms-npc` contract note ("Temporal's HTTP API locally, Temporal
  Cloud's HTTP API later"). Rejected: adding a gRPC Temporal client dependency
  (Principle VI — unjustified new dep).

## R5. Reconciler — cluster-singleton periodic diff

- **Decision**: `AgenticRealms.NpcMinds.Reconciler`, a **cluster-wide singleton
  GenServer** started via the project's existing Horde registry/supervisor (so
  exactly one runs cluster-wide and is relocated on node loss), with a
  `Process.send_after/3` sweep loop (mirroring `Transient.Manager`'s timer
  style). Each sweep: `live = ids(npc_clones)`, `running =
  TemporalClient.list_running_npc_ids()`; **start** `live − running`, **terminate**
  `running − live`. The diff is a pure function (`Reconciler.diff/2`) and is
  unit-tested in isolation.
- **Rationale**: Realizes the "best-effort + reconcile" clarification and SC-013
  (convergence after a Temporal outage). Cluster singleton (Principle I) avoids N
  nodes each scanning Temporal every interval. All operations are idempotent
  (USE_EXISTING start, tolerant terminate), so even overlapping sweeps are safe —
  the singleton is for efficiency and clarity, not correctness of a single op.
- **Cluster note**: `Ticks.Lifecycle` and `Transient.Manager` are deliberately
  *node-local* (they observe Presence per node). The reconciler is different — a
  global convergence task — so it is a singleton. `:global`-registered name is the
  documented fallback if Horde singleton wiring proves heavy.
- **Interval**: config `:npc_mind_reconcile_interval_ms`, default 60_000.
- **Alternatives**: durable outbox (persist intents + retry) — rejected as
  heavier than an idempotent list-and-diff that leans on Temporal's own
  guarantees; per-node sweep — rejected (redundant Temporal load at scale).

## R6. Inbound API — `/api` scope, bearer plug, JSON

- **Decision**: New `scope "/api"` in `lib/agenticrealms_web/router.ex` piped
  through `[:api, AgenticRealmsWeb.Plugs.RequireServiceToken]` →
  `NpcServiceController` actions `identity/2`, `surroundings/2`, `move/2`.
  Responses via `Phoenix.Controller.json/2` + `put_status/2`. `Jason` is the
  configured JSON library. The `:api` pipeline (`plug :accepts, ["json"]`) exists.
- **Auth plug**: `RequireServiceToken` reads
  `Application.get_env(:agenticrealms, :npc_service_secret)`, requires
  `authorization: "Bearer <token>"`, compares with
  `Plug.Crypto.secure_compare/2` (constant-time), else `401` + `halt`. It does not
  disclose missing-vs-wrong (FR-027). If the secret is unconfigured, all calls are
  rejected (fail closed).
- **Rationale**: Matches existing plug/controller idioms (`PlayerAuth`,
  `PlayerSessionController`, `error_json.ex`). No `FallbackController` exists, so
  each action maps results to status codes explicitly.

## R7. Read model for identity & surroundings

- **Identity**: `Repo.get(NPCClone, id)` → `name, short_description,
  long_description, lore`; `nil` → `404`. (Add/confirm `Queries.get_npc_clone_row/1`.)
- **Surroundings**:
  - `room_id` = the clone's `room_id` (`nil` → void: empty snapshot, not an error).
  - `exits` = **new** `Queries.list_global_exits/1` returning `%{direction,
    target_room_id}` filtered to `visible_to_user_id IS NULL` (global exits only —
    excludes owner-only transient exits from FR-014). The existing private
    `list_exits/2` returns `{direction, target_name}` and is viewer-scoped, so a
    new function is required.
  - `occupants` = merge of `list_npcs_in_room/1` (kind `npc`),
    `list_objects_in_room/1` (kind `object`, all objects — trusted service view,
    not per-player quest-gated), and players in the room via the existing
    room-players query (kind `player`, `username` as name, **id stringified**),
    each tagged with `kind`.
- **Rationale**: Reuses existing indexed queries; the only addition is the
  global-exits selector. Player ids are integers internally and stringified at the
  contract boundary (FR-029).

## R8. Witness fan-out & LiveView

- **Decision**: Add `UIEventBroadcaster.witness_object_move/5` clause for
  `(:npc, :relocated, %ContainerRef{type: :room}, %ContainerRef{type: :room}, id)`
  → broadcast `RoomNPCLeft` (origin) + `RoomNPCArrived` (destination), using
  `lookup_npc_name/1`. Also witness `EntityRemoved{kind: :npc, from: room}` →
  `RoomNPCLeft` to that room. Add `GameLive` `handle_info(%RoomNPCLeft{})` →
  `UIEvents.npc_left/2` (append departure log; no Presence mutation — NPCs aren't
  in Presence).
- **Rationale**: `RoomNPCLeft`/`RoomNPCArrived` structs already exist; the object
  `:relocated` clause is the exact template. This makes a mind-driven move
  indistinguishable from any other NPC move (FR-022, SC-001).

## R9. Config keys (`:agenticrealms` app env)

Compile-time defaults in `config/config.exs`; runtime env in the non-test block
of `config/runtime.exs` (mirroring `AgenticRealms.Anthropic`):

| Key | Env var | Default |
|---|---|---|
| `:npc_service_secret` | `NPC_SERVICE_SECRET` | (unset → API fails closed) |
| `:temporal_base_url` | `TEMPORAL_HTTP_URL` | `http://localhost:7243` (start-dev `--http-port`) |
| `:temporal_namespace` | `TEMPORAL_NAMESPACE` | `default` |
| `:temporal_task_queue` | `NPC_TASK_QUEUE` | `npc-minds` |
| `:temporal_api_key` | `TEMPORAL_API_KEY` | (unset → no auth header) |
| `:npc_workflow_type` | — | `NpcWorkflow` |
| `:npc_mind_reconcile_interval_ms` | `NPC_MIND_RECONCILE_MS` | `60000` |

Task queue `npc-minds`, workflow type `NpcWorkflow`, workflow id `npc-<entity_id>`,
input `{entity_id}`, conflict policy `USE_EXISTING` are the **agreed contract
values** with `agentic-realms-npc` feature 001 and must not drift.

## R10. Testing strategy

- **Pure/unit (no DB)**: `Entity` `RemoveEntity` execute/apply; reconciler
  `diff/2`; Temporal payload encoder; controller result→status mapping; auth plug.
- **Temporal**: stub `Req` via `Req.Test`/plug so `TemporalClient` is asserted
  against request shape (path, body, conflict policy, payload base64) with no live
  server; `LifecycleManager` tested by feeding it events and asserting the stubbed
  client was called (inject the client module or use a test double).
- **Commanded/Ecto (`:commanded` + sandbox)**: `EntityRemoved` projector deletes
  the row and is replay-safe; `list_global_exits/1` returns only global exits;
  purge terminates minds for its npc_ids (client stubbed).
- **Web contract**: `NpcServiceController` — identity (200/404), surroundings
  (200 in-room/void, 404 unknown), move (200 ok, 409 conflict, 422 no_such_exit /
  unsupported, 404 unknown), and 401 for missing/wrong token on every route.
- Gate: `mix precommit`.
