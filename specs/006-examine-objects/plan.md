# Implementation Plan: Examine Objects and Players

**Branch**: `006-examine-objects` | **Date**: 2026-05-21 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/006-examine-objects/spec.md`

## Summary

Extend the existing `look` command to accept an optional target, resolve that target against the player's visible scope (objects in the current room, objects in their inventory, players in the current room — including themselves), and append a new `:detail` log entry. For objects the entry shows the `long_description` field that has been persisted on every Game Object since feature 003 but has so far had no in-game way to surface. For players the entry shows the deliberately minimal placeholder `<display-name> is a player.`, leaving headroom for later features to enrich.

**Load-bearing design decisions**:

- **Pure read feature**. No new event types, no new aggregates, no migrations. The data already exists — `Object.long_description` is populated by every `PlaceObject` command (see `Seed.run/0`), and Phoenix.Presence + `Queries.other_occupants_of/2` already provide the visible-player set. The implementation is one new query facade + one new log-entry kind + one parser change + one tool-definition tweak.
- **New module `World.Examine`** sits alongside `World.Queries` rather than inside it. The target-resolution logic (FR-006a's three-tier precedence — exact > partial, inventory > room, object/player ties → refuse) is meaty enough to deserve its own file and its own unit-test surface; collapsing it into `Queries` would crowd that module and entangle two different kinds of "read" (raw lookups vs. policy-laden disambiguation). The module is pure: takes `player_id` + `target_string`, returns `{:ok, %Examine.Match{...}} | {:error, reason}`, and never raises.
- **Parser sentinel split**: `{:look}` (no target — existing behavior, unchanged) vs. `{:look, target}` (new). The split is deliberate: nothing in the existing `look`-with-no-target handler changes, so SC-003's "no measurable latency on commands that the fast parser already handles" comes for free.
- **AI resolver evolution, not replacement**: the existing `look` tool in `World.IntentResolver.Tools` gains an optional `target` property; the system prompt and few-shot examples flip from refusal-on-examine to mapping examine/inspect/study/read → `look` with target. The resolver's outcome union also gains `{:look, target}` — but `to_action/2` already routes by tool name, so the only meaningful change is teaching the model to USE the new shape via the system prompt. This is a one-shot prompt + tool-schema change; no resolver-architecture rewrite.
- **Inherits feature 005a's fallback-loop guard**: `handle_look_target/4` takes the same `allow_fallback?` parameter `handle_take`/`handle_drop` use. A fast-parsed `look <target>` whose target doesn't resolve falls through to the LLM resolver on the first attempt (so loose phrasing like `look the lantern with the dent` reaches the AI); on an LLM-dispatched retry the same failure simply refuses — no resolver loop, no infinite recursion.
- **Render path stays HEEx-only**: a new `log_entry/1` clause for `kind: :detail` renders the object's long description (auto-escaped) or the placeholder player line. No CSS spelunking required beyond a new `.log-entry.detail` rule paralleling `.log-entry.room`.
- **No broadcasts**: examination is observably private (SC-005). No PubSub send, no UIEvent struct, no witness entries for room peers. The persisted world is untouched.

**Per-spec design**:

- **Disambiguation precedence** (FR-006a) is implemented as a single function with three explicit stages: (1) exact case-insensitive matches across all three scopes, (2) inventory-over-room tiebreak only when remaining matches are all objects, (3) clarification refusal whenever a mixed-kind tie (one object + one player) or an unbroken multi-match remains. Partial / substring matching is the fallback when no exact match exists at all — matching the existing convention for take/drop name resolution.
- **Self-examination** (FR-005a in spec — `look <self-name>` / `look me` / `look self`) is supported. The Examine module receives the acting player_id and treats the acting player as part of the visible player scope. `me` and `self` are mapped to the acting player's username via a parser-level alias check that runs only inside the `look <target>` arm — no other command honors `me`/`self`, so the alias stays narrowly scoped.
- **Offline-player filtering** (spec edge-case + feature 003a inheritance): the Examine module's "visible players in this room" query reuses `Queries.other_occupants_of/2` and the acting player themselves. Since `other_occupants_of` already applies the Presence filter (see `lib/agenticrealms/world/queries.ex:163-172`), offline players are excluded by construction — no special-case logic added.

## Technical Context

**Language/Version**: Elixir 1.15+ / Erlang OTP 26+ (unchanged from 003/004/005)
**Primary Dependencies**: Existing only — Phoenix 1.8.5, Phoenix LiveView 1.1.0, `phoenix_pubsub`, `jason`, `ecto`, `req` (from 005). No new runtime deps.
**External Service**: Anthropic Messages API (unchanged — same endpoint, same model `claude-haiku-4-5-20251001`, same auth + caching strategy). Only the system prompt content and the `look` tool's `input_schema` change.
**Storage**: PostgreSQL via existing `world_objects` / `world_rooms` / `player_states` / `account_players` tables. No new migrations, no schema changes. `Object.long_description` is already populated for every seeded object.
**Testing**: ExUnit. Four layers — (1) `CommandParser` unit tests for the new `{:look, target}` sentinel, (2) `World.Examine` unit tests against a seeded fixture (real Repo via the existing test sandbox), (3) `IntentResolver.Tools` structural test confirming the `look` tool's new optional `target` property, (4) LiveView integration test for the end-to-end flow (fast-path examine of room object, examine of inventory object, examine of other player, examine of self, refusal for missing target, LLM-fallback via mocked resolver for natural-language phrasings).
**Target Platform**: Web browser (desktop, unchanged).
**Project Type**: Phoenix LiveView monolith (unchanged).

**Performance Goals**:
- SC-003 — canonical `look <target>` under 50ms p99. The query path is three small indexed reads (`PlayerState` by `player_id`, `world_objects` by `room_id`, `world_objects` by `player_id`) plus an in-memory username comparison against the room's occupant list. Comfortably under budget.
- SC-002 — 95% of natural-language examine phrasings resolve correctly within 1s end-to-end. Inherits from feature 005's resolver path (Haiku + ephemeral cache marker, ~300–800ms typical) — unchanged latency profile.

**Constraints**:
- The change to the `look` tool's `input_schema` (adding `target` as an optional property) invalidates the 5-minute ephemeral prompt cache on first deploy. The next request after deploy pays one uncached invocation; subsequent requests warm the cache normally. Same posture as 005's system-prompt changes.
- 500-character input cap (FR-017 in 005) continues to apply to the entire player input, including the target argument.
- No-broadcast contract is strict — SC-005 is verified by a parallel-session LiveView integration test ensuring the witness session sees zero log entries when its peer examines anything.

**Scale/Scope**:
- Same as 003/004/005 — handful of concurrent players, starter map with 3 rooms and 3 objects.
- One new log-entry kind, one new parser sentinel, one new pure module (~120 LOC estimated), one updated tool definition, one updated system prompt, one extended LiveView handler. ~400 LOC of production code total + tests.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The project constitution (`.specify/memory/constitution.md`) is the unfilled template — no concrete principles ratified. No gates to enforce. Proceeding (same posture as 003 / 004 / 005).

**Post-Phase 1 re-check**: No violations. The feature adds one narrow new module (`World.Examine`), reuses every existing data path (`Queries`, `Object` schema, `Presence`, `IntentResolver`), and introduces no new infrastructure (no migrations, no supervisors, no PubSub topics, no external services). No CLAUDE.md / constitution conflict.

## Project Structure

### Documentation (this feature)

```text
specs/006-examine-objects/
├── plan.md                  # This file (/speckit-plan output)
├── spec.md                  # Feature specification (validated; no clarifications)
├── research.md              # Phase 0: target-resolution algorithm, tool schema design,
│                            #          system-prompt diff, log-entry kind choice
├── data-model.md            # Phase 1: Examine.Match struct shape, target-resolution
│                            #          decision tree (FR-006a), :detail log-entry shape
├── quickstart.md            # Phase 1: how to manually verify each user story end-to-end
│                            #          against the seeded starter map
├── contracts/
│   ├── examine_api.md       # Phase 1: World.Examine public function contract
│   ├── parser.md            # Phase 1: CommandParser `{:look, target}` extension
│   ├── tools.md             # Phase 1: updated `look` tool definition (optional target)
│   ├── system_prompt.md     # Phase 1: system-prompt diff + new few-shot examples
│   └── ui_events.md         # Phase 1: new :detail log-entry kind (none broadcast)
└── checklists/
    └── requirements.md      # (Already created by /speckit-specify)
```

### Source Code (repository root)

```text
lib/
├── agenticrealms/
│   └── world/
│       ├── command_parser.ex                    # MODIFIED — `look [target]` arm now
│       │                                                   returns {:look} when target
│       │                                                   absent, {:look, normalized_target}
│       │                                                   when present. Also handles
│       │                                                   `me` / `self` alias mapping
│       │                                                   to the acting player's name
│       │                                                   (passed through unchanged at
│       │                                                   parse time; resolved in
│       │                                                   Examine using player_id).
│       ├── examine.ex                           # NEW — public facade `examine/2`.
│       │                                                Owns target resolution per
│       │                                                FR-005, FR-006, FR-006a, FR-007.
│       │                                                Returns Examine.Match or error.
│       ├── examine/
│       │   └── match.ex                         # NEW — Examine.Match struct
│       │                                                (target_kind: :object | :player,
│       │                                                 name, long_description?).
│       └── intent_resolver/
│           ├── tools.ex                         # MODIFIED — `look` tool gains optional
│           │                                                `target` property in its
│           │                                                input_schema.
│           └── (system_prompt.ex unchanged — content is in priv/)
└── agenticrealms_web/
    ├── live/
    │   └── game_live.ex                          # MODIFIED — `{:look, target}` parser
    │                                                       arm routes to new
    │                                                       handle_look_target/4
    │                                                       (with allow_fallback? = true
    │                                                       on the fast path, false from
    │                                                       dispatch_resolved_action/3).
    └── components/
        └── game_components.ex                    # MODIFIED — new log_entry/1 clause
                                                            for kind: :detail (object
                                                            and player render branches).

priv/
└── intent_resolver/
    └── system_prompt.md                          # MODIFIED — examine/inspect/study/read
                                                   now map to `look` with target; new
                                                   examples 10–12 cover object / inventory
                                                   / player examination; the "DO NOT
                                                   substitute look" reminder is REMOVED
                                                   (it is now precisely the wrong rule).

test/
├── agenticrealms/
│   └── world/
│       ├── command_parser_test.exs               # MODIFIED — new tests for
│       │                                                   {:look, target} parsing,
│       │                                                   `me` / `self` aliasing,
│       │                                                   case/whitespace handling.
│       ├── examine_test.exs                      # NEW — object in room, object in
│       │                                                inventory, player in room, self,
│       │                                                offline player, exact match,
│       │                                                partial match, ambiguous match,
│       │                                                inventory-over-room precedence,
│       │                                                mixed object/player exact tie
│       │                                                → refuse, no current room.
│       └── intent_resolver/
│           └── tools_test.exs                    # MODIFIED — assert `look` tool
│                                                            schema has an optional
│                                                            `target` property; existing
│                                                            tool count / names unchanged.
└── agenticrealms_web/
    └── live/
        ├── game_live_examine_test.exs            # NEW — LiveView integration. Fast-path
        │                                                examine of room object, examine
        │                                                of inventory object, examine of
        │                                                another player, examine of self,
        │                                                refusal for unseen target,
        │                                                detail-entry rendering shape.
        └── game_live_intent_parser_test.exs      # MODIFIED — add coverage for
                                                            natural-language examine
                                                            phrasings resolving via LLM
                                                            fallback to {:look, target};
                                                            offline-player examine refusal.
```

**Structure Decision**: New `World.Examine` module is a pure read-side facade that parallels `World.Queries` (raw reads) and `World.Communication` (non-event-sourced actions). It explicitly does NOT live inside `Queries` because the target-resolution policy in FR-006a is non-trivial — keeping it isolated buys an unencumbered unit-test surface and a single answer to the "where does this lookup live?" question for future features that examine non-canonical entity types (NPCs, exits, items-of-items). The module composes existing reads (`Queries.look_room/1`, `Queries.list_inventory/1`) rather than re-implementing them; no behavior in `Queries` changes.

The IntentResolver gets one narrowly-scoped change — the `look` tool schema and the system prompt. The resolver's response-parsing code (`IntentResolver.to_action/2`) already returns `{:ok, {:look}}` for the no-target case; adding a clause `to_action("look", %{"target" => t})` for the target case completes the wiring on the parsing side. `GameLive.dispatch_resolved_action/3` gains the new `{:look, target}` arm parallel to the existing `{:look}` arm.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No violations. The new module (`World.Examine`) is the minimum surface needed to encapsulate FR-006a's disambiguation precedence in one testable place — collapsing it into `Queries` would muddle that module's "raw read" semantics. The new log-entry kind (`:detail`) is required by FR-003 (visual / structural distinction from room view). No alternatives offer a smaller footprint.
