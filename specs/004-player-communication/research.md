# Phase 0 Research — Player Communication

All `[NEEDS CLARIFICATION]` markers in spec.md were resolved during `/speckit-clarify` (Session 2026-05-19). This document captures the remaining technical decisions — the ones that don't rise to the level of a spec clarification but still need a recorded choice before tasks can be cut.

---

## 1. Transport: existing `Phoenix.PubSub` vs. anything new

**Decision**: Use the same `AgenticRealms.PubSub` and the same topic strings (`room:<id>`, `player:<id>`) that feature 003 already established.

**Rationale**: Feature 003 already wired this up — `GameLive` subscribes to both topics on mount, the `World` facade module exposes `room_topic/1` and `player_topic/1`, and the witness UI events (`RoomObjectTaken`, `RoomPlayerArrived`, etc.) are delivered on these topics. Reusing the topics means the only LiveView change is new `handle_info/2` clauses pattern-matching on the new structs.

**Alternatives considered**:

- Per-utterance ad-hoc topics like `chat:room:<id>`. Rejected: pure duplication; no reason to split the namespace.
- A separate `Communication.PubSub` instance. Rejected: gratuitous infrastructure for zero benefit at this scale.
- Phoenix Channels (raw, not via PubSub). Rejected: LiveView already encapsulates the WS transport; layering Channels alongside it would split the delivery path.

---

## 2. No Commanded involvement (no commands, no events, no aggregates)

**Decision**: Communication is a non-event-sourced concern. The `World.Commands` facade is untouched; no new modules under `World.Commands/`, `World.Events/`, `World.Projections/`. There is no `Communication` aggregate.

**Rationale**: FR-022 (clarified) makes utterances transient — they're delivered and gone. Putting them through Commanded would mean writing to the event store, generating projections, and persisting payloads we've explicitly chosen not to retain. The "natural fit" pattern in this codebase for transient real-time signals is the existing `UIEvents` model: plain structs broadcast on PubSub. Communication slots cleanly into that pattern.

**Implication for race conditions**: There are no inter-aggregate races to serialize. Two players in the same room saying things at the same time produce two PubSub messages — order is determined by `Phoenix.PubSub`'s FIFO delivery per subscriber, which is sufficient for log ordering.

**Alternatives considered**:

- A `Communication` aggregate that emits `Spoken`, `Emoted`, `Told`, `Whispered` events into the event store. Rejected: contradicts FR-022 (would either persist what the spec says is transient, or burn an event-store stream on data we throw away — also expensive at scale if chat volume grew).
- A `say` command on the existing `World.Room` aggregate (with no resulting event). Rejected: aggregates by convention emit events; a command that produces nothing fights the framework.

---

## 3. Parser case handling — preserve case in `<text>`

**Decision**: Refactor `CommandParser.parse/1` so that the verb match is performed on a downcased copy of the first word, while the *rest* of the trimmed input (preserving its original casing) is what gets returned in the sentinel for communication verbs. Existing world-verb sentinels (`{:take, name}`, `{:drop, name}`) keep their current lowercased payload because `Queries.resolve_object_in_room/2` and `Queries.resolve_object_in_inventory/2` depend on lowercased lookup at the call site.

**Rationale**: The current parser does `downcased = String.downcase(trimmed)` and parses against `downcased` everywhere. This works for verbs whose argument is a name we want to lookup (objects), but it destroys user-typed speech text. Changing the parser to expose both `downcased_first_word` and `original_rest` is a small, local change — adds one branch for communication verbs, leaves the existing branches untouched.

**Alternatives considered**:

- Lowercase the verb only; preserve case throughout. Would require updating `Queries.resolve_object_in_room/2` to lowercase its argument internally. Cleaner long-term, but out of scope for this feature.
- Re-parse the original string after detecting a communication verb. Awkward and double-work.

---

## 4. Apostrophe (`'`) and colon (`:`) shortcuts

**Decision**: Detect at the start of trimmed input. If the trimmed input begins with `'` (apostrophe) and has at least one character after, treat as `say <rest>`. If it begins with `:` and has at least one character after, treat as `emote <rest>`. No space is required after the prefix character (e.g., `'hello` is valid; `' hello` is also valid — leading whitespace in the captured text is trimmed by the communication facade).

**Rationale**: MUD convention; matches common player muscle memory. Detecting prefix-char shortcuts before doing word-split keeps the verb table clean.

**Edge cases handled**:

- `'` alone (just the apostrophe) → falls through to the empty/refusal path because there's no text content.
- `'   ` (apostrophe + only whitespace) → same.
- `:bows` → emote with text "bows".
- Single colon `:` → falls through.
- A normal verb that happens to contain a colon (none exist today; future verbs should avoid leading `:`).

---

## 5. Recipient resolution query

**Decision**: A single Ecto query per `tell`/`whisper` invocation:

```elixir
from(p in AgenticRealms.Accounts.Player,
  where: fragment("LOWER(?) = LOWER(?)", p.username, ^name),
  select: %{id: p.id, username: p.username}
)
|> AgenticRealms.Repo.all()
```

- `[]` → `{:error, :not_found}`
- `[%{id: id} = player]` where `id == sender_id` → `{:error, :self_target}`
- `[player]` → `{:ok, player}`
- `[_ | _]` → `{:error, :ambiguous}`

**Rationale**: Pre-clarification, ambiguity was theoretical. Concretely, `AgenticRealms.Accounts.Player` enforces only case-sensitive uniqueness on username (per `unique_constraint(:username)` in `player.ex:65`), so a "user1" and "User1" coexist legally. The ambiguity refusal is a real path, not a hypothetical one.

**Alternatives considered**:

- Add a case-insensitive unique index on `players.username` in this feature. Rejected: out of scope — that's an Accounts-context change with its own migration path, and the spec already mandates ambiguity-refuse, which works whether or not the underlying schema is reformed.
- Add a `Repo.one/2` with `LIMIT 2` and special-case the count. Equivalent functionally; `Repo.all/1` is cleaner here for a small expected result set.

---

## 6. Offline tell detection via `Phoenix.Presence`

**Decision**: After successful recipient resolution but before broadcasting, query `AgenticRealmsWeb.Presence` for the recipient. If the recipient has zero tracked sessions, return `{:error, :not_deliverable}` (mapped to FR-016's neutral refusal at the LiveView layer).

```elixir
case Presence.get_by_key(Presence.topic(), Integer.to_string(recipient_id)) do
  %{metas: []} -> :offline
  %{metas: [_ | _]} -> :online
  _ -> :offline
end
```

**Rationale**: `Presence` is already running and already tracks every LiveView session. No new state, no extra ETS table. The check is cheap (ETS lookup). It runs only for `tell`; `whisper` doesn't need it because the room-occupancy check (FR-020) already implies the recipient has at least one session in the sender's room.

**Caveat (already documented as the edge case in spec)**: A recipient session can disconnect between the Presence check and the PubSub broadcast. That's harmless under the transient model — the dropped session just doesn't process the message; the sender already received their confirmation. We do NOT chase the recipient to refuse retroactively (FR-016: best-effort, no retry).

**Alternatives considered**:

- Broadcast first, then "ack" via Presence. Adds round-trip latency for no win.
- Maintain a separate online-set in ETS or GenServer. Rejected: duplicates what Presence already provides.

---

## 7. Multi-session delivery: actor exclusion and self-session targeting

**Decision**: To deliver the actor-side confirmation to *only* the originating session (and not the actor's other sessions), put the confirmation log-entry append **inline in `GameLive.handle_event("submit_command", ...)`** rather than broadcasting it. The broadcast goes only to *witnesses* (room subscribers other than the actor for `say`; all room subscribers including the actor for `emote`; recipient sessions for `tell`/`whisper`).

For `say`, the broadcast goes to all room subscribers (including the actor's other tabs); the actor's *originating* session gets the actor-side confirmation inline, and its `handle_info/2` for the broadcast filters out any `RoomUtterance` whose `actor_session_id` matches its own self-tracked session id.

**Self-session id**: assigned at mount time as a unique reference (`make_ref/0` or a fresh UUID-like value) and held in the socket assigns as `:session_id`. Included on every broadcast struct. LiveView's `handle_info/2` for `say` discards the event when `event.actor_session_id == socket.assigns.session_id`.

**Rationale**: Mirrors 003's actor-side / witness-side multi-session pattern (003 spec Clarifications Q5). The 003 implementation puts actor-side log entries inline in the handler that processed the command and never broadcasts them — exactly the model adopted here.

**Alternatives considered**:

- Filter by `player_id` instead of `session_id`. Rejected: that's what the actor-exclusion-via-player-id approach would do, but it would prevent the actor's *other* sessions in the same room from seeing a `say` as a witness, which contradicts FR-006 / Acceptance Scenario 5 of US1.
- Per-session topics. Rejected: PubSub doesn't need that granularity; a session-id field on the message body is sufficient.

---

## 8. Tell echo behavior for actor's other sessions

**Decision**: `tell`'s sender broadcasts on `player:<recipient_id>` (not the sender's own player topic). The originating session appends the actor-side confirmation inline. The sender's other sessions therefore receive nothing — neither a broadcast (they're not subscribed to the recipient's topic) nor an inline append (they're a different LiveView process).

**Rationale**: Per spec US3 Acceptance Scenario 5: *"A's session 1 sees the confirmation, A's session 2 sees nothing."* This decision realizes that scenario at zero cost — it falls out of choosing the recipient's topic as the broadcast target.

**Symmetry with whisper**: For `whisper`, the sender's other sessions in the same room would *also* see the broadcast on the room topic. We need them to NOT see the whisper (FR-018 covers only the originating session). The filter rule is: in `handle_info/2` for `PrivateUtterance` of `kind: :whisper`, drop unless `socket.assigns.current_player.id == event.recipient_id`. That filter naturally excludes the sender's other sessions (their `current_player.id == sender_id`, not `recipient_id`).

---

## 9. HTML escaping (FR-024)

**Decision**: Rely on HEEx auto-escaping in the rendered log-entry components. Pass utterance text as a plain `String.t()` through the entire pipeline (parser → facade → UIEvents struct → handle_info → log-entry assign → template), and let HEEx's default `{ @text }` interpolation handle escaping at render time.

**Rationale**: HEEx escapes string interpolations by default (only `raw/1` opts out). The `game_components.ex` is HEEx-based; no special handling needed at any earlier layer.

**Test guard**: A unit test in `game_live_communication_test.exs` will submit a `say` containing `<script>alert(1)</script>` and assert the rendered DOM contains the escaped text, not a `<script>` element.

---

## 10. Per-utterance length cap enforcement point

**Decision**: Enforce the 500-char cap in `World.Communication` (the facade), AFTER trimming, BEFORE broadcasting. The parser does not enforce it.

**Rationale**: Keeping the cap in the facade gives a single source of truth for the rule (FR-026), and means the cap applies uniformly whether the verb came in via parser sentinel, slash-command, or any future programmatic caller. The parser stays purely lexical.

**HTML-level guard**: The chat input element MAY set `maxlength="500"` as a UX nicety, but the server enforcement is authoritative.

---

## 11. Test strategy

**Decision**: Three layers, matching the 003 pattern.

| Layer | File | What it covers |
|-------|------|----------------|
| Unit (parser) | `test/agenticrealms/world/command_parser_test.exs` (existing — modified) | Each new verb and alias produces the right sentinel; case-preservation in `<text>`; apostrophe/colon shortcuts; empty/whitespace; whitespace between verb and arg; recipient token splitting (`tell alice hi mom` → recipient `"alice"`, text `"hi mom"`) |
| Unit (facade) | `test/agenticrealms/world/communication_test.exs` (new) | For each verb: empty refusal, over-length refusal, self-target refusal, ambiguous recipient refusal, not-found recipient refusal, offline-tell refusal, successful broadcast asserted via `Phoenix.PubSub.subscribe/2` in the test process; whisper room-scope refusal |
| Integration (LiveView) | `test/agenticrealms_web/live/game_live_communication_test.exs` (new) | Multi-session: two `live_isolated`'d players in the same room, `say`/`emote`/`whisper` flow; two players in different rooms for `tell`; actor's two-tab visibility (US1 scenario 5); recipient's two-tab visibility (US3 scenario 5); HTML escape test |

ExUnit `async: true` is fine for the unit tests; the LiveView tests run synchronously (per the existing 003 LiveView test conventions) because they share the world seed.

**No fixture data needed**: communication doesn't touch the world write side, so the existing `Seed.run/0` is sufficient — tests can spawn two players into the seeded starter room.

---

## 12. Open items deferred to planning / implementation

- **Rate limiting**: deferred per Edge Cases. v1 has none. If we add one later, the natural place is a token-bucket check at the top of each `World.Communication` function, sourced from a per-player ETS entry. No design work needed now.
- **`who` command**: out of scope; future feature. Mentioned in the spec assumptions only as the natural place to expose presence info already used by FR-016.
- **Visual styling of new log-entry kinds**: deferred to the LiveView/components implementation step. FR-025 mandates distinguishability; concrete colors/typography are not spec-level.

No remaining `[NEEDS CLARIFICATION]` items. Ready for Phase 1.
