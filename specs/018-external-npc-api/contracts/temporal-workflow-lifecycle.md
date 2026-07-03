# Contract — Outbound: Temporal Workflow Lifecycle (game → Temporal server)

The game calls **Temporal's HTTP API** to start/terminate/list NPC-mind
workflows. **This is a call to the Temporal server, never to the
`agentic-realms-npc` worker.** Implemented by
`AgenticRealms.NpcMinds.TemporalClient` using `Req`.

## Agreed values (must match `agentic-realms-npc` feature 001)

| Value | Value |
|---|---|
| Workflow type | `NpcWorkflow` |
| Workflow id | `npc-<entity_id>` |
| Task queue | `npc-minds` |
| Input | `{ "entity_id": "<uuid>" }` |
| Conflict policy | `WORKFLOW_ID_CONFLICT_POLICY_USE_EXISTING` |

## Config (`:agenticrealms` app env)

`temporal_base_url` (`TEMPORAL_HTTP_URL`, default `http://localhost:7243`),
`temporal_namespace` (`TEMPORAL_NAMESPACE`, `default`), `temporal_task_queue`
(`NPC_TASK_QUEUE`, `npc-minds`), `temporal_api_key` (`TEMPORAL_API_KEY`, optional
→ `Authorization: Bearer` when set), `npc_workflow_type` (`NpcWorkflow`).

## 1. `start_workflow(entity_id)` — StartWorkflowExecution

```
POST {base}/api/v1/namespaces/{ns}/workflows/npc-{entity_id}
Content-Type: application/json
Authorization: Bearer {temporal_api_key}      # only when configured
```
```json
{
  "workflowType": { "name": "NpcWorkflow" },
  "taskQueue":    { "name": "npc-minds" },
  "input": [ { "metadata": { "encoding": "anNvbi9wbGFpbg==" },
               "data": "<base64( {\"entity_id\":\"<uuid>\"} )>" } ],
  "workflowIdConflictPolicy": "WORKFLOW_ID_CONFLICT_POLICY_USE_EXISTING",
  "requestId": "<uuid>"
}
```
- `metadata.encoding` is base64 of `json/plain`; `data` is base64 of the JSON
  input. Encoder lives in `TemporalClient` and is unit-tested against a fixture.
- **Idempotency is Temporal's**: `USE_EXISTING` returns the running execution
  instead of erroring on a duplicate id → exactly one mind per NPC (FR-025). The
  game does NOT pre-check existence.
- Returns `:ok` on 2xx (including the "already running" case); logs + `{:error,
  reason}` on failure — the caller (handler/reconciler) never blocks a world
  change on this.

## 2. `terminate_workflow(entity_id)` — TerminateWorkflowExecution

```
POST {base}/api/v1/namespaces/{ns}/workflows/npc-{entity_id}/terminate
```
```json
{ "reason": "npc removed", "identity": "agentic-realms" }
```
- **Tolerance is Temporal's**: terminating an absent/already-closed workflow
  returns a benign not-found that the client maps to `:ok` (FR-028). The game does
  NOT pre-check whether a mind is running.

## 3. `list_running_npc_ids()` — ListWorkflowExecutions (reconciler)

```
GET {base}/api/v1/namespaces/{ns}/workflows?query={visibility}
```
`visibility = WorkflowType = 'NpcWorkflow' AND ExecutionStatus = 'Running'`
(URL-encoded). Paginate via `nextPageToken` if present. Extract each
`executions[].execution.workflowId`, strip the `npc-` prefix → set of running NPC
ids. Used only by the reconciler's diff.

## Failure & retry posture

- Handler/purge calls are **best-effort**: a failed start/terminate logs and
  returns `{:error, _}`; it never blocks or rolls back the world change (FR-029).
- The **reconciler** is the convergence backstop (FR-029a, SC-013): its next
  sweep re-issues any start/terminate missed during an outage. All three calls are
  safe to repeat (USE_EXISTING / tolerant terminate / read-only list).
- Transport security to Temporal is the deployment's responsibility.
