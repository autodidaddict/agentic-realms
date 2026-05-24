# Implementation Plan: NPC Blueprints (Prelude — Blueprint/Clone Split)

**Branch**: `008-npc-blueprints` | **Date**: 2026-05-23 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/008-npc-blueprints/spec.md`

## Summary

Refactor feature 007's NPC entity into a blueprint/clone split. Introduce `NPCBlueprint` as a new Commanded aggregate that owns per-blueprint state — name, descriptions, and a monotonic serial counter — and emits `NPCClonedFromBlueprint` events whose payload carries a fully-realized snapshot of the blueprint's data (full-copy semantics, per the 2026-05-23 clarifications). The persisted read model splits into two tables: `npc_blueprints` (authored templates, no location) and `npc_clones` (the in-world clones, denormalized blueprint data + `blueprint_id` + `serial`). The starter map's Garrick the Innkeeper becomes a `Garrick the Innkeeper` blueprint with one clone (`#1`) in the Stone Atrium. Feature 007's entire player-facing surface — room view "Also here:" section, examine, take refusal, arrival broadcasts — keeps working unchanged.

**Load-bearing design decisions**:

- **Blueprint is a Commanded aggregate, not just a Schema row.** It needs to serialize the per-blueprint `next_serial` counter (FR-009) and enforce blueprint-existence checks atomically with clone spawning. The aggregate is identified by `:blueprint_id` (prefix `"npc-blueprint-"`); its state holds `name`, `short_description`, `long_description`, `next_serial`, and a `MapSet` of issued `clone_ids` for duplicate-id refusal. Sparing engineering: blueprints have only two commands (`CreateNPCBlueprint`, `SpawnNPCClone`) and two events (`NPCBlueprintCreated`, `NPCClonedFromBlueprint`). No update, no delete in this feature (FR-005a, FR-016).
- **Full-copy materialization lives in the aggregate's `execute/2`.** When `SpawnNPCClone` arrives at the blueprint aggregate, the aggregate's *current* `name`, `short_description`, and `long_description` are stamped into the emitted `NPCClonedFromBlueprint` event. The clone's data is captured at the exact aggregate-state moment of cloning — this is the persistence-layer guarantee behind Story 3 / FR-007 / FR-012. The projector inserts the clone row using only the event's denormalized fields; the `npc_clones.blueprint_id` FK is purely lineage, never consulted at render time (FR-007 amplified).
- **Per-room display name uniqueness moves to the read-model layer.** Feature 007 enforced FR-001a via `Room` aggregate state (`npc_names_lower` MapSet). Now that NPC events flow through a different aggregate (`NPCBlueprint`), enforcement moves to two layers: (a) a unique DB index `npc_clones(room_id, LOWER(name))` (defense-in-depth, projector-side), and (b) a pre-dispatch read-model check in `World.Commands.spawn_npc_clone/3` (clean refusal before any event is emitted). This is the **only** structural change to FR-015's enforcement — the contract itself is unchanged.
- **The `Room` aggregate keeps its `NPCSpawnedInRoom` `apply/2` clause as a vestigial no-op.** Commanded aggregates rehydrate by replaying their full event stream. Feature 007's `NPCSpawnedInRoom` events were emitted by the Room aggregate (routed via `room-<id>`), so they remain in that stream. To avoid crashing the Room aggregate's rehydration, the apply clause stays — but it reduces to `def apply(%__MODULE__{} = state, %NPCSpawnedInRoom{}), do: state`. The Room aggregate stops tracking `npc_ids` and `npc_names_lower` (removed from `defstruct`), because no current command consults that state. Feature 007's `Commands.SpawnNPC` struct, the router dispatch entry, and the Room's `execute/2` clauses for `SpawnNPC` are all removed.
- **Wipe-and-replay migration per FR-021a / Q2 clarification.** The Ecto migration drops `world_npcs`, creates `npc_blueprints` + `npc_clones`, and resets the `WorldProjector` subscription so the projector replays the entire event store from position 0 on the next application startup. Existing read-model handlers (rooms, exits, objects, player_state) are already idempotent via `on_conflict: :nothing`, so re-projection is a no-op for them. NPC events project into the new tables via the synthetic-blueprint path (see next bullet). Operational cost: a brief window during application startup where the projector is catching up; functionally identical to a normal cold start.
- **Synthetic blueprints for legacy event replay (FR-019 / FR-020 / FR-021).** The `WorldProjector` keeps its handler for `NPCSpawnedInRoom` (feature 007's event). When the handler fires during replay, it derives a **deterministic synthetic blueprint id** from a UUID5 namespace + the `(name, short_description, long_description)` tuple, upserts a row into `npc_blueprints` with `is_synthetic: true`, and then inserts the clone row using the event's denormalized payload. The same handler is hit for both fresh seed-event replay AND for any historical events from feature-007 IEx-dispatched spawns. Idempotency comes from `on_conflict: :nothing` on the blueprint insert; the deterministic id guarantees the same payload always projects to the same blueprint row.
- **Serial assignment for legacy events**: the synthetic-blueprint path needs to assign a serial. The projector queries the current max serial for the synthetic blueprint (`SELECT COALESCE(MAX(serial), 0) + 1 FROM npc_clones WHERE blueprint_id = ?`) and inserts at that value. Because the projector is single-threaded (Commanded event-handler ordering), this read-then-write is safe. The clone row's `(blueprint_id, serial)` unique constraint catches any edge case as a projector failure (acceptable — historical events with mid-replay race conditions are a non-issue for our small worlds).
- **Player-facing surface is identical to feature 007.** `Queries.list_npcs_in_room/1` and `Queries.resolve_npc_in_room/2` continue to return the same projection shape (`%{id, name, short_description}`) — they just query `npc_clones` instead of `world_npcs`. `World.Examine`'s `long_description_of_npc/1` looks up `Schemas.NPCClone` instead of `Schemas.NPC` (the schema module is renamed). The `RoomView.npcs` field and the "Also here:" rendering are untouched. `Commands.take/2`'s NPC fall-through continues to use `resolve_npc_in_room/2` and continues to return `{:error, :object_is_fixed}` — same code path, different underlying table.
- **The `Schemas.NPC` module rename**. The file at `lib/agenticrealms/world/schemas/npc.ex` is renamed to `npc_clone.ex` with module `World.Schemas.NPCClone`. Every internal reference (Examine, Queries, the integration test) updates. This is a sed-and-confirm refactor; not load-bearing intellectually but worth flagging because it touches many files.
- **No new player-visible surfaces ship.** No new commands, no new log entries, no new HUD widgets, no new tool definitions in the LLM resolver, no system prompt changes. Per FR-025 this is enforced architecturally — there's nothing in the feature to expose.

**Per-spec design**:

- **Blueprint identifier scheme**: human-readable slug stored as a string (`"garrick_the_innkeeper"`). Not a UUID. The slug is stable across re-seeds, makes seed code self-documenting, and survives event-store replay deterministically. Clone IDs remain `binary_id` (UUID), matching the rest of the persisted world.
- **`name#serial` debug rendering** (FR-011): produced by a single helper `Schemas.NPCClone.debug_id/1` that returns `"#{clone.name}##{clone.serial}"`. Used in telemetry events (`Examine.emit_telemetry/2` gets a `clone_debug_id` field) and any future admin tool. The room renderer, examination renderer, and arrival broadcast all use the bare `clone.name` — never `debug_id/1`.
- **Seed flow**: `Seed.do_seed/0` dispatches one `CreateNPCBlueprint{blueprint_id: "garrick_the_innkeeper", name: ..., short: ..., long: ...}` then one `SpawnNPCClone{blueprint_id: "garrick_the_innkeeper", clone_id: @innkeeper_garrick_clone_id, room_id: @starting_room_id}` (the existing `@innkeeper_garrick_id` from feature 007 is renamed/repurposed as the clone id for continuity).

## Technical Context

**Language/Version**: Elixir 1.15+ / Erlang OTP 26+ (unchanged from 003–007)
**Primary Dependencies**: Existing only — Phoenix 1.8.5, Phoenix LiveView 1.1.0, `commanded`, `commanded_eventstore_adapter`, `phoenix_pubsub`, `jason`, `ecto`, `req`. No new runtime deps.
**External Service**: None new. The LLM resolver's tool definitions and system prompt are unchanged (no surface for blueprint-aware authoring in this feature — that's the wizard tab).
**Storage**: PostgreSQL via existing `world_rooms`/`world_exits`/`world_objects`/`player_states`/`account_players` tables (unchanged) plus a new `npc_blueprints` table and a renamed-and-restructured `npc_clones` table (replacing feature 007's `world_npcs`). One new migration that drops `world_npcs`, creates the two new tables, and resets the projector subscription.
**Testing**: ExUnit. Six layers — (1) `NPCBlueprint` aggregate unit tests for `CreateNPCBlueprint` and `SpawnNPCClone` (happy paths + duplicate clone_id refusal + spawn-against-uninitialized-blueprint refusal), (2) `WorldProjector` legacy-event replay tests for `NPCSpawnedInRoom` → synthetic blueprint + clone, (3) `Queries` unit tests for `list_npcs_in_room/1` + `resolve_npc_in_room/2` against the new clone table, (4) full-copy semantics test — DB-level mutation of a blueprint row after spawning, verify clone row unchanged (Story 3 / SC-003), (5) every feature 007 integration test still passes against the refactored schema (Story 1 / SC-001), (6) a new wipe-and-replay test — populate world, drop tables, replay event store, verify world is reconstructed correctly (Story 5 / SC-005).
**Target Platform**: Web browser (desktop, unchanged).
**Project Type**: Phoenix LiveView monolith (unchanged).

**Performance Goals**:
- Clone spawn latency: under 50ms p99 for fresh seed (Commanded aggregate dispatch + projector insert). Same posture as existing `SpawnNPC` from feature 007.
- Read-model query latency: `list_npcs_in_room/1` continues to meet feature 006/007's targets. The query shape is identical — only the table name changes.
- Replay throughput: a freshly-reset world (3 rooms, 3 objects, 1 NPC) replays in under 1 second on a developer laptop. Cold starts after the migration are imperceptible.

**Constraints**:
- The Commanded subscription reset MUST be coordinated with the migration. Two options: (a) the Ecto migration TRUNCATEs the `subscriptions` table for the `WorldProjector` row, or (b) a one-shot release command runs `WorldProjector.reset()` on first deploy. (a) is simpler for the dev workflow and is what the plan adopts.
- `:strong` consistency on the projector handler is preserved — historical (legacy) and new events both project synchronously so seeds and tests don't race.
- No new domain event types beyond `NPCBlueprintCreated` and `NPCClonedFromBlueprint`. Feature 007's `NPCSpawnedInRoom` remains in the event store untouched (event-source purity).
- The 500-character input cap continues to apply to any value that comes from external input (blueprint name, descriptions). For now, all blueprints are seed-authored so this is a soft constraint.

**Scale/Scope**:
- Same as 003–007 — small world, single NPC blueprint in the starter map, single clone.
- New code: one aggregate, two command structs, two event structs, two Ecto schemas, one migration, one projector handler clause per new event, one synthetic-blueprint generator, refactored seed, deletion of feature 007's `SpawnNPC` command + Room `execute/2` clauses.
- Deletion of code: feature 007's `Commands.SpawnNPC` struct (1 file deleted), Room aggregate's NPC `execute/2` clauses (no file deletion, function clauses removed), Room aggregate's `npc_ids`/`npc_names_lower` `defstruct` fields.
- ~600–700 LOC of production code touched + ~400 LOC of tests. Net code count is roughly flat (additions balanced by deletions).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The project constitution (`.specify/memory/constitution.md`) is the unfilled template — no concrete principles ratified. No gates to enforce. Proceeding (same posture as 003 / 004 / 005 / 006 / 007).

**Post-Phase 1 re-check**: No violations. The feature introduces one new aggregate (`World.NPCBlueprint`), one new schema (`Schemas.NPCBlueprint`), one renamed schema (`Schemas.NPCClone` ← was `Schemas.NPC`), two new commands, two new events, one new migration, and narrow extensions to existing modules (Router, WorldProjector, Queries, Examine, Seed, Commands.take/2 — unchanged because it consults Queries by interface, UIEventBroadcaster, GameLive — unchanged because it consumes UI events by struct shape). No new external services, no new PubSub topics, no new supervisors. The refactor preserves every player-facing contract from feature 007.

## Project Structure

### Documentation (this feature)

```text
specs/008-npc-blueprints/
├── plan.md                  # This file (/speckit-plan output)
├── spec.md                  # Feature specification (clarified 2026-05-23)
├── research.md              # Phase 0: aggregate ownership choice, per-room
│                            #          uniqueness placement, synthetic
│                            #          blueprint id derivation, wipe-and-replay
│                            #          subscription reset mechanism, name#serial
│                            #          debug rendering surface
├── data-model.md            # Phase 1: npc_blueprints schema, npc_clones
│                            #          schema, NPCBlueprint aggregate state,
│                            #          full-copy materialization rule, invariants
├── quickstart.md            # Phase 1: how to verify each user story end-to-end
│                            #          (including SC-005 replay round-trip)
├── contracts/
│   ├── commands.md          # Phase 1: CreateNPCBlueprint + SpawnNPCClone
│   │                        #          command shapes + aggregate handlers
│   ├── events.md            # Phase 1: NPCBlueprintCreated + NPCClonedFromBlueprint
│   │                        #          domain events + legacy NPCSpawnedInRoom
│   │                        #          forward-compatibility path
│   ├── projector.md         # Phase 1: WorldProjector handler clauses for the
│   │                        #          new events + the legacy-event synthetic-
│   │                        #          blueprint path
│   ├── queries.md           # Phase 1: list_npcs_in_room/1 + resolve_npc_in_room/2
│   │                        #          updated to target npc_clones; no
│   │                        #          interface change
│   └── migration.md         # Phase 1: wipe-and-replay migration steps,
│                            #          subscription reset, idempotency
└── checklists/
    └── requirements.md      # (Already created by /speckit-specify)
```

### Source Code (repository root)

```text
lib/
├── agenticrealms/
│   └── world/
│       ├── npc_blueprint.ex                        # NEW — Commanded aggregate.
│       │                                                  Identified by
│       │                                                  :blueprint_id with
│       │                                                  prefix "npc-blueprint-".
│       │                                                  State: id, name,
│       │                                                  short, long,
│       │                                                  next_serial,
│       │                                                  clone_ids MapSet.
│       │                                                  Two commands, two
│       │                                                  events, ~80 LOC.
│       ├── commands/
│       │   ├── spawn_npc.ex                        # DELETED — feature 007
│       │   │                                                command; no
│       │   │                                                current dispatcher
│       │   │                                                emits it. Historical
│       │   │                                                events from 007 are
│       │   │                                                untouched.
│       │   ├── create_npc_blueprint.ex             # NEW — %CreateNPCBlueprint{
│       │   │                                                blueprint_id, name,
│       │   │                                                short_description,
│       │   │                                                long_description}.
│       │   └── spawn_npc_clone.ex                  # NEW — %SpawnNPCClone{
│       │                                                  blueprint_id,
│       │                                                  clone_id, room_id}.
│       ├── events/
│       │   ├── npc_spawned_in_room.ex              # UNCHANGED — kept for
│       │   │                                                replay; no new
│       │   │                                                events of this
│       │   │                                                type are emitted.
│       │   ├── npc_blueprint_created.ex            # NEW — %NPCBlueprintCreated{
│       │   │                                                blueprint_id, name,
│       │   │                                                short_description,
│       │   │                                                long_description,
│       │   │                                                version: 1}.
│       │   └── npc_cloned_from_blueprint.ex        # NEW — %NPCClonedFromBlueprint{
│       │                                                  blueprint_id, clone_id,
│       │                                                  room_id, serial, name,
│       │                                                  short_description,
│       │                                                  long_description,
│       │                                                  version: 1}.
│       ├── schemas/
│       │   ├── npc.ex                              # RENAMED to npc_clone.ex —
│       │   │                                                module renames from
│       │   │                                                Schemas.NPC to
│       │   │                                                Schemas.NPCClone;
│       │   │                                                table renames from
│       │   │                                                world_npcs to
│       │   │                                                npc_clones; adds
│       │   │                                                blueprint_id +
│       │   │                                                serial columns.
│       │   └── npc_blueprint.ex                    # NEW — Ecto schema for
│       │                                                  npc_blueprints. Fields:
│       │                                                  id (string, slug),
│       │                                                  name, short, long,
│       │                                                  is_synthetic boolean.
│       ├── room.ex                                  # MODIFIED — REMOVE
│       │                                                       npc_ids,
│       │                                                       npc_names_lower
│       │                                                       from defstruct.
│       │                                                       REMOVE execute/2
│       │                                                       clauses for
│       │                                                       SpawnNPC. KEEP
│       │                                                       apply/2 clause
│       │                                                       for
│       │                                                       NPCSpawnedInRoom
│       │                                                       as a no-op
│       │                                                       (replay
│       │                                                       compatibility).
│       ├── router.ex                                # MODIFIED — REMOVE
│       │                                                       SpawnNPC from
│       │                                                       Room dispatch.
│       │                                                       ADD identify
│       │                                                       NPCBlueprint
│       │                                                       and dispatch
│       │                                                       [CreateNPCBlueprint,
│       │                                                       SpawnNPCClone]
│       │                                                       to NPCBlueprint.
│       ├── projections/
│       │   └── world_projector.ex                  # MODIFIED — extend handle/2
│       │                                                       for new events
│       │                                                       (NPCBlueprintCreated
│       │                                                       → upsert
│       │                                                       npc_blueprints
│       │                                                       row;
│       │                                                       NPCClonedFromBlueprint
│       │                                                       → insert
│       │                                                       npc_clones row).
│       │                                                       REWRITE handle/2
│       │                                                       for the legacy
│       │                                                       NPCSpawnedInRoom
│       │                                                       event: derive
│       │                                                       synthetic
│       │                                                       blueprint id
│       │                                                       via UUID5,
│       │                                                       upsert
│       │                                                       npc_blueprints
│       │                                                       row, insert
│       │                                                       clone with
│       │                                                       computed serial.
│       ├── queries.ex                                # MODIFIED — change
│       │                                                       schema alias
│       │                                                       NPC → NPCClone;
│       │                                                       list_npcs_in_room/1
│       │                                                       and
│       │                                                       resolve_npc_in_room/2
│       │                                                       query against
│       │                                                       the renamed
│       │                                                       schema. Return
│       │                                                       shapes are
│       │                                                       unchanged.
│       ├── examine.ex                                # MODIFIED — change
│       │                                                       Schemas.NPC →
│       │                                                       Schemas.NPCClone
│       │                                                       in
│       │                                                       long_description_of_npc/1.
│       │                                                       Behavior
│       │                                                       unchanged.
│       ├── seed.ex                                   # MODIFIED — REPLACE the
│       │                                                       feature 007
│       │                                                       SpawnNPC
│       │                                                       dispatch with
│       │                                                       CreateNPCBlueprint
│       │                                                       (slug
│       │                                                       "garrick_the_innkeeper")
│       │                                                       + SpawnNPCClone
│       │                                                       (clone_id =
│       │                                                       existing UUID).
│       └── ui_event_broadcaster.ex                  # MODIFIED — UPDATE handle/2
│                                                               for
│                                                               NPCSpawnedInRoom
│                                                               to import the
│                                                               renamed
│                                                               schemas if it
│                                                               references
│                                                               them; ADD
│                                                               handle/2 clause
│                                                               for
│                                                               NPCClonedFromBlueprint
│                                                               that broadcasts
│                                                               RoomNPCArrived
│                                                               identically.
│                                                               Both paths
│                                                               yield the same
│                                                               UI event.

priv/
└── repo/
    └── migrations/
        └── 2026MMDDHHMMSS_introduce_npc_blueprints.exs
                                                      # NEW — drops world_npcs;
                                                              creates
                                                              npc_blueprints
                                                              (id string PK,
                                                              name, short,
                                                              long,
                                                              is_synthetic,
                                                              timestamps);
                                                              creates
                                                              npc_clones
                                                              (id binary_id PK,
                                                              blueprint_id FK
                                                              → npc_blueprints.id
                                                              on_delete:
                                                              :restrict, serial
                                                              int, name, short,
                                                              long, room_id
                                                              FK, timestamps,
                                                              UNIQUE
                                                              (blueprint_id,
                                                              serial), UNIQUE
                                                              (room_id,
                                                              LOWER(name)));
                                                              resets
                                                              WorldProjector
                                                              subscription
                                                              position.

test/
├── agenticrealms/
│   └── world/
│       ├── npc_blueprint_test.exs                   # NEW — aggregate unit
│       │                                                  tests:
│       │                                                  CreateNPCBlueprint
│       │                                                  happy + duplicate id
│       │                                                  refusal +
│       │                                                  empty-long-description
│       │                                                  refusal;
│       │                                                  SpawnNPCClone happy
│       │                                                  + uninitialized
│       │                                                  blueprint refusal +
│       │                                                  duplicate clone_id
│       │                                                  refusal + serial
│       │                                                  monotonic across N
│       │                                                  spawns.
│       ├── room_test.exs                             # MODIFIED — REMOVE the
│       │                                                       SpawnNPC test
│       │                                                       block added in
│       │                                                       feature 007.
│       │                                                       Existing
│       │                                                       PlaceObject /
│       │                                                       TakeObject /
│       │                                                       DropObject
│       │                                                       tests remain.
│       │                                                       ADD one test:
│       │                                                       NPCSpawnedInRoom
│       │                                                       apply clause is
│       │                                                       a no-op
│       │                                                       (state
│       │                                                       unchanged).
│       ├── examine_test.exs                          # MODIFIED — update
│       │                                                       insert_npc/3
│       │                                                       helper to use
│       │                                                       Schemas.NPCClone
│       │                                                       and provide
│       │                                                       blueprint_id +
│       │                                                       serial. Add a
│       │                                                       per-test
│       │                                                       insert_blueprint/3
│       │                                                       helper that
│       │                                                       seeds the
│       │                                                       referenced
│       │                                                       blueprint
│       │                                                       (FK).
│       └── projections/
│           └── world_projector_npc_replay_test.exs   # NEW — wipe-and-replay
│                                                              integration
│                                                              tests: (a)
│                                                              replay an
│                                                              event store
│                                                              with ONLY
│                                                              legacy
│                                                              NPCSpawnedInRoom
│                                                              events
│                                                              produces
│                                                              synthetic
│                                                              blueprints +
│                                                              clones; (b)
│                                                              replay with
│                                                              mixed legacy
│                                                              + new events
│                                                              produces both
│                                                              cleanly; (c)
│                                                              double replay
│                                                              is idempotent.
└── agenticrealms_web/
    └── live/
        └── game_live_npc_test.exs                    # MODIFIED — adjust
                                                                  imports
                                                                  (Schemas.NPC
                                                                  →
                                                                  Schemas.NPCClone);
                                                                  the IEx
                                                                  dispatches
                                                                  in the
                                                                  parallel-
                                                                  session
                                                                  test use
                                                                  CreateNPCBlueprint
                                                                  +
                                                                  SpawnNPCClone
                                                                  instead of
                                                                  the
                                                                  removed
                                                                  SpawnNPC.
                                                                  Acceptance
                                                                  scenarios
                                                                  unchanged.
```

**Structure Decision**: The blueprint/clone split slots into the existing project layout without introducing new top-level concepts. `NPCBlueprint` is an aggregate alongside `Room` and `Player`; `Schemas.NPCBlueprint` is a schema alongside the others. The projector grows two new handler clauses + a legacy-event rewrite; everything else either renames or stays put.

The two architecturally-novel pieces are:

1. **The blueprint aggregate's serial counter**, which is the most interesting state in this whole feature. It's owned by the aggregate (not a DB sequence, not a projector-side counter, not a global atomic). This places the serial-assignment decision at the natural serialization boundary (the aggregate's command-execution gate) and means concurrent `SpawnNPCClone` dispatches against the same blueprint are serialized for free.

2. **The synthetic-blueprint generator** in the projector. It exists solely to handle legacy `NPCSpawnedInRoom` events from feature 007 — events that lack a `blueprint_id` field but must project into a schema that requires one. The deterministic UUID5 derivation gives idempotent replay (FR-020). The `is_synthetic` flag exists in the schema specifically so wizards (future feature) can identify and optionally adopt synthetic blueprints as "real" authored content during a migration phase.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No violations. The feature is a structural refactor; complexity is largely conserved across the change:

| Decision | Why it's the simplest viable answer |
|---|---|
| New `NPCBlueprint` aggregate (instead of a DB sequence + projector logic) | Aggregate ownership of `next_serial` is the natural Commanded idiom. Alternative (DB sequence, projector-computed serial) requires extra coordination and doesn't extend cleanly to runtime spawning. |
| Per-room uniqueness via DB unique index + pre-dispatch check (instead of aggregate state) | Two-aggregate coordination (blueprint + room) for one invariant is over-engineered. The DB index + pre-dispatch check provides equivalent safety for seed-only spawning, with simpler code. The race window only matters under runtime spawning, which is a future feature concern. |
| `Schemas.NPC` → `Schemas.NPCClone` rename (instead of inventing a new name) | Clones are NPCs that have been instantiated; the name aligns with the user-facing terminology established by the design conversation. |
| Synthetic blueprint deterministic id via UUID5 of payload tuple (instead of a random UUID per legacy event) | Deterministic ids guarantee idempotent replay. Random UUIDs would create duplicate synthetic blueprints on every replay run. |
| `Room` aggregate keeps `NPCSpawnedInRoom` apply/2 clause as a no-op (instead of removing it) | Commanded rehydrates aggregates by replaying their stream. Removing the clause would crash rehydration on any Room with a historical NPC event. A no-op is the minimum-surface answer. |
| Wipe-and-replay migration via projector subscription reset (instead of in-place SQL migration) | Per Q2 clarification — leans on event-store-as-source-of-truth, exercises the synthetic-blueprint path on every developer's first migration as implicit regression coverage. |
