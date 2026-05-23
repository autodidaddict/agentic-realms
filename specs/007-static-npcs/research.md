# Phase 0 Research: Static NPCs

Five design questions worth resolving before tasks are generated. The spec is clarified — there are no `NEEDS CLARIFICATION` markers in Technical Context. Research instead surfaces the implementation-level decisions that drive the contract docs in Phase 1.

## R1. Aggregate ownership: extend `Room` vs. introduce a per-NPC aggregate

**Decision**: Extend the existing `Room` aggregate. `SpawnNPC` is routed to `Room` (just like `PlaceObject`); the aggregate tracks `npc_ids` and `npc_names_lower` as additional MapSet state slices alongside the existing `object_ids`.

**Rationale**:
- NPCs in this feature have no behavior to serialize. They cannot move, speak, act, or take damage (FR-017 / FR-018 / FR-019). The only invariants that need a serialization point are (a) npc_id uniqueness and (b) per-room display name uniqueness (FR-001a) — both of which are room-scoped.
- The `Room` aggregate is the natural home for "what is currently in this room" — it already owns the same question for objects. Adding NPCs is structurally identical to adding objects.
- Per-NPC aggregates would introduce N extra aggregate processes for what amounts to inert data. They would also force a two-aggregate handshake to enforce per-room name uniqueness (NPC aggregate publishes its name, Room aggregate validates the constraint, NPC aggregate commits) — wildly out of proportion to the feature's needs.

**Alternatives considered**:
- **Per-NPC `NPC` aggregate**: Rejected. No behavior to serialize. The future extensibility argument doesn't justify the cost now — when a later feature gives NPCs state machines, the existing `NPCSpawnedInRoom` event carries the `npc_id` and we can extract a new aggregate then (event store is forward-compatible: new aggregates may subscribe to historical event streams via their identity prefix).
- **No aggregate — pure projector-driven seed**: Rejected. We would lose the strong consistency guarantee for per-room name uniqueness (FR-001a). The DB unique index would still catch duplicates, but the dispatch path would return a confusing `Ecto.ConstraintError` instead of a clean `{:error, :npc_name_taken_in_room}`. The aggregate is also where future-feature command paths (despawn, move) would need to live anyway.

## R2. Uniqueness enforcement layering for per-room NPC names (FR-001a)

**Decision**: Defense in depth — enforce per-room name uniqueness at THREE layers.

1. **Aggregate state** (`Room.npc_names_lower :: MapSet`): the `SpawnNPC` command handler returns `{:error, :npc_name_taken_in_room}` when the lowercased name is already present in the aggregate's MapSet. This is the authoritative in-flight check.
2. **Database unique index** (`world_npcs(room_id, LOWER(name))`): a partial unique index on the read-model table. Catches any divergence between aggregate state and projection (e.g., a manual seed bypass, a future replay anomaly).
3. **Seed-time validation**: the `Seed.run/0` function dispatches `SpawnNPC` commands; any aggregate error aborts the seed with a clear Logger error. No special validation code — the aggregate's refusal IS the validation.

**Rationale**: Three independent defenses, each cheap. The aggregate check is the contract; the DB index is the safety net; the seed treats aggregate errors as fatal. Any single-layer bug cannot let two NPCs named "Garrick" co-exist in one room.

**Alternatives considered**:
- **DB-only enforcement**: Rejected. The aggregate would have to surface a generic `Ecto.ConstraintError` to the dispatcher — bad refusal ergonomics, no clean error atom for tests to match on.
- **Aggregate-only enforcement**: Rejected. A bug in the projector (or a manual SQL insert during diagnostic work) could create duplicates without the aggregate ever seeing them.

## R3. Take refusal: reuse `:object_is_fixed` vs. introduce a new error atom

**Decision**: Reuse the existing `:object_is_fixed` error atom.

**Rationale**:
- FR-015 explicitly demands "the exact same code path and produce the same shape of refusal entry as the existing fixed-object refusal." Reusing the atom is the most literal interpretation.
- The LiveView already maps `{:error, :object_is_fixed}` to `"You can't take that."` (`game_live.ex:458-460`). That message is exactly right for NPCs — generic, not surprising, and uniform with how the world refuses takes against fixed objects today.
- A new atom (`:npc_not_takeable`) would require a new LiveView clause, a new copy decision, and a new test surface. All for the same user-facing string. Pure overhead.

**Implementation surface**: `World.Commands.take/2` extended:

```elixir
def take(player_id, name) do
  with {:ok, room_id} <- Queries.current_room_of(player_id) do
    case Queries.resolve_object_in_room(room_id, name) do
      {:ok, object_id} ->
        with {:ok, false} <- check_not_fixed(object_id),
             # ... existing happy path ...
      {:error, :no_such_object} ->
        # NEW: fall through to NPC scope.
        case Queries.resolve_npc_in_room(room_id, name) do
          {:ok, _npc_id} -> {:error, :object_is_fixed}
          {:error, :no_such_object} -> {:error, :no_such_object}
          {:error, :ambiguous} -> {:error, :ambiguous}
        end
      other -> other
    end
  end
end
```

**Alternatives considered**:
- **`:npc_not_takeable` new atom**: Rejected. New surface, no semantic gain.
- **Have the LLM resolver refuse `take` for NPC targets pre-dispatch**: Rejected. The fast parser also has to refuse, which means duplicating the NPC scope check in two places. Centralizing in `Commands.take/2` is the single source of truth.

## R4. Seed-time placement: which room gets the starter NPC?

**Decision**: Garrick the Innkeeper goes into the **Stone Atrium** (`@starting_room_id`).

**Rationale**:
- FR-004 / Story 1 acceptance scenario 4 require at least one room in the starter map to contain at least one NPC. The Stone Atrium is the designated starting room, so every new player sees Garrick on first login without needing to move — maximum discoverability for the feature's headline payoff.
- The Stone Atrium currently contains a brass lantern (takeable). Adding an NPC means a fresh login renders three sections in the room view: objects (the lantern), other players (typically empty on first login), and "Also here" (Garrick). All three sections of the FR-004 contract are exercised by the starter room out of the box.

**Garrick's long description**: deliberately not load-bearing — chosen for atmosphere consistent with the existing Stone Atrium description (mossy granite, cool air). A representative draft:

> A wiry man in a stained apron, his hands callused and his eyes patient. He polishes a tankard that already looks clean and watches the door without quite seeming to.

**Alternatives considered**:
- **Library or Corridor**: Both rooms are reachable from the Atrium but require a movement command. Defeats the "demonstrable on first login" goal of SC-001 / FR-004 acceptance scenario 4.
- **Multiple NPCs in different rooms**: Out of scope for this feature's seed. The spec requires "at least one"; adding more is content authoring that can happen in a follow-up seed update.

## R5. Per-request context-snapshot format change for the LLM resolver

**Decision**: Add one new line `NPCs here: <names>` to `ContextSnapshot.render/3`, positioned between the existing `Objects here:` line and `Other players present:` line.

**Rationale**:
- The resolver already gets a per-request snapshot of "what is in scope" via `ContextSnapshot.render/3`. NPCs are now a third entity type in scope; the model needs to know about them to resolve natural-language phrasings like "the old man" against the actual visible Garrick.
- The snapshot is volatile (rebuilt per request); the system prompt + tool definitions are cached. So the format change costs nothing in terms of cache invalidation — it only changes the volatile per-request user message.
- The existing snapshot already uses `(none)` for empty sections; following the same convention keeps the rendering uniform across the three categories.

**Cache impact**: The system prompt gains one short paragraph (~50 tokens) noting that NPCs are valid examination targets. This invalidates the 5-minute ephemeral prompt cache on first deploy. Same posture as feature 005's prompt changes and feature 006's tool-schema change — one uncached request after deploy, then back to normal.

**Alternatives considered**:
- **No snapshot change, only system prompt edit**: Rejected. The model needs concrete in-scope target names to resolve descriptive paraphrases ("the innkeeper" → Garrick). Without listing them explicitly in the snapshot, the model would have to guess, and the resolver path would degrade for any descriptive phrasing.
- **Merge NPCs into `Other players present:`**: Rejected. The whole point of the entity separation is that NPCs and players are distinct kinds of targets — merging them would muddle the model's classifier and would also conflict with FR-008's cross-type collision rule (the model needs to know which target type it's selecting to flag a mixed-kind tie).
