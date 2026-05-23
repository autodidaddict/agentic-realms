# Implementation Plan: Static NPCs

**Branch**: `007-static-npcs` | **Date**: 2026-05-23 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/007-static-npcs/spec.md`

## Summary

Introduce a new first-class entity type — NPC — that lives only in rooms, is un-gettable, and is examinable the same way game objects and other players are. NPCs are spawned via a new `SpawnNPC` Commanded command (seed-time only in this feature, per the 2026-05-23 clarification), which raises an `NPCSpawnedInRoom` event projected into a new `world_npcs` read model and broadcast as a `RoomNPCArrived` UI event so live sessions in the destination room append a `<name> arrives.` system entry. The room renderer gains an "Also here" section that lists NPCs by display name (locked-in label from the 2026-05-23 clarification), the `World.Examine` module's scope is extended to include same-room NPCs, and `World.Commands.take/2` consults the new NPC read model so attempts to `take <npc>` resolve through the existing fixed-object refusal pipeline.

**Load-bearing design decisions**:

- **NPC is a parallel entity, not a subtype**. The spec is explicit ("a first class citizen"). We add a new aggregate state slice on `Room`, a new schema (`World.Schemas.NPC`), a new read-model table (`world_npcs`), and a new event (`NPCSpawnedInRoom`). NPCs do NOT extend `Object` and do NOT extend `Player` — both would muddle the existing un-gettable / takeable code paths and force conditionals on every site that touches the muddled type. The parallel-entity choice is what the user's "first class citizen" framing demands and it isolates every new branch behind one of three named types.
- **Per-room display name uniqueness (FR-001a) is enforced at three layers**: DB unique index on `world_npcs(room_id, LOWER(name))`, aggregate state (`Room.npc_names_lower` MapSet rejects collisions in-flight), and seed-time validation (a violation aborts the seed). Defense in depth — no single bug-class can let two NPCs named "Garrick" co-exist in the same room.
- **No `fixed`/`takeable` flag on the NPC schema** in this feature. Every NPC is un-gettable by virtue of being an NPC; exposing a flag now would require deciding what the false case means (a "summonable" NPC? a "takeable" NPC? — neither is in scope). FR-003's "same TYPE of flag" requirement is honored at the **refusal-path** level rather than the **schema** level: `World.Commands.take/2` consults the NPC read model in the same conditional structure as `Queries.object_fixed?/1`, and the LiveView's existing `:object_is_fixed` clause renders the refusal. Future features that need takeable NPCs can add the flag then with no schema rewrite.
- **`SpawnNPC` is routed to the existing `Room` aggregate** (just like `PlaceObject`). NPCs belong to a room and a room is the natural serialization point for "what is currently here." We do NOT introduce a per-NPC aggregate — NPCs have no behavior, no movement, no state machine in this feature (FR-017 / FR-018 / FR-019), so an aggregate per NPC would be all overhead and no payoff. If future features make NPCs stateful, they may extract a new aggregate then.
- **The arrival-witness pipeline is wired up end-to-end even though seed-time is the only trigger in this feature** (per Q1 clarification). The `UIEventBroadcaster` gains an `NPCSpawnedInRoom` handler that broadcasts `RoomNPCArrived`, and `GameLive.handle_info(%RoomNPCArrived{}, ...)` appends the `<name> arrives.` system entry and refreshes the room render. Proving the contract under the seed-time-only trigger means the next feature (runtime spawn, movement, dialogue triggers) lights up the path for free.
- **No "leaves" / departure entry, ever**. Per the Q2 clarification, this feature explicitly does NOT emit a `<name> leaves.` counterpart. Even if a world-reset wipes a room's NPCs, we do not synthesize departure events. Players discover removed NPCs via the next `look`. No `NPCDespawned` event is defined; no LiveView departure handler is added. This is a hard line that prevents accidental scope creep.
- **`World.Examine` extends, doesn't fork**. The existing three-stage resolver (exact > partial, inventory > room, mixed-kind tie → refuse) is extended to include `:npc` as a third `target_kind`. NPCs participate only in the room scope (never inventory). Cross-type ties (NPC + player + object exact-matching the same lowercased name in the same room) refuse with `:ambiguous_mixed_kind` — same refusal shape, expanded to recognize the new kind. The Examine module remains pure; no new external dependencies.
- **Render path stays HEEx-only**. `GameComponents.log_entry/1` gets one new clause for `kind: :detail, target_kind: :npc` (parallel to the existing object/player branches), and the room renderer gets an "Also here" section that renders only when `room.npcs` is non-empty. No new CSS classes beyond an "also-here" rule that mirrors the existing "objects" / "other-players" section styling.
- **Take refusal reuses `:object_is_fixed`** rather than introducing a new error atom. `World.Commands.take/2` falls through to a new `resolve_npc_in_room/2` query when no game object matches; if an NPC matches, the function short-circuits with `{:error, :object_is_fixed}`. The LiveView's existing clause `{:error, :object_is_fixed} -> "You can't take that."` then fires unchanged. This is exactly the "same code path" wording in FR-015 / the user's spec input.

**Per-spec design**:

- **"Also here" section label** is locked at the literal string `Also here` per the 2026-05-23 clarification (Q4). It is a structural section in the room view, parallel to the existing object listing and the other-players listing. When the room contains zero NPCs the section is omitted entirely (FR-004 — no empty headings).
- **Long description rendering** for an examined NPC is identical in shape to an examined object: a `:detail` log entry with `target_kind: :npc`, the NPC's display name shown alongside the long description (FR-006 — same render contract as feature 006 FR-008). The `Examine.Match` struct adds `:npc` as a valid `target_kind`.
- **Multi-session arrival delivery** (FR-014) inherits feature 003's FR-035 plumbing for free: `Phoenix.PubSub.broadcast/3` against the room topic fans out to every subscriber LiveView, which means every concurrent session for every player in the room receives the `RoomNPCArrived` message and appends its own `<name> arrives.` entry.
- **Self-NPC alias collision protection**: NPCs never participate in self-examination (`look me` / `look self`) — those resolve only to the acting player (existing behavior). The `Examine` module's `@self_aliases` whitelist remains object/player-only; no NPC can satisfy `look me`.
- **Seed-time spawn placement**: the existing `Seed.run/0` is extended to dispatch one `SpawnNPC` command after the existing room/exit/object commands, placing Garrick the Innkeeper into the Stone Atrium. The Stone Atrium is the designated starting room (`@starting_room_id`), so a fresh login immediately sees the new NPC in the "Also here" section without needing to move.

## Technical Context

**Language/Version**: Elixir 1.15+ / Erlang OTP 26+ (unchanged from 003–006)
**Primary Dependencies**: Existing only — Phoenix 1.8.5, Phoenix LiveView 1.1.0, `phoenix_pubsub`, `commanded`, `commanded_eventstore_adapter`, `jason`, `ecto`, `req`. No new runtime deps.
**External Service**: Anthropic Messages API (unchanged — same endpoint, same model `claude-haiku-4-5-20251001`, same auth + caching strategy). The `look` tool description grows by one sentence ("...or an NPC currently in the room") and the per-request user-message snapshot (`ContextSnapshot.render/3`) gains one new line `NPCs here: <names>`.
**Storage**: PostgreSQL via existing `world_objects` / `world_rooms` / `player_states` / `account_players` tables plus a new `world_npcs` table. One new migration. EventStore gains a new event stream entry type (`NPCSpawnedInRoom`).
**Testing**: ExUnit. Six layers — (1) `Room` aggregate unit tests for `SpawnNPC` (id uniqueness, per-room name uniqueness, room-not-found), (2) `WorldProjector` unit test for `NPCSpawnedInRoom` insert, (3) `Queries` test for `list_npcs_in_room/1` and `resolve_npc_in_room/2`, (4) `Examine` unit tests for NPC matching (exact, partial, cross-type tie refusal, no-inventory-NPCs), (5) `World.Commands.take` unit test for NPC refusal path (returns `:object_is_fixed`), (6) LiveView integration test for the end-to-end flow: fresh login sees Garrick in the "Also here" section, `look garrick` renders the detail entry, `take garrick` produces "You can't take that.", and a parallel-session test for the seed-time `NPCSpawnedInRoom` → `<name> arrives.` broadcast.
**Target Platform**: Web browser (desktop, unchanged).
**Project Type**: Phoenix LiveView monolith (unchanged).

**Performance Goals**:
- NPC examination latency inherits the same target as feature 006 (canonical `look <target>` under 50ms p99). The NPC scope query is one indexed read against `world_npcs` by `room_id`; the long description fetch is a single `Repo.get/2` by id. Comfortably under budget.
- NPC arrival broadcast latency under 100ms p99 from `SpawnNPC` dispatch to `RoomNPCArrived` arriving in the GameLive `handle_info`. Inherits the same `consistency: :strong` posture as the existing `RoomObjectTaken` / `RoomPlayerArrived` broadcasts.
- Room render with NPCs adds one indexed query (`SELECT id, name, short_description FROM world_npcs WHERE room_id = $1 ORDER BY name`) — well inside the existing room-view budget.

**Constraints**:
- The `look` tool's description and the per-request context-snapshot format both invalidate the 5-minute ephemeral prompt cache on first deploy after this feature ships. Next request pays one uncached invocation; subsequent requests warm normally. Same posture as 005's system-prompt changes and 006's tool-schema change.
- The new event type (`NPCSpawnedInRoom`) is added to the event store. Existing event streams continue to project correctly — adding new event types is backward-compatible because no projector or aggregate is changed for existing events.
- The 500-character input cap from feature 004 / 005 continues to apply.
- No-departure-entry rule is strict (FR-017b). If a future bug accidentally raises an `NPCDespawned` event, the broadcaster MUST NOT emit a leaves entry; this is enforced by **not defining** the event in this feature.

**Scale/Scope**:
- Same as 003–006 — handful of concurrent players, starter map with 3 rooms.
- One new entity, one new event, one new command, one new aggregate command handler, one new schema, one new migration, one new UIEvent struct, one new broadcaster clause, one new LiveView `handle_info` clause, one new render-helper clause for the `:detail` `:npc` branch, one new "Also here" section in the room renderer, one extended take command refusal path, one extended Examine resolution scope.
- ~500–600 LOC of production code + tests.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The project constitution (`.specify/memory/constitution.md`) is the unfilled template — no concrete principles ratified. No gates to enforce. Proceeding (same posture as 003 / 004 / 005 / 006).

**Post-Phase 1 re-check**: No violations. The feature adds one new schema, one new command, one new event, one new UI event, and a handful of narrow extensions to existing modules (`Room` aggregate, `WorldProjector`, `UIEventBroadcaster`, `Queries`, `Examine`, `Commands.take`, `GameLive`, `GameComponents`, `IntentResolver.Tools`, `ContextSnapshot`). No new infrastructure (no new supervisors, no new external services, no new PubSub topics — reuses the existing `room:<room_uuid>` topic). No CLAUDE.md / constitution conflict.

## Project Structure

### Documentation (this feature)

```text
specs/007-static-npcs/
├── plan.md                  # This file (/speckit-plan output)
├── spec.md                  # Feature specification (clarified 2026-05-23)
├── research.md              # Phase 0: aggregate-vs-projection ownership of NPCs,
│                            #          uniqueness enforcement layering, take
│                            #          refusal reuse-vs-new-atom decision,
│                            #          seed placement choice
├── data-model.md            # Phase 1: world_npcs schema, NPC entity, Room
│                            #          aggregate state extension, Examine.Match
│                            #          extension to :npc, "Also here" section
│                            #          contract, RoomView extension
├── quickstart.md            # Phase 1: how to manually verify each user story
│                            #          end-to-end against the seeded starter map
├── contracts/
│   ├── commands.md          # Phase 1: SpawnNPC command + Room aggregate handler
│   ├── events.md            # Phase 1: NPCSpawnedInRoom domain event
│   ├── ui_events.md         # Phase 1: RoomNPCArrived UI event + GameLive handler
│   ├── queries.md           # Phase 1: list_npcs_in_room/1, resolve_npc_in_room/2
│   ├── examine.md           # Phase 1: Examine module scope + Match extension
│   ├── take_refusal.md      # Phase 1: Commands.take NPC refusal path
│   └── tools.md             # Phase 1: IntentResolver `look` description tweak
│                            #          + ContextSnapshot "NPCs here:" line
└── checklists/
    └── requirements.md      # (Already created by /speckit-specify)
```

### Source Code (repository root)

```text
lib/
├── agenticrealms/
│   └── world/
│       ├── room.ex                                 # MODIFIED — Room aggregate
│       │                                                       gains npc_ids +
│       │                                                       npc_names_lower
│       │                                                       state, SpawnNPC
│       │                                                       command handler,
│       │                                                       NPCSpawnedInRoom
│       │                                                       apply/2 clause.
│       ├── router.ex                               # MODIFIED — register SpawnNPC
│       │                                                       on the Room
│       │                                                       dispatch list.
│       ├── commands/
│       │   └── spawn_npc.ex                        # NEW — %SpawnNPC{room_id,
│       │                                                  npc_id, name,
│       │                                                  short_description,
│       │                                                  long_description}.
│       ├── events/
│       │   └── npc_spawned_in_room.ex              # NEW — %NPCSpawnedInRoom{...}
│       │                                                  with @derive Jason.Encoder
│       │                                                  and version: 1.
│       ├── schemas/
│       │   └── npc.ex                              # NEW — Ecto schema for
│       │                                                  world_npcs (id, name,
│       │                                                  short_description,
│       │                                                  long_description,
│       │                                                  belongs_to :room).
│       ├── projections/
│       │   └── world_projector.ex                  # MODIFIED — handle/2 clause
│       │                                                       for NPCSpawnedInRoom
│       │                                                       inserts %NPC{...}
│       │                                                       into world_npcs.
│       ├── ui_event_broadcaster.ex                 # MODIFIED — handle/2 clause
│       │                                                       for NPCSpawnedInRoom
│       │                                                       fans out RoomNPCArrived
│       │                                                       on room topic.
│       ├── ui_events.ex                            # MODIFIED — defmodule
│       │                                                       RoomNPCArrived
│       │                                                       (added; reuses
│       │                                                       UIEvents pattern).
│       ├── queries.ex                              # MODIFIED — new
│       │                                                       list_npcs_in_room/1
│       │                                                       and
│       │                                                       resolve_npc_in_room/2;
│       │                                                       look_room/1 now
│       │                                                       populates
│       │                                                       RoomView.npcs.
│       ├── room_view.ex                            # MODIFIED — RoomView struct
│       │                                                       gains :npcs field.
│       ├── examine.ex                              # MODIFIED — gather_scope/1
│       │                                                       includes NPCs;
│       │                                                       resolve/2 handles
│       │                                                       :npc kind; new
│       │                                                       filter helpers.
│       ├── examine/
│       │   └── match.ex                            # MODIFIED — target_kind now
│       │                                                       includes :npc.
│       ├── commands.ex                             # MODIFIED — take/2 falls
│       │                                                       through to
│       │                                                       Queries.resolve_npc_in_room/2
│       │                                                       on :no_such_object,
│       │                                                       returns
│       │                                                       :object_is_fixed
│       │                                                       on NPC match.
│       ├── intent_resolver/
│       │   ├── tools.ex                            # MODIFIED — `look` tool
│       │   │                                                   description: add
│       │   │                                                   "...or an NPC
│       │   │                                                   currently in the
│       │   │                                                   room" + minor
│       │   │                                                   example tweak;
│       │   │                                                   `take` tool's
│       │   │                                                   description and
│       │   │                                                   target schema
│       │   │                                                   remain
│       │   │                                                   unchanged (the
│       │   │                                                   model still emits
│       │   │                                                   {:take, name};
│       │   │                                                   the refusal is
│       │   │                                                   server-side).
│       │   └── context_snapshot.ex                 # MODIFIED — render/3 adds
│       │                                                       one "NPCs here:"
│       │                                                       line below
│       │                                                       "Objects here:".
│       └── seed.ex                                 # MODIFIED — after seeding
│                                                               rooms / exits /
│                                                               objects,
│                                                               dispatch one
│                                                               SpawnNPC for
│                                                               Garrick the
│                                                               Innkeeper into
│                                                               the Stone Atrium.
└── agenticrealms_web/
    ├── live/
    │   └── game_live.ex                            # MODIFIED — new handle_info
    │                                                           clause for
    │                                                           %RoomNPCArrived{}
    │                                                           appends
    │                                                           "<name> arrives."
    │                                                           system entry +
    │                                                           refreshes
    │                                                           assigns.room.
    └── components/
        └── game_components.ex                       # MODIFIED — log_entry/1
                                                                clause for
                                                                kind: :detail,
                                                                target_kind: :npc;
                                                                room renderer
                                                                gains "Also
                                                                here" section
                                                                when
                                                                room.npcs is
                                                                non-empty.

priv/
├── intent_resolver/
│   └── system_prompt.md                            # MODIFIED — one new line
│                                                              in the "Look /
│                                                              examine" section
│                                                              clarifying that
│                                                              NPCs are valid
│                                                              examination
│                                                              targets and may
│                                                              be referred to
│                                                              by name or
│                                                              descriptive
│                                                              paraphrase.
└── repo/
    └── migrations/
        └── 2026MMDDHHMMSS_create_world_npcs.exs    # NEW — world_npcs table
                                                          with id (binary_id),
                                                          name (string, NOT
                                                          NULL), short/long
                                                          descriptions (NOT
                                                          NULL), room_id (FK
                                                          NOT NULL), unique
                                                          index on
                                                          (room_id, LOWER(name)).

test/
├── agenticrealms/
│   └── world/
│       ├── room_test.exs                            # MODIFIED — new tests for
│       │                                                       SpawnNPC: happy
│       │                                                       path, duplicate
│       │                                                       npc_id, duplicate
│       │                                                       name in same
│       │                                                       room (refuse),
│       │                                                       same name across
│       │                                                       different rooms
│       │                                                       (allow), unknown
│       │                                                       room.
│       ├── projections/
│       │   └── world_projector_test.exs             # MODIFIED — new test for
│       │                                                       NPCSpawnedInRoom
│       │                                                       projection
│       │                                                       inserting into
│       │                                                       world_npcs.
│       ├── queries_test.exs                         # MODIFIED — new tests for
│       │                                                       list_npcs_in_room/1
│       │                                                       (ordered by name)
│       │                                                       and
│       │                                                       resolve_npc_in_room/2
│       │                                                       (case-insensitive,
│       │                                                       ambiguity).
│       ├── examine_test.exs                         # MODIFIED — new tests for
│       │                                                       NPC matching:
│       │                                                       exact name,
│       │                                                       partial name,
│       │                                                       NPC + same-named
│       │                                                       player tie →
│       │                                                       :ambiguous_mixed_kind,
│       │                                                       NPC + same-named
│       │                                                       object tie →
│       │                                                       :ambiguous_mixed_kind,
│       │                                                       NPCs not
│       │                                                       findable via
│       │                                                       inventory scope.
│       ├── commands_take_test.exs                   # MODIFIED — new test:
│       │                                                       take of an NPC
│       │                                                       name returns
│       │                                                       {:error,
│       │                                                       :object_is_fixed}.
│       └── intent_resolver/
│           └── context_snapshot_test.exs            # MODIFIED — new test:
│                                                               render/3 includes
│                                                               "NPCs here:"
│                                                               line; empty NPC
│                                                               list renders as
│                                                               "(none)".
└── agenticrealms_web/
    └── live/
        ├── game_live_npc_test.exs                   # NEW — LiveView integration.
        │                                                   Fresh login renders
        │                                                   "Also here" section
        │                                                   with Garrick;
        │                                                   `look garrick`
        │                                                   appends detail entry
        │                                                   with long description;
        │                                                   `take garrick`
        │                                                   appends
        │                                                   "You can't take
        │                                                   that.";
        │                                                   parallel-session
        │                                                   test fires SpawnNPC
        │                                                   while two sessions
        │                                                   are connected to
        │                                                   the destination
        │                                                   room and both
        │                                                   sessions receive
        │                                                   "<name> arrives.".
        └── live/
            └── game_live_intent_parser_test.exs     # MODIFIED — natural-language
                                                              phrasings
                                                              ("examine the
                                                              innkeeper",
                                                              "pick up the old
                                                              man") route
                                                              correctly via
                                                              LLM fallback to
                                                              {:look, "<npc>"}
                                                              and
                                                              {:take, "<npc>"}
                                                              respectively.
```

**Structure Decision**: NPCs join the existing parallel layers — domain (aggregate state on `Room` + new command + new event), read-model (new `world_npcs` table + new schema + new query helpers + extension of the existing `RoomView`), UI broadcast (new `RoomNPCArrived` UIEvent + new broadcaster clause + new GameLive `handle_info` clause), render (extension of `GameComponents`'s room renderer and `:detail` clauses), and resolver (extension of `Examine` + minor tweak to the `look` tool description and `ContextSnapshot`).

No new top-level module is introduced — `World.Examine` is the closest candidate for a new dedicated module ("NPC interaction") but its scope here is purely "extend the resolver's set of visible targets," which is exactly what that module exists for. Future features that introduce active NPC behavior (combat, dialogue, scripts) will likely want a dedicated `World.NPC` module owning the behavior; we are deliberately not creating that module now to avoid premature abstraction. The schema (`World.Schemas.NPC`) sits alongside `Schemas.Object` / `Schemas.Room` / `Schemas.PlayerState` / `Schemas.Exit` exactly the way every other entity-bearing read model does.

The decision to route `SpawnNPC` to the existing `Room` aggregate (rather than introducing a new `NPC` aggregate) is the one architectural call worth flagging: NPCs in this feature have no behavior of their own to serialize, and their lifecycle (spawn-only, no movement, no removal) is owned by the room they live in. If a later feature gives NPCs state machines (combat HP, dialogue trees, schedules), extracting an `NPC` aggregate at that point is straightforward — the persisted event stream is forward-compatible because `NPCSpawnedInRoom` already carries the `npc_id`, which a future extraction would use as the aggregate identity prefix.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No violations. The new schema, new command, new event, and new UI event are the minimum surface to introduce a new entity type into an event-sourced read model that drives a live UI. Reusing the `Room` aggregate (instead of a per-NPC aggregate) is the simpler choice; reusing `:object_is_fixed` (instead of a new error atom) is the simpler choice; extending the existing `Examine` and `Queries` modules (instead of forking) is the simpler choice. The "Also here" section is the only user-facing rendering decision and it was locked in by the Q4 clarification. No alternatives offer a smaller footprint.
