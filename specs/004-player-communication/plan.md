# Implementation Plan: Player Communication — Say, Emote, Tell, Whisper

**Branch**: `004-player-communication` | **Date**: 2026-05-19 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/004-player-communication/spec.md`

## Summary

Add four communication verbs — `say`, `emote`, `tell`, `whisper` — on top of the persisted world built in feature 003. None of them mutate world state, so the design avoids the Commanded write side entirely: no commands, no aggregates, no domain events, no projections. Communication is a thin module that resolves a recipient (for tell/whisper), validates the input, and **broadcasts directly on existing `Phoenix.PubSub` topics** — `room:<id>` for say/emote/whisper, `player:<id>` for tell. Witness LiveViews already subscribe to those topics from feature 003; this feature only adds new `UIEvents.*` struct kinds, the matching `handle_info/2` clauses in `GameLive`, and new sentinels in `CommandParser`.

**Per-clarification design decisions** (Session 2026-05-19):

- **Transient only** (FR-022) → no event store, no Ecto schema, no projection. Communication leaves zero artifacts behind once delivered.
- **Case-insensitive exact recipient match** (FR-010) → a single `Repo.one/2` query with `where: fragment("LOWER(username) = LOWER(?)", ^name)`; multiple matches refused as `:ambiguous` (a real possibility — `Accounts.Player` enforces only case-sensitive uniqueness).
- **Neutral "could not be delivered" for offline tells** (FR-016) → resolved-but-not-tracked-in-`Presence` produces a uniform refusal that leaks no presence info.
- **500-character cap, refuse on overflow** (FR-026) → enforced once in the communication facade after trimming; never silent truncation.
- **Self-target refused** (FR-010a) → resolution returns `{:error, :self_target}` when `resolved_id == sender_id`; the same refusal path covers both verbs.

**Topic routing summary**:

| Verb     | Broadcast topic           | Recipient filter in LiveView                 | Actor exclusion |
|----------|---------------------------|----------------------------------------------|-----------------|
| `say`    | `room:<sender_room_id>`   | none (all subscribers see it)                | actor's session excluded by sender_session_id |
| `emote`  | `room:<sender_room_id>`   | none                                          | actor's session **included** (FR-008) |
| `whisper`| `room:<sender_room_id>`   | `recipient_id == current_player_id`           | non-recipients silently ignore |
| `tell`   | `player:<recipient_id>`   | none (only recipient's sessions subscribe)    | sender's other sessions do **not** receive |

Tell deliberately uses `player:<recipient_id>` (not `player:<sender_id>`) so that delivery reaches every session of the recipient regardless of room, and sender's own sessions don't receive an echo (they get the actor-side confirmation from the originating LiveView only). Whisper is broadcast on the room topic but carries `recipient_id`, and `GameLive.handle_info/2` simply drops the event if its own `current_player.id` is not the recipient.

## Technical Context

**Language/Version**: Elixir 1.15+ / Erlang OTP 26+ (unchanged from 003)
**Primary Dependencies**: Phoenix 1.8.5, Phoenix LiveView 1.1.0, `phoenix_pubsub` (already in use via 003), Phoenix.Presence (already in use, will be queried for tell-recipient online status), Ecto 3.13 (read-only — `Accounts.Player` lookup for case-insensitive username resolution). **No new dependencies.**
**Storage**: None new. Communication writes nothing. The only DB touch is a single read query against `players` per `tell`/`whisper` invocation for recipient resolution.
**Testing**: ExUnit (parser unit tests, communication facade unit tests with `Phoenix.PubSub`-only assertions, `Phoenix.LiveViewTest` for multi-session integration). No aggregate test helpers needed; no event-store fixtures.
**Target Platform**: Web browser (desktop only — unchanged scope from 001/002/003)
**Project Type**: Web application (Phoenix LiveView monolith)
**Performance Goals**: SC-001 — same-room recipients see `say`/`emote` within 100 ms p95 (matches 003's witness latency target). Implicit but equivalent target for `tell` cross-room delivery.
**Constraints**: No persistence, no retry on delivery failure (best-effort PubSub per FR-016 + FR-022), all utterance text HTML-escaped on render (FR-024), 500-char cap (FR-026), no per-player rate limit in v1 (Edge Cases — deferred).
**Scale/Scope**: Same as 003 — a handful of concurrent players, starter map of ~5 rooms. PubSub fan-out cost is negligible at this scale.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The project constitution file (`.specify/memory/constitution.md`) is the unfilled template — no concrete principles ratified. No gates to enforce. Proceeding (same posture as 003).

**Post-Phase 1 re-check**: No violations. This feature explicitly *avoids* introducing new architectural patterns (no Commanded usage, no Ecto schema, no migration); it reuses 003's `Phoenix.PubSub` substrate and `World.UIEvents` struct convention. The only meaningfully new module is `World.Communication`, a small facade for verb handling.

## Project Structure

### Documentation (this feature)

```text
specs/004-player-communication/
├── plan.md                  # This file (/speckit-plan output)
├── spec.md                  # Feature specification (clarified)
├── research.md              # Phase 0: technical decisions & alternatives considered
├── data-model.md            # Phase 1: utterance struct shapes (transient, no DB)
├── quickstart.md            # Phase 1: dev setup, manual test walkthrough
├── contracts/
│   ├── ui_events.md         # Phase 1: new UIEvents struct contracts + topic routing
│   ├── parser.md            # Phase 1: text-input grammar additions → command sentinels
│   └── communication_api.md # Phase 1: World.Communication public function contracts
└── checklists/              # (Optional, not generated by /speckit-plan)
```

### Source Code (repository root)

```text
lib/
├── agenticrealms/
│   └── world/
│       ├── ui_events.ex                 # MODIFIED — add RoomUtterance + PrivateUtterance structs
│       ├── command_parser.ex            # MODIFIED — add say/emote/tell/whisper sentinels;
│       │                                  preserve case in the <text> argument for new verbs
│       ├── communication.ex             # NEW — public facade: say/2, emote/2, tell/3, whisper/3
│       └── communication/               # NEW — internal helpers (kept small; may collapse into communication.ex)
│           └── recipient_resolver.ex    # NEW — case-insensitive username lookup w/ ambiguity refusal
└── agenticrealms_web/
    ├── components/
    │   └── game_components.ex           # MODIFIED — new log_entry clauses for :speech, :emote_action,
    │                                      :private_tell_in, :private_whisper_in, :private_tell_out,
    │                                      :private_whisper_out, :refusal kinds (FR-025)
    └── live/
        ├── game_live.ex                 # MODIFIED — new submit_command branches for the four verbs;
        │                                  new handle_info clauses for RoomUtterance + PrivateUtterance
        └── game_live.html.heex          # MINIMAL CHANGE — renders new log kinds via game_components

test/
├── agenticrealms/
│   └── world/
│       ├── command_parser_test.exs      # MODIFIED — new cases for say/emote/tell/whisper + edge cases
│       ├── communication_test.exs       # NEW — facade unit tests with PubSub assertions
│       └── communication/
│           └── recipient_resolver_test.exs  # NEW — exact match, ambiguity, self, not-found
└── agenticrealms_web/
    └── live/
        └── game_live_communication_test.exs   # NEW — end-to-end multi-session, multi-room tests
                                                  covering all four verbs and refusal paths
```

**Structure Decision**: A new `World.Communication` module owns the entire communication concern. It is intentionally not part of `World.Commands` (which is the Commanded write-side facade) — there are no commands or events for communication. The `command_parser.ex` change is additive; existing world verbs are not affected. No new migrations, no `application.ex` changes, no supervision-tree additions.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No violations. (Constitution is the unfilled template; this feature reuses existing infrastructure rather than adding to it.)
