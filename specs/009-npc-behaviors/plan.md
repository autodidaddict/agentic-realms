# Implementation Plan: NPC and Room Behaviors (Triggers + Actions, Minimal Set)

**Branch**: `009-npc-behaviors` | **Date**: 2026-05-24 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/009-npc-behaviors/spec.md`

## Summary

Introduce a data-shaped behavior system: NPC blueprints and rooms can hold a list of `(trigger, [actions])` tuples. Two triggers ship (`player_entered`, `player_left`); one action ships (`say <text>`). A new Commanded event handler — `World.Behaviors.Interpreter` — subscribes to `PlayerSpawned` and `PlayerMoved` domain events and dispatches matching behaviors. Behavior firings produce TWO new transient log-entry kinds via Phoenix.PubSub broadcasts:

- `:npc_speech` — NPC clone as speaker, rendered with the clone's display name (`Garrick the Innkeeper says, "..."`). Delivered to every player in the speaker's room (feature 004 say semantics).
- `:room_speech` — room as source, rendered as unattributed ambient narration (just the line, no "X says"). Delivered only to the player whose movement triggered the behavior.

The Garrick blueprint and the Stone Atrium each gain seeded behaviors so the feature is demonstrable from a fresh login.

**Load-bearing design decisions**:

- **Behaviors are data, not code.** Stored as JSONB on `npc_blueprints.behaviors`, `npc_clones.behaviors`, and `world_rooms.behaviors`. Format is `[%{"trigger" => "player_entered", "actions" => [%{"type" => "say", "text" => "..."}]}, ...]`. A small validator module sanity-checks the shape at insertion time (seed dispatch); the interpreter assumes valid shape at firing time and skips malformed individual actions rather than crashing the whole list.
- **Behavior firings are non-event-sourced (FR-016).** The interpreter produces transient PubSub broadcasts only — never appends to the Commanded event store, never emits a domain event. This matches feature 004's player-speech posture exactly.
- **Replay guard via Commanded subscription start position (FR-016a).** The `World.Behaviors.Interpreter` event handler is configured with `start_from: :current` (i.e., it subscribes from the current event-store HEAD, not from position 0). Historical events that fired before the interpreter started are never processed by it. On a fresh deploy / `mix event_store.reset && mix ecto.reset`, the interpreter starts after seed completes, and seed's spawn events fire behaviors. Future movements fire behaviors. A wipe-and-replay rebuild does NOT re-fire history. This is the simplest, most operationally clear solution to FR-016a.
- **Behavior inheritance via feature 008 full-copy.** The `NPCBlueprint` aggregate's `execute(SpawnNPCClone)` clause stamps the blueprint's current `behaviors` list into the emitted `NPCClonedFromBlueprint` event payload (new field). The projector denormalizes onto `npc_clones.behaviors`. This means blueprint behavior edits do NOT propagate to existing clones — the wizard tab feature will revisit propagation semantics; this feature locks in the same blast-radius posture as feature 008.
- **Event schema evolution: `NPCClonedFromBlueprint` gains an optional `behaviors` field.** Existing events in the event store (from feature 008) deserialize with `behaviors: []` (default), and the projector treats that as "no behaviors." Future-feature events emit non-empty behaviors. Fully backward-compatible — no migration of historical event payloads needed. Same pattern for `NPCBlueprintCreated`.
- **Delivery via player-topic (NOT room-topic).** The interpreter broadcasts new `BehaviorUtterance` UI events on `World.player_topic(player_id)` for the appropriate set of players. Specifically:
  - `:room_speech` → broadcast only on `player_topic(triggering_player_id)`.
  - `:npc_speech` → broadcast on `player_topic(triggering_player_id)` PLUS `player_topic(p)` for every OTHER player in the speaker's room (queried from the read model at firing time).
  This bypasses the room-topic delivery used by feature 004 because of two requirements: (1) `:room_speech` is triggering-player-only, which room-topic can't express, and (2) the moving player must receive `:npc_speech` for `player_left` even though they're about to unsubscribe from the source-room topic, AND for `player_entered` before they've subscribed to the destination topic. Player-topic delivery sidesteps both subscription-window issues — GameLive subscribes to its own player-topic on mount and never unsubscribes during movement.
- **Three new log entry kinds in GameLive's render path:**
  - `:npc_speech` clause — renders `<name> says, "<text>"` with `class="log-entry speech speech-npc"`.
  - `:room_speech` clause — renders just the text, italicized, with `class="log-entry narrate narrate-room"` (no actor name, no quotation marks framing it as speech).
  Both inherit from the existing `GameComponents.log_entry/1` pattern.
- **FR-017a ordering relaxation.** The natural Commanded + PubSub timing puts behavior-sourced entries AFTER the destination room view renders for both `player_entered` AND `player_left`. The spec's FR-017a aspires to "before destination view" for `player_left`, but achieving that would require pre-dispatch behavior firing in the LiveView handler — a coupling we're explicitly avoiding (interpreter stays event-handler-bound, not LiveView-bound, for testability and architectural symmetry with other handlers). The plan accepts the natural order: the leaving player STILL receives the goodbye (FR-017 honored), just slightly after the destination room renders. FR-017a's narrative ideal is filed as a future polish concern.
- **Feature 007 FR-018 relaxation is documentation-only.** Feature 007 forbade NPC speech as a *scope* rule, not a runtime invariant — there's no code in the existing codebase that prevents NPCs from speaking. So this feature doesn't need to remove a check; it simply documents the lifting in the spec and adds the new code paths that produce NPC speech. The remaining feature 007 restrictions (NPCs cannot move, cannot participate in combat) remain unchanged.

**Behavior data movement (the three events)**: behavior data travels through exactly three Commanded events in this feature, all extended with a backward-compatible optional `:behaviors` field defaulting to `[]`:

| Event | Carries behaviors for | Backward-compat for existing events |
|---|---|---|
| `RoomCreated` (existing, EXTENDED) | rooms at creation time | feature 003/008 events deserialize with `behaviors: []` |
| `NPCBlueprintCreated` (feature 008, EXTENDED) | NPC blueprints at authoring time | feature 008 events deserialize with `behaviors: []` |
| `NPCClonedFromBlueprint` (feature 008, EXTENDED) | NPC clones at spawn time (full-copied from blueprint) | feature 008 events deserialize with `behaviors: []` |

There are **no mutation events for behaviors in this feature**. Rooms are created once with their initial behaviors; blueprints are immutable (feature 008 FR-005a); clones own their copy from the moment of spawning. Future features that introduce wizard-edit paths will add behavior-mutation events at that time.

The choice to extend `RoomCreated` (rather than introduce a `SetRoomBehaviors` event) was a deliberate decision (clarified mid-plan, 2026-05-24): event-sourced data only — a non-event-sourced direct DB write would be wiped during replay, breaking feature 008's wipe-and-replay posture. Both NPC and room behaviors follow the same pattern: stamped into the creation event, replayed deterministically.

**Per-spec design**:

- **Two triggers + one action vocabulary**: enforced by a small validator (`World.Behaviors.Validator`) called at seed-dispatch time. Unknown trigger atoms or action types raise during seed run, so authoring errors fail fast. The interpreter dispatches on trigger atoms and pattern-matches on action shape — also a defensive layer.
- **Firing order** (FR-008a): for any given trigger event in a room, the interpreter executes the ROOM's behaviors first, then enumerates NPC clones in the room (ordered by `serial` for determinism) and executes each clone's behaviors. Within a single entity's behavior list, behaviors fire in authored order; within a single behavior, actions fire in authored order.
- **Single-threaded execution per trigger event**: Commanded's event handler model processes events serially per subscription. No locking needed.
- **`:say` text validation**: the seed validator caps `text` at 500 characters (FR-004). The interpreter trusts the validator — it doesn't re-check.
- **Garrick's behavior list** (seed): `[{player_entered: [say "Welcome to the Stone Atrium."]}, {player_left: [say "Farewell, traveler."]}]`. Stone Atrium's behavior list (seed): `[{player_entered: [say "The cool air carries the scent of rain."]}]`. These are the minimum seeded content for SC-001, SC-002, and Story 3's room-narration smoke.

## Technical Context

**Language/Version**: Elixir 1.15+ / Erlang OTP 26+ (unchanged from 003–008)
**Primary Dependencies**: Existing only — Phoenix 1.8.5, Phoenix LiveView 1.1.0, `commanded`, `commanded_eventstore_adapter`, `phoenix_pubsub`, `jason`, `ecto`, `req`. No new runtime deps.
**External Service**: None. The LLM resolver from feature 005 is untouched in this feature.
**Storage**: PostgreSQL via existing read-model tables. Three columns added: `npc_blueprints.behaviors` JSONB, `npc_clones.behaviors` JSONB, `world_rooms.behaviors` JSONB. One new migration; default empty list (`'[]'::jsonb`). EventStore gains no new event types — `NPCClonedFromBlueprint` and `NPCBlueprintCreated` are extended with a backward-compatible `:behaviors` field.
**Testing**: ExUnit. Six layers — (1) `World.Behaviors.Validator` unit tests for shape validation, (2) `World.Behaviors.Interpreter` unit tests for trigger dispatch (using direct handler invocation), (3) `World.NPCBlueprint` aggregate test extension for behavior stamping into `NPCClonedFromBlueprint`, (4) `WorldProjector` projection test for the new `behaviors` field (and legacy `NPCSpawnedInRoom` defaulting to `[]`), (5) `Queries` behavior-lookup test, (6) LiveView integration tests covering Story 1 (Garrick greets), Story 2 (Garrick farewells, including the leaving-player delivery), Story 3 (room narration, triggering-player-only scope), Story 4 (multi-behavior composition), Story 5 (multi-action composition).
**Target Platform**: Web browser (desktop, unchanged).
**Project Type**: Phoenix LiveView monolith (unchanged).

**Performance Goals**:
- Behavior firing latency: under 50ms from `Commands.move/2` return to the behavior-sourced entries appearing in GameLive's mailbox. Single-threaded handler, small query (1 room + a handful of NPCs), no external calls.
- Replay of historical event store: behavior interpreter does NOT participate. The `start_from: :current` config means replay is unaffected by this feature.
- Read-model footprint: ~100 bytes per behavior (JSONB), well under any practical limit. The starter map ships with 3 behaviors total.

**Constraints**:
- The behavior interpreter MUST be `consistency: :strong` so that `Commands.move/2` blocks until behaviors have fired AND broadcast. Without this, the LiveView could query its mailbox before the entries arrive.
- The interpreter's `start_from: :current` is critical for FR-016a (no re-firing on replay). The plan documents this clearly so it's not accidentally changed.
- The 500-character cap on `:say` text is validated at SEED time. The interpreter assumes well-formed data; if a malformed action slips in (e.g., a future bug in the wizard tab's input validation), the interpreter logs and skips that action rather than crashing the whole behavior list.
- The `NPCClonedFromBlueprint` event-schema evolution (adding `:behaviors` field with default `[]`) is backward-compatible. Existing events from feature 008's history deserialize cleanly; new events carry behaviors.

**Scale/Scope**:
- Same as 003–008 — handful of concurrent players, small starter map.
- New code: one validator module, one event-handler module (the interpreter), one action-executor module, one new UIEvent struct, two new GameComponents render clauses, one new migration, **three extended events** (`RoomCreated`, `NPCBlueprintCreated`, `NPCClonedFromBlueprint` — all gain optional `:behaviors` field), **two extended commands** (`CreateRoom`, `CreateNPCBlueprint`), three extended aggregate clauses (`Room` execute+apply for `CreateRoom`, `NPCBlueprint` execute for `CreateNPCBlueprint` and `SpawnNPCClone`), three extended projector handlers, two seed extensions (Garrick blueprint with behaviors, Stone Atrium room with behaviors — both at creation time via the existing dispatch path).
- ~600–800 LOC of production code + ~400 LOC of tests.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The project constitution (`.specify/memory/constitution.md`) is the unfilled template — no concrete principles ratified. No gates to enforce. Proceeding (same posture as 003–008).

**Post-Phase 1 re-check**: No violations. The feature adds one new validator module, one new event-handler module, one new action-executor module, one new UIEvent struct, and narrow extensions to existing modules. No new infrastructure, no new external services, no new PubSub topics beyond the existing `player_topic`. No CLAUDE.md / constitution conflict.

## Project Structure

### Documentation (this feature)

```text
specs/009-npc-behaviors/
├── plan.md                  # This file (/speckit-plan output)
├── spec.md                  # Feature specification (clarified 2026-05-24)
├── research.md              # Phase 0: trigger-handler subscription start position
│                            #          (replay safety), delivery topic choice
│                            #          (player vs room), behavior validator shape,
│                            #          firing order between rooms and NPCs,
│                            #          new log-entry-kind CSS treatment
├── data-model.md            # Phase 1: behavior storage shape (JSONB) on the
│                            #          three attach tables, BehaviorUtterance
│                            #          UIEvent struct, log-entry payload shapes
├── quickstart.md            # Phase 1: how to manually verify each user story
│                            #          end-to-end (incl. parallel-session test
│                            #          for triggering-player-only scope)
├── contracts/
│   ├── validator.md         # Phase 1: World.Behaviors.Validator API + format
│   ├── interpreter.md       # Phase 1: Behaviors.Interpreter event handler
│   │                        #          contract (subscription, firing logic,
│   │                        #          broadcast strategy)
│   ├── events.md            # Phase 1: NPCClonedFromBlueprint and
│   │                        #          NPCBlueprintCreated :behaviors field
│   │                        #          extensions; no new domain events
│   ├── ui_events.md         # Phase 1: BehaviorUtterance struct + GameLive
│   │                        #          handle_info clauses
│   ├── queries.md           # Phase 1: behavior-lookup query helpers
│   ├── render.md            # Phase 1: GameComponents :npc_speech and
│   │                        #          :room_speech log-entry render clauses
│   └── seed.md              # Phase 1: Garrick + Stone Atrium behavior payloads
└── checklists/
    └── requirements.md      # (Already created by /speckit-specify)
```

### Source Code (repository root)

```text
lib/
├── agenticrealms/
│   └── world/
│       ├── behaviors/                              # NEW directory
│       │   ├── validator.ex                        # NEW — Behaviors.Validator.
│       │   │                                                Validates behavior
│       │   │                                                list shape at seed
│       │   │                                                time: known triggers,
│       │   │                                                known actions, :say
│       │   │                                                text is non-empty and
│       │   │                                                ≤500 chars. Returns
│       │   │                                                :ok or {:error, atom}.
│       │   ├── interpreter.ex                      # NEW — Behaviors.Interpreter.
│       │   │                                                Commanded event handler
│       │   │                                                with start_from:
│       │   │                                                :current and
│       │   │                                                consistency: :strong.
│       │   │                                                Subscribes to
│       │   │                                                PlayerSpawned and
│       │   │                                                PlayerMoved. ~200 LOC.
│       │   └── action_executor.ex                  # NEW — Behaviors.ActionExecutor.
│       │                                                  Pure function: given a
│       │                                                  materialized action +
│       │                                                  speaker context +
│       │                                                  recipient list, builds a
│       │                                                  BehaviorUtterance and
│       │                                                  broadcasts on the
│       │                                                  appropriate player topics.
│       │                                                  Currently only knows
│       │                                                  :say; future actions add
│       │                                                  clauses.
│       ├── events/
│       │   ├── room_created.ex                     # MODIFIED — add optional
│       │   │                                                   :behaviors field
│       │   │                                                   with default `[]`.
│       │   │                                                   Existing feature
│       │   │                                                   003 events
│       │   │                                                   deserialize
│       │   │                                                   cleanly.
│       │   ├── npc_blueprint_created.ex            # MODIFIED — add optional
│       │   │                                                   :behaviors field
│       │   │                                                   with default `[]`.
│       │   │                                                   Existing feature
│       │   │                                                   008 events
│       │   │                                                   deserialize
│       │   │                                                   cleanly.
│       │   └── npc_cloned_from_blueprint.ex        # MODIFIED — same: add
│       │                                                       optional :behaviors
│       │                                                       field with default
│       │                                                       `[]`.
│       ├── room.ex                                   # MODIFIED — extend Room
│       │                                                       aggregate's
│       │                                                       defstruct with
│       │                                                       :behaviors
│       │                                                       (default `[]`).
│       │                                                       execute/2 for
│       │                                                       CreateRoom reads
│       │                                                       :behaviors from the
│       │                                                       command and passes
│       │                                                       it through to the
│       │                                                       emitted RoomCreated
│       │                                                       event. apply/2
│       │                                                       for RoomCreated
│       │                                                       sets
│       │                                                       state.behaviors.
│       ├── npc_blueprint.ex                         # MODIFIED — extend defstruct
│       │                                                       with :behaviors
│       │                                                       (default `[]`).
│       │                                                       execute/2 for
│       │                                                       CreateNPCBlueprint
│       │                                                       reads :behaviors
│       │                                                       from command and
│       │                                                       carries it through
│       │                                                       to event. apply/2
│       │                                                       for
│       │                                                       NPCBlueprintCreated
│       │                                                       sets
│       │                                                       state.behaviors.
│       │                                                       execute/2 for
│       │                                                       SpawnNPCClone
│       │                                                       stamps current
│       │                                                       behaviors into the
│       │                                                       NPCClonedFromBlueprint
│       │                                                       event payload
│       │                                                       (full-copy at
│       │                                                       clone time).
│       ├── commands/
│       │   ├── create_room.ex                      # MODIFIED — add :behaviors
│       │   │                                                   field with default
│       │   │                                                   `[]` to defstruct
│       │   │                                                   (not in
│       │   │                                                   @enforce_keys, so
│       │   │                                                   any caller that
│       │   │                                                   omits behaviors
│       │   │                                                   still works).
│       │   └── create_npc_blueprint.ex             # MODIFIED — add :behaviors
│       │                                                       field with default
│       │                                                       `[]` to defstruct
│       │                                                       (same pattern).
│       ├── projections/
│       │   └── world_projector.ex                  # MODIFIED — handle/2 for
│       │                                                       RoomCreated,
│       │                                                       NPCBlueprintCreated,
│       │                                                       and
│       │                                                       NPCClonedFromBlueprint
│       │                                                       all set :behaviors
│       │                                                       on the inserted
│       │                                                       row. The legacy
│       │                                                       NPCSpawnedInRoom
│       │                                                       handler sets
│       │                                                       behaviors: [] on
│       │                                                       its synthetic
│       │                                                       blueprint + clone
│       │                                                       inserts (legacy
│       │                                                       events had no
│       │                                                       behaviors concept).
│       │                                                       Feature 003/008
│       │                                                       events with no
│       │                                                       :behaviors field
│       │                                                       deserialize with
│       │                                                       behaviors: [] —
│       │                                                       backward-compatible.
│       ├── schemas/
│       │   ├── npc_blueprint.ex                    # MODIFIED — add :behaviors
│       │   │                                                   :map field
│       │   │                                                   (defaults to []).
│       │   ├── npc_clone.ex                        # MODIFIED — add :behaviors
│       │   │                                                   :map field
│       │   │                                                   (defaults to []).
│       │   └── room.ex                             # MODIFIED — add :behaviors
│       │                                                       :map field
│       │                                                       (defaults to []).
│       ├── queries.ex                              # MODIFIED — add
│       │                                                       get_room_behaviors/1,
│       │                                                       list_npc_clones_in_room_with_behaviors/1
│       │                                                       (returns clone_id +
│       │                                                       name + serial +
│       │                                                       behaviors, ordered
│       │                                                       by serial for
│       │                                                       deterministic
│       │                                                       firing order).
│       ├── ui_events.ex                            # MODIFIED — add new
│       │                                                       BehaviorUtterance
│       │                                                       struct module
│       │                                                       (kind ∈
│       │                                                       [:npc_speech,
│       │                                                       :room_speech],
│       │                                                       actor_name (nil for
│       │                                                       :room_speech), text,
│       │                                                       room_id,
│       │                                                       triggering_player_id).
│       └── seed.ex                                 # MODIFIED — extend Garrick's
│                                                               CreateNPCBlueprint
│                                                               dispatch with
│                                                               :behaviors payload
│                                                               for player_entered
│                                                               + player_left.
│                                                               Extend the Stone
│                                                               Atrium's CreateRoom
│                                                               dispatch with a
│                                                               :behaviors payload
│                                                               containing the
│                                                               atmospheric
│                                                               player_entered
│                                                               narration. NO
│                                                               direct DB writes —
│                                                               all behavior data
│                                                               flows through
│                                                               event-sourced
│                                                               creation events.

priv/
└── repo/
    └── migrations/
        └── 2026MMDDHHMMSS_add_behaviors_columns.exs
                                                      # NEW — add :behaviors
                                                              JSONB column
                                                              (NOT NULL, DEFAULT
                                                              '[]'::jsonb) to
                                                              npc_blueprints,
                                                              npc_clones,
                                                              world_rooms.

lib/
├── agenticrealms/
│   └── application.ex                              # MODIFIED if needed — the
│                                                               Behaviors.Interpreter
│                                                               is a Commanded
│                                                               event handler;
│                                                               registration
│                                                               follows the same
│                                                               pattern as
│                                                               WorldProjector +
│                                                               UIEventBroadcaster.
│                                                               Verify via the
│                                                               existing
│                                                               supervisor tree
│                                                               whether it
│                                                               needs an explicit
│                                                               child_spec entry.
└── agenticrealms_web/
    ├── live/
    │   └── game_live.ex                            # MODIFIED — ADD
    │                                                           handle_info
    │                                                           clauses for
    │                                                           %BehaviorUtterance{
    │                                                           kind: :npc_speech}
    │                                                           and
    │                                                           %BehaviorUtterance{
    │                                                           kind: :room_speech}.
    │                                                           Each appends the
    │                                                           appropriate log
    │                                                           entry (:npc_speech
    │                                                           or :room_speech
    │                                                           kind) to the
    │                                                           socket assigns.
    └── components/
        └── game_components.ex                       # MODIFIED — ADD
                                                                log_entry/1
                                                                clauses for
                                                                kind: :npc_speech
                                                                (renders
                                                                <who> says,
                                                                "<text>" with
                                                                speech-npc class)
                                                                and
                                                                kind: :room_speech
                                                                (renders the text
                                                                italicized with
                                                                narrate-room
                                                                class, NO
                                                                attribution).

test/
├── agenticrealms/
│   └── world/
│       ├── behaviors/
│       │   ├── validator_test.exs                  # NEW — shape validation
│       │   │                                                tests: unknown trigger,
│       │   │                                                unknown action,
│       │   │                                                empty text, over-cap
│       │   │                                                text, nested wrong
│       │   │                                                types, happy paths.
│       │   └── interpreter_test.exs                # NEW — direct handler
│       │                                                  invocation tests.
│       │                                                  Setup: insert
│       │                                                  rooms/clones/blueprints
│       │                                                  via Repo.insert! (no
│       │                                                  Commanded), call
│       │                                                  Interpreter.handle/2
│       │                                                  with synthesized
│       │                                                  PlayerSpawned /
│       │                                                  PlayerMoved structs,
│       │                                                  subscribe to player
│       │                                                  topics, assert the
│       │                                                  expected
│       │                                                  BehaviorUtterance
│       │                                                  messages arrive in
│       │                                                  expected order.
│       │                                                  Cases: empty
│       │                                                  behaviors (no-op),
│       │                                                  single say, multi-
│       │                                                  behavior order,
│       │                                                  multi-action order,
│       │                                                  room-first NPC-second
│       │                                                  order, room-speech to
│       │                                                  triggering player
│       │                                                  only, npc-speech to
│       │                                                  triggering player +
│       │                                                  others, no firing for
│       │                                                  empty rooms.
│       ├── npc_blueprint_test.exs                   # MODIFIED — extend
│       │                                                       CreateNPCBlueprint
│       │                                                       happy-path test
│       │                                                       to assert
│       │                                                       behaviors are
│       │                                                       carried through;
│       │                                                       extend
│       │                                                       SpawnNPCClone
│       │                                                       happy-path test
│       │                                                       to assert the
│       │                                                       blueprint's
│       │                                                       behaviors are
│       │                                                       stamped into the
│       │                                                       emitted event
│       │                                                       payload.
│       └── projections/
│           └── world_projector_npc_replay_test.exs # MODIFIED — verify the
│                                                              behaviors column
│                                                              is populated for
│                                                              new events AND
│                                                              defaults to []
│                                                              for legacy
│                                                              NPCSpawnedInRoom
│                                                              events.
└── agenticrealms_web/
    └── live/
        └── game_live_behaviors_test.exs             # NEW — comprehensive
                                                              integration test
                                                              covering all 5
                                                              user stories.
                                                              ConnCase, async:
                                                              false, tagged
                                                              :integration. Same
                                                              pattern as the
                                                              feature 007/008
                                                              integration test
                                                              (one test, many
                                                              acceptance
                                                              scenarios in
                                                              sequence).
```

**Structure Decision**: The behavior system slots cleanly into the existing project layout. The new `World.Behaviors` namespace gets three modules (`Validator`, `Interpreter`, `ActionExecutor`) and lives under `lib/agenticrealms/world/behaviors/`. The `Validator` is pure and unit-testable; the `Interpreter` is a Commanded handler subscribed to existing domain events; the `ActionExecutor` is the per-action logic (currently `:say` only — future actions add clauses).

Behavior storage rides on the existing read-model tables via three new JSONB columns. The migration is small (3 columns, 3 default values). The existing `NPCBlueprint` aggregate and `WorldProjector` grow narrowly to carry behaviors through the dispatch → event → projection pipeline.

The two new log-entry kinds (`:npc_speech`, `:room_speech`) integrate into `GameComponents` as additional clauses on the existing `log_entry/1` function. No new render module needed.

Critically, **no new domain events are introduced.** The feature relies entirely on existing `PlayerSpawned` / `PlayerMoved` events as triggers and on new transient `BehaviorUtterance` UI events as outputs. This matches feature 004's non-event-sourced posture and is the architectural commitment from the spec's FR-016 / FR-016a / Assumptions.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No violations. The new modules and schema columns are the minimum surface needed:

| Decision | Why it's the simplest viable answer |
|---|---|
| Behaviors stored as JSONB, not a separate table | The behavior list is small (~3 entries per entity), always accessed together with its parent entity, and never queried by content. A separate table would add 3 joins per trigger event for zero gain. |
| Three behavior columns (blueprint, clone, room), not one polymorphic table | Polymorphism would require a `behavior_owner_type` discriminator + an FK that's actually three different references. The 3-column approach is simpler, faster, and matches the three distinct attach surfaces directly. |
| `start_from: :current` for the interpreter, not a "live mode" flag | `start_from: :current` is built into Commanded's handler config. A custom flag would require manual gating in every `handle/2` clause and an external coordination signal — strictly more code for the same effect. |
| Player-topic delivery (not room-topic) for behavior utterances | Room-topic can't express triggering-player-only delivery for `:room_speech`, AND can't reliably deliver to the moving player around their unsubscribe/subscribe transitions. Player-topic is always-subscribed-on-mount, which is bulletproof. |
| FR-017a relaxation (post-destination ordering for `player_left`) | The narrative ideal ("see the goodbye as you leave") would require pre-dispatch behavior firing in the LiveView handler, coupling the interpreter to the LiveView path. Keeping the interpreter as a pure event handler is worth the slightly-imperfect ordering. The leaving player still receives the goodbye (FR-017 honored). |
| Adding `:behaviors` field to existing events (rather than new event types) | An event-shape extension with a defaulted optional field is backward-compatible (existing events deserialize with `behaviors: []`); inventing a sibling event would mean two emission paths and two projector handlers for one concept. The defaulted field is the simpler answer. |
| Room behaviors stored on `world_rooms` directly (not via a room blueprint) | Feature 008 deferred room blueprints. Adding one now would expand scope substantially. The room row + a JSONB column is the minimum surface. If a future feature introduces room blueprints with clone-style separation, room behaviors can migrate; not anticipated yet. |
