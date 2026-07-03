# Quickstart — External NPC Brains (Game-Side)

Verify the game side end-to-end: the contract routes (auth + identity +
surroundings + move), the lifecycle handoff (start on spawn, terminate on
removal), and the reconciliation backstop. The `agentic-realms-npc` worker is
optional here — you can exercise the game side with `curl` + IEx alone.

## Prereqs

- Postgres running; event-store + read-model DBs migrated (`mix ecto.setup`).
- A Temporal server with its **HTTP API** enabled, e.g.:
  ```sh
  temporal server start-dev --http-port 7243
  ```
- Env for the game:
  ```sh
  export NPC_SERVICE_SECRET=devsecret
  export TEMPORAL_HTTP_URL=http://localhost:7243
  export TEMPORAL_NAMESPACE=default
  export NPC_TASK_QUEUE=npc-minds
  # export TEMPORAL_API_KEY=...   # only for Temporal Cloud
  ```
- Start the game: `mix phx.server` (base `http://localhost:4000`).

## 1. Auth gate (US3)

```sh
# no token → 401
curl -si localhost:4000/api/npc/SOME_ID/identity | head -1        # HTTP/1.1 401
# wrong token → 401
curl -si -H 'Authorization: Bearer nope' localhost:4000/api/npc/SOME_ID/identity | head -1
# correct token → proceeds (404 if id unknown)
curl -si -H 'Authorization: Bearer devsecret' localhost:4000/api/npc/SOME_ID/identity | head -1
```

## 2. Pick a live NPC + read identity/surroundings (US4/US2)

```sh
# In IEx (iex -S mix phx.server), grab a spawned NPC id + its room:
#   AgenticRealms.World.Queries.list_npcs_in_room(<room_id>)
export NPC=<npc-entity-id>
export TOK='Authorization: Bearer devsecret'

curl -s -H "$TOK" localhost:4000/api/npc/$NPC/identity | jq
# → { entity_id, name, short_description, long_description, lore }

curl -s -H "$TOK" localhost:4000/api/npc/$NPC/surroundings | jq
# → { entity_id, room_id, exits:[{direction,to_room_id}], occupants:[{id,kind,name}] }
```

## 3. Move the NPC + witness it (US1)

Open the game in a browser and stand a player in the NPC's room.

```sh
# use a direction + room_id from the surroundings response
curl -s -H "$TOK" -H 'Content-Type: application/json' \
  -d '{"direction":"north","expected_room_id":"'"$ROOM"'"}' \
  localhost:4000/api/npc/$NPC/move | jq
# → { "result":"ok", "from_room_id":"…", "to_room_id":"…" }
```
Expect: the watching player sees **"<name> leaves."** / arrival in the
destination room — identical to any NPC move.

Negative checks:
```sh
# stale origin → 409 conflict (move again with the OLD expected_room_id)
curl -s -o /dev/null -w '%{http_code}\n' -H "$TOK" -H 'Content-Type: application/json' \
  -d '{"direction":"north","expected_room_id":"'"$ROOM"'"}' localhost:4000/api/npc/$NPC/move   # 409
# bad direction → 422 no_such_exit
curl -s -H "$TOK" -H 'Content-Type: application/json' \
  -d '{"direction":"west","expected_room_id":"'"$NEWROOM"'"}' localhost:4000/api/npc/$NPC/move | jq
```

## 4. Lifecycle: start on spawn, terminate on removal (US4/US5)

```elixir
# IEx — spawn an NPC via the existing flow, then confirm a mind started:
AgenticRealms.World.Commands.spawn_npc_clone(blueprint_id, room_id, name)
# → LifecycleManager reacts to EntityCloned{kind: :npc} and starts workflow npc-<id>
#   Confirm in Temporal Web UI (localhost:8233) that npc-<id> is Running.

# Remove it → mind terminates:
AgenticRealms.World.Commands.remove_npc(npc_id)
# → EntityRemoved{kind: :npc}; players in the room see "<name> leaves.";
#   npc_clones row is deleted; workflow npc-<id> is Terminated.
```

Idempotency: re-running `spawn`/handoff for the same id starts **no** second mind
(Temporal `USE_EXISTING`); `remove_npc/1` on an already-removed id → `{:error,
:not_found}` and terminating an absent mind is a no-op.

## 5. Reconciliation backstop (SC-013)

```
1. Stop the Temporal server.
2. Spawn an NPC (handoff fails, best-effort — the NPC spawns fine, no player error).
3. Restart the Temporal server.
4. Within one reconcile interval (default 60s), the reconciler starts the missing
   npc-<id> workflow. Kill a workflow whose NPC you then remove → the next sweep
   terminates the orphan. Converges to exactly one mind per live NPC.
```

## 6. Automated checks

```sh
mix test test/agenticrealms/npc_minds test/agenticrealms_web/npc_service_controller_test.exs \
         test/agenticrealms/world/entity_remove_test.exs
mix precommit     # warnings-as-errors + format + full suite (the merge gate)
```
