# Contract — Inbound HTTP: NPC Service API (game-exposed)

The three routes the game exposes to the external mind worker. This mirrors the
shared schema in `agentic-realms-npc` feature 001 (`contracts/http-contract.md` /
`openapi.yaml`) — that schema is authoritative; this file records the game-side
mapping. **The game must not drift from it.**

## Conventions

- Base: the game's `AGENTIC_REALMS_BASE_URL` (worker side), default
  `http://localhost:4000`.
- **Auth on every route**: `Authorization: Bearer <NPC_SERVICE_SECRET>`. Missing,
  malformed, or wrong → `401` with no read/write performed; the response does not
  distinguish missing vs. wrong (FR-027, FR-030, FR-033). Constant-time compare.
- JSON in/out; ids are strings; player ids stringified. Directions:
  `north south east west northeast northwest southeast southwest up down rift`.
- Implemented by `AgenticRealmsWeb.NpcServiceController`; guarded by
  `AgenticRealmsWeb.Plugs.RequireServiceToken` in the `/api` scope.

---

## 1. `GET /api/npc/:id/identity`

Pure read. `US4 / FR-005..008`.

**200**
```json
{ "entity_id": "…", "name": "Garrick the Innkeeper",
  "short_description": "a wiry innkeeper in a stained apron",
  "long_description": "…", "lore": "…" }
```
**404** entity is not an existing NPC. **401** bad/missing token.

Game mapping: `Repo.get(NPCClone, id)` → fields; `nil` → 404.

---

## 2. `GET /api/npc/:id/surroundings`

Pure read; safe every cycle; no world change. `US2 / FR-009..014`.

**200 (in a room)**
```json
{ "entity_id": "…", "room_id": "…",
  "exits": [ { "direction": "north", "to_room_id": "…" } ],
  "occupants": [
    { "id": "…", "kind": "npc",    "name": "Garrick the Innkeeper" },
    { "id": "42", "kind": "player", "name": "alothien" },
    { "id": "…", "kind": "object", "name": "a brass lantern" } ] }
```
**200 (void / removed)** — non-actionable, NOT an error:
```json
{ "entity_id": "…", "room_id": null, "exits": [], "occupants": [] }
```
**404** unknown entity. **401** bad/missing token.

Game mapping: `room_id = NPCClone.room_id` (nil → void). `exits =
Queries.list_global_exits(room_id)` → `{direction, to_room_id: target_room_id}`
(global only; owner-only transient exits excluded). `occupants` = merge of
`list_npcs_in_room` (npc), `list_objects_in_room` (object, all), room players
(player, username as name, id stringified), each tagged `kind`.

---

## 3. `POST /api/npc/:id/move`

Enacts a move via the existing command path (compare-and-swap). `US1 /
FR-015..021`.

**Request**
```json
{ "direction": "north", "expected_room_id": "…" }
```
**200 — applied**
```json
{ "result": "ok", "from_room_id": "…", "to_room_id": "…" }
```
**409 — conflict** (NPC no longer in `expected_room_id`): `{ "result": "conflict" }`
**422 — no such exit** (`direction` not a current **global** exit of
`expected_room_id`, or unsupported container): `{ "result": "no_such_exit" }`
**404** unknown entity. **401** bad/missing token.

Game mapping (controller `move/2`):
1. `exits = Queries.list_global_exits(expected_room_id)`; find `direction`. Absent
   → `422 no_such_exit`.
2. `to_room_id` = that exit's `target_room_id`.
3. `Commands.move_entity(id, ContainerRef.room(expected_room_id),
   ContainerRef.room(to_room_id), :relocated)` (dispatch `consistency: :strong`).
4. Map result: `:ok` → 200; `{:error, :container_conflict}` → 409;
   `{:error, :not_found}` → 404; `{:error, :unsupported_container}` → 422.

The `expected_from` guard makes the dispatch a compare-and-swap → **retry-safe
with no idempotency key** (a stale retry becomes `409`, never a double move). A
successful `:relocated` NPC move emits `EntityMoved{kind: :npc, cause: :relocated}`,
which the witness fan-out turns into `RoomNPCLeft`/`RoomNPCArrived` (FR-022).

---

## Error/response invariants

- No route performs a read or world change before the token is validated.
- `422` is used for both invalid-exit and unsupported-container so the wire stays
  `{result: "no_such_exit"}` per the shared schema.
- Reads never 5xx on a void/removed NPC — they return the empty snapshot.
