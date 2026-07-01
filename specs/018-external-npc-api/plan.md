# Implementation Plan: External NPC Brains — Game-Side Contract API

**Branch**: `018-external-npc-api` | **Date**: 2026-07-01 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/018-external-npc-api/spec.md`

## Summary

Move autonomous NPC decision-making **out** of the game. The game gains three
responsibilities: (1) an authenticated HTTP **contract** an external mind calls
to read an NPC's identity/lore, read its surroundings, and submit a move;
(2) a **mind-lifecycle handoff** — a Commanded event handler ("process manager")
that reacts to NPC spawn and NPC-removal *domain events* by calling the
**Temporal server's HTTP API** to start/terminate the NPC's workflow; and (3) a
**cluster-singleton reconciliation sweep** that converges running minds to the
set of live NPCs so the best-effort handoff is eventually consistent after a
Temporal outage.

Key design decisions from Phase 0 research:

1. **The "process manager" is a `Commanded.Event.Handler`, not a Commanded
   `ProcessManager`.** A `ProcessManager` routes events → commands; our need is
   an *external* side effect (an HTTP call to Temporal). A named event handler is
   the idiomatic primitive, and — importantly — a named Commanded handler is an
   **exclusive, single cluster-wide subscriber**, which makes the start/terminate
   handoff a cluster singleton for free (Principle I).
2. **NPC removal must become a first-class event.** No NPC-removal domain event
   exists today (NPCs are only removed by the transient-region hard-purge, which
   emits nothing). This feature adds a generic `RemoveEntity` command →
   `EntityRemoved` event on the existing `Entity` aggregate, with a projector that
   **deletes the read-model row**. The projector delete is not optional: the
   reconciler derives "live NPCs" from `npc_clones`, so a removal that left the
   row would make the reconciler resurrect the terminated mind.
3. **Every spawned NPC gets a mind** (clarified) — the trigger is
   `EntityCloned{kind: :npc}`; there is no per-NPC gating.
4. **No new dependency.** Temporal is reached with `Req` (already used by the
   Anthropic client) against Temporal's HTTP API; Commanded/Ecto/Horde already
   present. The Temporal HTTP `StartWorkflowExecution` call uses
   `workflowIdConflictPolicy = USE_EXISTING`, so the *orchestrator* enforces
   "exactly one mind per NPC" (the game does no bookkeeping).

## Technical Context

**Language/Version**: Elixir ~1.20 (OTP), Phoenix 1.8 / LiveView 1.1
**Primary Dependencies**: Commanded 1.4.x + commanded_eventstore_adapter + eventstore (PostgreSQL), Ecto/Postgrex, Horde 0.10, Phoenix.Presence, **Req ~> 0.5** (reused for the outbound Temporal HTTP calls), Jason
**Storage**: Two PostgreSQL databases — event store (`AgenticRealms.EventStore`) and read model (`AgenticRealms.Repo`). **No schema migration required** (removal deletes existing read-model rows; no new columns).
**External systems**: **Temporal server** (durable-workflow engine) reached over its **HTTP API** — start/terminate/list workflow executions. The `agentic-realms-npc` worker service is *not* called by the game.
**Testing**: ExUnit; `AgenticRealms.DataCase` (Ecto SQL Sandbox + `@moduletag :commanded`). Pure logic (aggregate execute/apply, reconciler diff, payload encoding, controller shaping) unit-tested without the DB; Temporal HTTP calls tested with a stubbed `Req` (`Req.Test`/plug stub) — no live Temporal in the suite.
**Target Platform**: Linux server; multi-node BEAM cluster (Horde present) — cluster semantics are a first-class concern here (Principle I).
**Project Type**: Web application (Phoenix LiveView front end + event-sourced domain backend) + new outbound integration + new inbound service API.
**Performance Goals**: Contract reads are single indexed Ecto queries (identity = `Repo.get`; surroundings = a few room-scoped selects). Move = one `:strong` dispatch. Lifecycle handoff is a single async HTTP call off the world-change path. Reconciler sweep is O(live NPCs) once per interval.
**Constraints**: World spawn/removal MUST never be blocked by the handoff (best-effort + reconcile); the contract MUST reject unauthenticated calls before any read/write; moves MUST be compare-and-swap safe and retry-idempotent; the handoff/terminate calls target the Temporal HTTP API only, never the worker.
**Scale/Scope**: Target ≥500 concurrent, mostly-idle NPC minds (spec SC-008, enforced on the worker side); game side must sustain 500+ lifecycle calls over time and a reconciler diff over ~500 rows per interval.

**Unknowns resolved in Phase 0** (see `research.md`): Temporal HTTP API endpoints + payload encoding + conflict policy; process-manager primitive choice; reconciler cluster-singleton strategy; removal-event shape; exits query variant; auth plug shape. **No `NEEDS CLARIFICATION` remain.**

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Constitution v1.0.0 (ratified 2026-06-09). Assessment against the six principles:

| Principle | Assessment |
|---|---|
| **I. Cluster-Correct by Default (NON-NEGOTIABLE)** | **PASS (with stated semantics).** The lifecycle handoff is a *named* `Commanded.Event.Handler` → exclusive single cluster-wide subscriber, so exactly one node issues each start/terminate. The **reconciler** is a **cluster-wide singleton** (registered via the project's existing Horde registry/supervisor so exactly one runs cluster-wide and is relocated on node loss); `:global` is the documented fallback. Cluster semantics are stated in the spec (best-effort + reconcile) and here. The API controller and auth plug are stateless request-scoped code (node-local is correct). |
| **II. Event-Sourcing Invariants (NON-NEGOTIABLE)** | **PASS.** NPC removal is added as `RemoveEntity` → `EntityRemoved` through the `Entity` aggregate (sole writer; validates existence; state via `apply/2`). The read-model row is deleted **only by a projector** reacting to `EntityRemoved` (idempotent). Temporal start/terminate are external side effects in an event handler, not read-model writes; business decisions read the *event*, not raw event tables. The transient-purge terminate is an out-of-band external call within the already-justified destructive purge flow (no event-store write added). |
| **III. Local-First LiveView Interaction** | **PASS.** The only LiveView change is a new `RoomNPCLeft` `handle_info` clause that appends a log line from a PubSub world event. A round-trip is inherent and justified: it is a server-authoritative, cross-client world broadcast (not client-local behavior). |
| **IV. Test-First, Green-Before-Merge** | **PASS.** Unit tests precede/accompany: `Entity` `RemoveEntity` execute/apply, the `EntityRemoved` projector (deletes row, idempotent/replay-safe), the reconciler diff (pure), Temporal payload encoding, the auth plug, and the controller contract behaviors (200/401/404/409/422). `mix precommit` (warnings-as-errors, format, test) is the gate. |
| **V. Clean Git History — No AI Attribution (NON-NEGOTIABLE)** | **PASS.** All commits on this branch omit attribution; continues. |
| **VI. Idiomatic Phoenix & Deliberate Simplicity** | **PASS.** Zero new dependencies (Req/Commanded/Ecto/Horde already present). New cohesive `AgenticRealms.NpcMinds` context; reuses `Entity` aggregate, `Commands` facade, existing witness/UIEvents, existing config pattern. The reconciler is the one added moving part — justified below. |

**Design elements worth flagging** (tracked in Complexity Tracking): the reconciliation singleton (added machinery) and reusing "process manager" to mean a Commanded event handler.

**Post-Design re-check**: PASS — the design stays within existing patterns (aggregate/command/event/projector, named event handler, Horde singleton, `/api` scope + plug, `Req` client, `:agenticrealms` app-env config). No principle is bent.

## Project Structure

### Documentation (this feature)

```text
specs/018-external-npc-api/
├── plan.md              # This file
├── research.md          # Phase 0 — decisions & rationale (Temporal HTTP, PM choice, reconciler, removal event)
├── data-model.md        # Phase 1 — new command/event, read-model impact, snapshot shapes, reconciler state
├── quickstart.md        # Phase 1 — run Temporal + game, drive the loop, verify start/move/terminate/reconcile
├── contracts/
│   ├── npc-service-api.md               # The 3 game-exposed HTTP routes (identity/surroundings/move) + auth + status codes
│   ├── temporal-workflow-lifecycle.md   # Outbound: Temporal HTTP start/terminate/list + payload encoding + conflict policy
│   └── domain-events.md                 # New RemoveEntity command + EntityRemoved event + projector/witness contract
├── checklists/
│   └── requirements.md  # Spec quality checklist (already present)
└── tasks.md             # Phase 2 — created by /speckit.tasks (NOT here)
```

### Source Code (repository root)

New `NpcMinds` context (lifecycle + Temporal + reconciler), a new web API surface (controller + auth plug + `/api` scope), a generic entity-removal command/event on the existing `Entity` aggregate, one new read query, witness + LiveView additions, config, and supervision-tree wiring.

```text
lib/agenticrealms/npc_minds/            # NEW context
├── temporal_client.ex                  # NEW  Req client: start_workflow/1, terminate_workflow/1, list_running_npc_ids/0 (payload encode, conflict policy USE_EXISTING)
├── lifecycle_manager.ex                # NEW  Commanded.Event.Handler ("process manager", consistency: :eventual): EntityCloned{kind: :npc}→start; EntityRemoved{kind: :npc}→terminate
├── reconciler.ex                       # NEW  cluster-singleton GenServer: periodic sweep diff(live npc_clones ids ↔ running Temporal ids) → start missing / terminate orphaned
└── config.ex                           # NEW  reads :agenticrealms app-env (temporal base_url/namespace/api_key/task_queue, workflow type, id scheme, sweep interval)

lib/agenticrealms/world/
├── commands/remove_entity.ex           # NEW  %RemoveEntity{entity_id} → Entity
├── events/entity_removed.ex            # NEW  %EntityRemoved{entity_id, kind, from} (from = last container, for witness)
├── entity.ex                           # EDIT execute(RemoveEntity)→EntityRemoved (or {:error,:not_found}); apply marks removed; lifespan :stop on EntityRemoved
├── router.ex                           # EDIT dispatch [RemoveEntity] → Entity
├── commands.ex                         # EDIT remove_entity/1 (+ remove_npc/1 convenience) facade, consistency: :strong
├── queries.ex                          # EDIT add list_global_exits/1 (%{direction, target_room_id}, visible_to_user_id IS NULL); ensure get_npc_clone_row/1
├── projections/<entity_projector>.ex   # EDIT handle EntityRemoved → delete npc_clones (kind :npc) / world_objects (kind :object) row, idempotent
└── transient/purge.ex                  # EDIT terminate minds for the collected npc_ids (out-of-band TemporalClient call) — best-effort, does not block purge

lib/agenticrealms/world/ui_event_broadcaster.ex   # EDIT +witness_object_move(:npc,:relocated,from_room,to_room,id) → RoomNPCLeft+RoomNPCArrived; +witness EntityRemoved(:npc, from room) → RoomNPCLeft

lib/agenticrealms_web/
├── controllers/npc_service_controller.ex   # NEW identity/2, surroundings/2, move/2 (JSON; maps domain results → 200/404/409/422)
├── plugs/require_service_token.ex          # NEW bearer plug, Plug.Crypto.secure_compare vs :npc_service_secret, 401 + halt
├── router.ex                                # EDIT scope "/api" pipe_through [:api, RequireServiceToken] → the 3 routes
├── live/game_live.ex                        # EDIT handle_info(%RoomNPCLeft{}) → UIEvents.npc_left/2
└── live/game_live/ui_events.ex              # EDIT npc_left/2 (append departure log; no presence mutation — NPCs aren't in Presence)

config/config.exs        # EDIT compile-time defaults: temporal_base_url/namespace/task_queue, workflow_type, sweep interval
config/runtime.exs       # EDIT runtime env (non-test block): NPC_SERVICE_SECRET, TEMPORAL_* ; test env leaves secret unset/stub client
lib/agenticrealms/application.ex   # EDIT supervision tree: add NpcMinds.LifecycleManager (handler) and NpcMinds.Reconciler (Horde singleton) after the World handlers block

test/agenticrealms/npc_minds/            # NEW temporal_client_test (Req stub), lifecycle_manager_test, reconciler_test (pure diff)
test/agenticrealms/world/                 # NEW entity_remove_test (execute/apply), entity_removed_projector_test, queries_global_exits_test, purge_terminate_test
test/agenticrealms_web/                    # NEW require_service_token_test, npc_service_controller_test (identity/surroundings/move + 401/404/409/422)
```

**Structure Decision**: Single Phoenix app. New domain-adjacent logic lives in a cohesive `AgenticRealms.NpcMinds` context (lifecycle handler + Temporal client + reconciler), keeping the outward Temporal integration in one place. Write-side removal follows the established command/event/projector layering on the existing `Entity` aggregate (feature 016). The inbound service API is a conventional Phoenix `/api` scope guarded by a bearer plug. Cluster semantics: the handler is an exclusive Commanded subscriber; the reconciler is a Horde-registered cluster singleton.

## Complexity Tracking

| Deviation / Added machinery | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| **Reconciliation singleton** (a new cluster-wide GenServer that periodically diffs live NPCs ↔ running minds) | Spec clarification chose "best-effort handoff + reconcile"; SC-013 requires convergence to exactly one mind per live NPC after a Temporal outage. The event handler alone loses any start/terminate issued while Temporal is unreachable. | *Best-effort only* was offered and rejected by the user (would leave NPCs mindless after an outage). *Durable outbox* is heavier (persisted intents + retry machinery) than the idempotent list-and-diff sweep, which leans on Temporal's own USE_EXISTING/terminate-tolerance. |
| **"Process manager" implemented as `Commanded.Event.Handler`** (not a Commanded `ProcessManager`) | The lifecycle action is an external HTTP side effect, which handlers do idiomatically; a `ProcessManager` is for event→command routing and would need an artificial command. | A real `ProcessManager` would require inventing a command whose only effect is an external call — indirection with no benefit, and it still couldn't perform HTTP cleanly. |
| **New generic `RemoveEntity`/`EntityRemoved` on the `Entity` aggregate** | No removal event exists; the terminate trigger and read-model cleanup both require one; the event-sourcing mandate (Principle II) forbids ad-hoc row deletes outside a projector. | *Terminate only in the purge path* was rejected via clarification (needs a first-class removal). *Deleting the `npc_clones` row directly* (no event) violates Principle II and would desync the event store from the read model. |
