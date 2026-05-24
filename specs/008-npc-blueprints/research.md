# Phase 0 Research: NPC Blueprints

Five design questions resolved before tasks generation. The spec is clarified (no `NEEDS CLARIFICATION` markers in Technical Context); these are implementation-level decisions that drive Phase 1's contracts.

## R1. Aggregate ownership: new `NPCBlueprint` aggregate vs. extending `Room`

**Decision**: New `World.NPCBlueprint` aggregate, identified by `:blueprint_id` with prefix `"npc-blueprint-"`. Two commands route to it: `CreateNPCBlueprint`, `SpawnNPCClone`. The aggregate owns the per-blueprint serial counter and the `MapSet` of issued `clone_ids`.

**Rationale**:
- The blueprint has its own invariants — id uniqueness, serial monotonicity, no-duplicate-clone-id — that need a serialization point. The natural Commanded boundary is one aggregate per blueprint.
- Extending the `Room` aggregate (where feature 007 placed NPC commands) would conflate two different concerns: "what's in this room" vs. "what is this kind of NPC and how many have I made." It would also produce hot aggregates: a popular Stone Atrium with many NPC events would slow down every command targeting that room.
- A per-blueprint aggregate is what Commanded is good at — small, focused, with a clear identity boundary. The aggregate instance for `"npc-blueprint-garrick_the_innkeeper"` is independent of the Room aggregate for the Stone Atrium.

**Alternatives considered**:
- **Extend `Room`**: rejected. Coupling per-blueprint state (serial counter) to per-room state would either require duplicating serial counters across rooms (incorrect — serial is per-blueprint, not per-room) or pushing the serial counter to a third coordinator. Worse, every command targeting a room would touch NPC blueprint state irrelevant to that command.
- **DB sequence per blueprint**: rejected. PostgreSQL sequences are awkward to create dynamically per blueprint and don't play well with event-sourcing replay (the sequence's value is read-model state, not derivable from events). Aggregate-owned counter is replay-deterministic.
- **Global event-store-derived serial** (just count `NPCClonedFromBlueprint` events with this `blueprint_id`): rejected. Functionally similar to the aggregate-owned counter but requires the projector to compute it, adding a roundtrip per spawn and risking off-by-one bugs if events arrive out of order. The aggregate handles ordering for free.

## R2. Per-room display name uniqueness: aggregate state vs. read-model layer

**Decision**: Move enforcement to two layers — (a) a DB unique index `npc_clones(room_id, LOWER(name))` and (b) a pre-dispatch read-model check in `World.Commands.spawn_npc_clone/3`. The aggregate no longer tracks `npc_names_lower` (it tracks only `clone_ids` for blueprint-level identity uniqueness).

**Rationale**:
- Spawning a clone of a blueprint into a room is now a command against the `NPCBlueprint` aggregate. The blueprint aggregate doesn't know what's in any room — that's the Room aggregate's concern. Adding a separate aggregate just to enforce per-room uniqueness would be over-engineering for this scope.
- DB-level enforcement via a unique index is bullet-proof and matches the project's posture (feature 003's `world_objects.exactly_one_location` check constraint follows the same pattern). Pre-dispatch check gives clean error atoms (`{:error, :clone_name_taken_in_room}`) before any event hits the store.
- Race window analysis: two concurrent `spawn_npc_clone` calls into the same room, same blueprint, could both pass the pre-dispatch check. The first projects successfully; the second's projector insert raises a unique-constraint error. For seed-only spawning (feature 008's scope per FR-018), this race is essentially impossible. For runtime spawning (future feature), the projector's constraint violation surface is documented and acceptable.

**Alternatives considered**:
- **Aggregate state in `NPCBlueprint`**: rejected. The blueprint aggregate doesn't know about rooms; pushing per-room state into it would conflate concerns.
- **Two-aggregate dispatch (NPCBlueprint + Room)**: rejected. Distributed transaction across two aggregates is heavyweight for one invariant. Process managers / sagas exist for this but the engineering surface is much larger than the problem warrants.
- **Pre-dispatch only**: rejected without DB-level safety net. The pre-dispatch check is best-effort; the DB unique index is the contract.

## R3. Synthetic blueprint identity for legacy event replay (FR-019 / FR-020 / FR-021)

**Decision**: Synthetic blueprint id = UUID5 derived from a fixed namespace + the `(name, short_description, long_description)` tuple. Same tuple → same id (deterministic, idempotent). Stored as a string column in `npc_blueprints` with `is_synthetic: true`.

**Rationale**:
- FR-020 requires idempotent replay. A random UUID per legacy event would create N synthetic blueprints for N replays of the same event. UUID5 of the payload tuple guarantees the SAME synthetic blueprint id is computed every time.
- The namespace UUID is hardcoded in the projector module (something like `UUID.uuid5(:nil, "agenticrealms:legacy-npc-spawn")` for the namespace constant, then `UUID.uuid5(namespace, "#{name}|#{short}|#{long}")` for the per-event id). Hardcoding the namespace means the migration is reproducible across machines.
- The `is_synthetic` boolean exists so the future wizard tab can identify these blueprints and offer a migration affordance: "promote this synthetic blueprint to an authored one" (giving it a proper slug). This is forward-compatibility for the wizard tab, not a current feature surface.
- Two distinct legacy events with the SAME `(name, short, long)` tuple correctly share a synthetic blueprint. Their clones are different rows (different `clone_id`, different `serial`), but they descend from the same blueprint lineage. This matches the "same kind of NPC" semantic the user described in the design conversation.

**Alternatives considered**:
- **Random UUID per event**: rejected. Breaks FR-020 idempotency.
- **UUID5 of `npc_id` alone** (the legacy event's NPC id): each legacy NPC gets its own synthetic blueprint. Rejected: it means re-spawning Garrick three times in feature 007 produces three distinct blueprints, which is semantically wrong (they're the same kind of NPC).
- **String slug derived from name**: e.g., `"_synthetic_garrick_the_innkeeper"`. Rejected: name collisions across events with different descriptions would conflate distinct blueprints into one.

## R4. Subscription reset mechanism for wipe-and-replay migration (FR-021a)

**Decision**: The Ecto migration includes a SQL `DELETE` against the Commanded `subscriptions` table for the `WorldProjector` row, after creating the new schema tables. On next application startup, the projector subscribes from position 0 and replays the entire event store.

**Rationale**:
- The Commanded `subscriptions` table tracks each handler's position in the event stream. Deleting the row resets the position to "beginning" — the next start-up causes a full replay.
- Doing this inside the Ecto migration ensures it happens atomically with the schema change. No separate operational step required.
- Existing read-model handlers (rooms, exits, objects, player_state) are all `on_conflict: :nothing` and tolerate re-projection of events they've already processed — the cost is a few redundant upserts during application startup, taking maybe 50ms on the small starter map.
- An alternative — using Commanded's `Commanded.EventStore.reset!/0` or similar runtime API — is a release-command concern, not a migration concern. Tying it to the migration is simpler for the dev workflow (`mix ecto.migrate` does the right thing on its own).

**Alternatives considered**:
- **Runtime `WorldProjector.reset()` on first deploy**: rejected. Requires an operational step beyond `mix ecto.migrate`; easy to forget; race-prone if the projector starts before the reset runs.
- **No reset; just project from current position**: rejected. The new `npc_clones` table would be empty for existing worlds, breaking SC-002.
- **Two separate projectors (one for new events, one for legacy)**: rejected. Adds complexity to the handler topology; doesn't avoid the subscription reset.

## R5. `name#serial` debug rendering helper

**Decision**: Single helper `Schemas.NPCClone.debug_id/1` returning `"#{clone.name}##{clone.serial}"`. Used in `Examine.emit_telemetry/2` (a new `clone_debug_id` event field), and available to any future admin tool. Player-facing render paths (room view, examination, take refusal, arrival broadcast) use `clone.name` directly with no `#serial` suffix.

**Rationale**:
- A single helper keeps the rendering consistent and grep-able. If a future change to the LPMud-style format is needed (e.g., adding a backslash escape for names containing `#`), it lands in one place.
- Telemetry is the natural first consumer: when an NPC is examined, the existing `[:agenticrealms, :examine, :resolve]` telemetry event grows a `clone_debug_id` field. Admins watching telemetry see `"Garrick the Innkeeper#1"` and can immediately distinguish clones.
- Player-facing surfaces never call `debug_id/1`. FR-011's "MUST NOT appear in any player-facing surface" is enforced architecturally: GameLive, GameComponents, and the LiveView template have zero references to `debug_id/1`. A test asserts that the rendered HTML for the room view does NOT contain a `#` character preceded by an NPC name.

**Alternatives considered**:
- **Inline string interpolation at each call site**: rejected. Easy for drift to creep in (one site uses `<name>#<serial>`, another uses `<name> (clone #<serial>)`).
- **A field on the schema** (e.g., `npc_clones.debug_id` precomputed at insert): rejected. Adds storage cost and stale-cache risk if the format ever changes. A function over read-fresh fields is simpler.
- **Expose `#serial` to players in any context**: rejected by FR-011.
