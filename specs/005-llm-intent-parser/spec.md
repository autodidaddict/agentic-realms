# Feature Specification: Natural-Language Player Commands

**Feature Branch**: `005-llm-intent-parser`
**Created**: 2026-05-19
**Status**: Draft
**Input**: User description: "LLM-based intent parser as a fallback for natural-language player input. The existing fast `CommandParser` handles canonical and aliased forms (`take`, `get`, `pick`, `n`, `north`, `'hi`, `:waves`); rejecting natural-language variants ('grab the lantern off the table', 'I want to pick up that journal', 'head north and look around') as unknown. This feature adds an LLM-backed fallback that resolves unknown input to a canonical action using tool use. Hybrid architecture: fast parser stays as the front-line path; only `{:unknown, ...}` results go to the LLM. One action per submission (chained intent is refused; chaining can be added later). A `respond_to_player` refusal tool is the LLM's only escape hatch — it must never hallucinate actions. Downstream validation (object resolution, room scope, etc.) is unchanged."

## Clarifications

### Session 2026-05-19

- Q: What should the resolver do when player intent doesn't exactly match a canonical action but a near-mapping exists (e.g., `examine the lantern` when only `look` exists)? → A: Refuse with a hint. The resolver MUST refuse for intents that don't precisely match a canonical action, even when a related action is semantically adjacent. The refusal SHOULD hint at what the game can do (e.g., "You can `look` to see the room, but examining specific objects isn't supported yet."). Substitution would erode player trust and would silently break test design when missing actions ship later.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Player Uses Natural-Language Variants for Supported Actions (Priority: P1)

A player whose muscle memory was built around canonical commands (`take brass lantern`, `go north`) discovers they can also type more conversationally — `grab the lantern off the mantel`, `head north`, `let me pick up the journal`, `give that thing to me`, `tell Alice I'll be right there` — and the game does the right thing every time. The action that results is identical to what would have happened if the player had typed the canonical form: the lantern moves to their inventory, they walk through the north exit, the journal lifts from the shelf, the tell goes to Alice. The player never sees a "I don't understand" message for input that maps cleanly to one of the game's supported verbs.

**Why this priority**: This is the entire player-facing payoff of the feature. Without it, the feature delivers zero value — the fast canonical parser already works for the commands players have learned to type. The whole point is to lower the barrier for players who haven't memorized the verb table or who naturally express intent more verbosely.

**Independent Test**: Given a player in a room containing a takeable "brass lantern", when the player submits `grab the lantern off the table`, then the lantern moves into their inventory exactly as if they had submitted `take brass lantern` — the same log entries appear, the same Present HUD updates, the same downstream broadcasts fire. Repeat for at least one verb per supported action (take, drop, move, look, inventory, say, emote, tell, whisper) using a phrasing the fast parser would reject.

**Acceptance Scenarios**:

1. **Given** a player in a room containing a brass lantern, **When** they submit `grab the lantern off the table`, **Then** the lantern moves to their inventory and the player's log shows the same confirmation entry as if they had typed `take brass lantern`.
2. **Given** a player in a room with a north exit, **When** they submit `head north`, `walk north`, `let's go north`, or `I want to go north`, **Then** the player moves through the north exit just as if they had typed `north` or `go north`.
3. **Given** a player wanting to communicate, **When** they submit `tell Alice I'm coming` or `whisper to Bob that I'll meet him later`, **Then** the corresponding tell or whisper is delivered with the recipient and message extracted from the natural-language phrasing.
4. **Given** a player carrying a journal, **When** they submit `put the journal back` or `let go of the journal`, **Then** the journal is dropped in the current room just as if they had typed `drop journal`.
5. **Given** a player wanting to know what they're carrying, **When** they submit `what's in my pockets` or `show me my stuff`, **Then** the inventory listing appears just as if they had typed `inventory` or `inv`.

---

### User Story 2 - Player Gets a Clear Refusal for Unsupported or Ambiguous Intent (Priority: P2)

A player types something the game can't act on — a question (`what time is it?`), a request for a not-yet-implemented feature (`attack the orc`, `save my game`), a meta-game query (`who am I?`), gibberish, or a multi-step intent (`take the lantern and head north`) — and gets a clear, friendly refusal entry in their log instead of a generic confusing error or, worse, the game pretending to act on something it can't. The refusal tells the player what went wrong in human terms — they can quickly adjust and try again — and the rest of the game (other players' actions, their own subsequent commands) keeps working normally.

**Why this priority**: Without explicit refusal handling, expressive input that doesn't map to a supported action would either succeed wrongly (the model hallucinates an action) or fail with a confusing system error. Refusals are the safety boundary that makes the feature trustworthy. A player who types `attack the orc` deserves a message saying combat isn't supported yet — not a silent no-op, not a crash, not a take/drop attempt on the orc.

**Independent Test**: Given a player in any room, when they submit `save my game` or `attack the wizard` or `what's the meaning of life?`, then their log appends a refusal entry that doesn't take any game action, doesn't disrupt other players, and gives the player enough information to adjust their input.

**Acceptance Scenarios**:

1. **Given** a player asking an out-of-game question, **When** they submit `what time is it?` or `who made this game?`, **Then** their log appends a refusal entry indicating that's not something the game can answer, and no game action is taken.
2. **Given** a player attempting an unimplemented action, **When** they submit `attack the orc` or `cast a spell`, **Then** their log appends a refusal entry indicating that action isn't supported yet.
3. **Given** a player issuing a multi-step intent, **When** they submit `take the lantern and go north`, **Then** their log appends a refusal entry suggesting they issue one action at a time, and no game action is taken (neither the take nor the move executes).
4. **Given** a player typing nonsense or unclear input, **When** they submit `xyzzy quux` or `the thing is whatever`, **Then** their log appends a refusal entry asking them to clarify what they want to do.
5. **Given** a player whose intent resolves to a supported action but with arguments that don't exist in the room, **When** they submit `take the dragon` in a room with no dragon, **Then** the existing world-state refusal fires (e.g., "you don't see that here") — the system never bypasses the canonical action's own validation rules.
6. **Given** a player whose intent is close to but distinct from a canonical action (e.g., `examine the lantern`, `inspect the journal`, `study the runes` — there is no examine / inspect / study action), **When** they submit such input, **Then** the resolver refuses with a hint indicating what IS available ("You can `look` to see the room, but examining specific objects isn't supported yet."), and does NOT substitute a near-mapping action like `look`.

---

### User Story 3 - Game Remains Responsive When the Intent Resolver Fails (Priority: P3)

The external AI service backing the natural-language resolver is unavailable, slow, rate-limited, or returns garbage. The player whose command happened to need the resolver sees a graceful "I'm not sure what you meant" refusal in their log — no crash, no infinite spinner, no broken UI. Other players in the game are entirely unaffected: their canonical commands keep flowing through the fast path with zero added latency, and their LLM-fallback commands either succeed normally (if their command happens not to trigger the same failure) or get the same graceful refusal. The player whose command was refused due to a service failure can immediately try again — either with the same input (in case the service has recovered) or by rephrasing toward a canonical form.

**Why this priority**: Third-party service dependencies inevitably fail in production. Without explicit handling, every player whose command happens to hit the LLM fallback during a service outage would see a crashed game session. The cost of this defensive work is small; the cost of skipping it is "the entire feature is fragile in operations."

**Independent Test**: Simulate the AI service being unreachable (configure an invalid endpoint, force a timeout, return a malformed response) and submit a natural-language command. Verify the player's log shows a graceful refusal entry, the LiveView session stays connected and responsive, and other players' canonical commands continue to work with no added latency.

**Acceptance Scenarios**:

1. **Given** the AI service is unreachable, **When** a player submits natural-language input, **Then** their log appends a graceful refusal entry within a bounded time and the session remains usable for subsequent commands.
2. **Given** the AI service times out, **When** a player submits natural-language input, **Then** the player sees a graceful refusal within a bounded time and the player can immediately submit a follow-up command.
3. **Given** the AI service returns a malformed or unexpected response, **When** a player submits natural-language input, **Then** their log appends a graceful refusal entry — the malformed response never propagates to the player's view or causes a crash.
4. **Given** the AI service has just failed for one player, **When** a second player submits a canonical command via the fast path, **Then** the second player's command resolves with normal fast-path latency — the first player's failure does not block, slow, or affect the second player.

---

### Edge Cases

- **Canonical commands stay on the fast path**: a player typing `n`, `look`, `inv`, `take lantern`, `'hi`, or `:waves` never invokes the AI resolver — these are handled by the existing fast parser with no added latency or cost.
- **Ambiguous reference**: a player types `take it` or `get the thing` in a room with multiple objects. The resolver picks a best guess from context, or refuses with a clarifying message if no single object is dominant.
- **Near-mapping intent** (e.g., `examine X`, `inspect X`, `study X`, `read X` — actions that are semantically adjacent to `look` but not implemented): per FR-007a the resolver refuses with a hint rather than substituting `look`. A future feature that adds an `examine` action will make these intents start succeeding; this rule ensures the player's mental model doesn't need to shift when that happens.
- **Pronouns / context-dependent references**: a player types `pick it up` after looking at a specific object. For v1, the resolver does not maintain conversational state — `it` resolves only if the surrounding room context makes it obvious (e.g., only one object is present), otherwise it refuses.
- **Action resolves but argument doesn't exist in the world**: handled by existing canonical action validation (the lantern's not in the room → "you don't see that here"). The resolver is not trusted to override world state.
- **Non-English input**: out of scope for v1. Behavior is undefined and the player should see a graceful refusal rather than a crash.
- **Very long input**: a reasonable input length cap applies (matching the 500-character cap from communication verbs is a sensible default). Over-cap input is refused before the resolver is invoked.
- **Resolver picks an action the player isn't authorized to perform**: this case doesn't arise in v1 because all canonical actions are player-available, but the design should not assume the resolver is trusted to perform privileged operations.
- **Profanity, harassment, or abuse delivered via the LLM path**: the resolver passes player-supplied text through to existing action handlers (e.g., a `say` action carries the player's message verbatim). Content moderation is deferred — same model as the communication verbs, which apply no profanity filter.

## Requirements *(mandatory)*

### Functional Requirements

**Command routing**:

- **FR-001**: The system MUST attempt to resolve player input via the existing fast canonical-command parser first. The AI fallback is invoked when the fast parser returns an unknown-command result OR (per FR-001a) when a fast-parsed command fails because an object reference could not be resolved.
- **FR-001a** (amendment, feature 005a): A command can be lexically canonical yet fail at object-name resolution — e.g. `drop the lantern` parses cleanly but `the lantern` does not exact-match the carried object `brass lantern`. When a fast-parsed `take` fails with "no such object" or a `drop` fails with "not carrying that" — i.e. the failure is an unresolved object *name*, not a world-state condition — the system MUST route the player's original literal input to the AI resolver, which can map the loose noun phrase against actual room/inventory contents. This fallback fires only on the first (fast-path) attempt; an action the AI itself resolved that still fails MUST simply refuse (no fallback loop). Failures that the AI cannot help with — no exit in that direction, object is fixed, genuinely ambiguous identical names, no current room — MUST NOT trigger the fallback.
- **FR-002**: Canonical and aliased commands that resolve successfully MUST NOT trigger any AI invocation, additional latency, or token cost. (A canonical command that fails object-name resolution does pay the fallback cost per FR-001a — this is the deliberate price of resolving loose references.)
- **FR-003**: The integration boundary between the fast parser and the AI fallback MUST be invisible to the player — they see only the same kinds of log entries (confirmations, refusals, room views) regardless of which path resolved their input.

**AI intent resolution**:

- **FR-004**: When the fast parser returns unknown, the system MUST hand the player's raw input to an AI intent resolver that selects exactly one canonical game action and the arguments for that action.
- **FR-005**: The set of game actions the resolver can select MUST be limited to the canonical actions already implemented by the game (`take`, `drop`, `move`, `look`, `inventory`, `say`, `emote`, `tell`, `whisper`) plus an explicit refusal mechanism (FR-007). The resolver MUST NOT be able to invent actions beyond this set.
- **FR-006**: The resolver MUST receive a context snapshot describing the player's current room (room name, description, visible objects with names and short descriptions, exits with directions, other players present) and the player's inventory. This context is used to disambiguate references such as "the lantern" against actual room contents.

**Refusal and validation**:

- **FR-007**: The resolver MUST have an explicit refusal mechanism the model uses when player input does not map to a supported action. Refusal is the resolver's only sanctioned way to signal "no action" — the resolver MUST NOT respond with a malformed or absent action choice as a stand-in for refusal. The refusal mechanism takes a free-form refusal message authored by the resolver per request, allowing the message to be situational and to hint at what the game CAN do.
- **FR-007a**: When player intent is close to but distinct from a canonical action (e.g., `examine the lantern` when only `look` exists, `inspect the journal`, `study X`, `read X`), the resolver MUST refuse via FR-007 rather than substitute the nearest available action. The refusal SHOULD hint at adjacent capabilities the game does support (e.g., "You can `look` to see the room, but examining specific objects isn't supported yet."). This rule preserves player intent precision and ensures future actions (when added to the canonical set) start succeeding cleanly without backwards-compatibility tension against learned substitution behavior.
- **FR-008**: When the resolver selects a refusal, the player's log MUST append a refusal entry containing a brief human-readable explanation of why the input wasn't acted on. The session MUST otherwise be unchanged (no broadcast, no state change).
- **FR-009**: When the resolver selects an action whose arguments don't resolve in the current world (e.g., a `take` on a non-existent object), the system MUST surface the existing canonical refusal for that case (e.g., "you don't see that here"). The resolver's choice MUST NOT bypass downstream world-state validation.
- **FR-010**: Multi-step or chained intent in player input ("take the lantern and head north") MUST be refused with a hint that the player should issue one action at a time. Multi-step is explicitly out of scope for this feature; the resolver may receive multi-step input but MUST decline rather than executing the first step in isolation.

**Resilience**:

- **FR-011**: When the AI service is unreachable, times out (within a bounded wait), or returns malformed output, the player MUST see a graceful refusal entry in their narrative log. The player's LiveView session MUST remain connected and responsive for subsequent commands.
- **FR-012**: AI service failures affecting one player MUST NOT block, slow, or otherwise disrupt other players' commands. In particular, the fast canonical-command path MUST be completely unaffected by AI service health.
- **FR-013**: The system MUST enforce a bounded wait on the AI resolver. The bound MUST be short enough that a failed or slow resolver doesn't leave the player staring at an unresponsive session for more than a few seconds.

**Player experience**:

- **FR-014**: The player's narrative log MUST echo the player's original literal input as a command entry, regardless of whether the input was resolved via the fast path or the AI path. The player MUST NOT see their input rewritten into a canonicalized form.
- **FR-015**: The player MAY see a subtle indicator that the game is processing their input while the AI resolver is in flight. Such an indicator MUST be unobtrusive and MUST disappear as soon as a result (action or refusal) is appended to the log.

**Cost and observability**:

- **FR-016**: The system SHOULD log AI invocation counts and outcomes per player so abusive patterns or cost overruns can be detected. Per-player rate limits and hard caps are deferred to operational tuning; no hard cap is required in this feature.
- **FR-017**: The system MUST cap the length of player input handed to the AI resolver (matching the 500-character cap used by communication verbs is a sensible default). Over-cap input MUST be refused before the resolver is invoked.

### Key Entities

- **Player Input**: The raw text submitted by a player via the command input box in the Play view. Whitespace-trimmed, length-capped, in English.
- **Canonical Action**: One of the game's existing supported verbs — `take`, `drop`, `move`, `look`, `inventory`, `say`, `emote`, `tell`, `whisper`. Each has a small, well-defined argument schema and an existing handler implementation. The resolver chooses one of these per invocation.
- **Resolver Context Snapshot**: A point-in-time summary of the player's current room (name, description, visible objects, exits, occupants) and inventory, supplied to the AI resolver so it can disambiguate references. Sourced from existing world read-side queries; not persisted; rebuilt on every invocation.
- **Resolver Outcome**: The output of one AI resolver invocation. Exactly one of: (a) a canonical action with arguments, (b) a refusal with a player-visible message. There is no third outcome (no clarifying-question round-trip in v1).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 95% of natural-language variants of supported actions correctly resolve to the right canonical action on first attempt. Measured against a curated test set of at least 50 inputs covering all current verbs and a representative spread of phrasings.
- **SC-002**: 95% of natural-language inputs reach a resolver outcome (action execution or refusal) within 1 second of submission, measured end-to-end from the player's submit to the log update.
- **SC-003**: Canonical fast-path commands resolve in under 50 milliseconds 99% of the time after this feature ships. Adding the AI fallback MUST NOT impose any measurable latency on commands that the fast parser already handles.
- **SC-004**: 100% of AI service failures (unreachable endpoint, timeout, malformed response) produce a graceful refusal entry in the affected player's log, with zero session crashes and zero impact on other players' commands.
- **SC-005**: 100% of out-of-scope intents (questions, unimplemented actions, multi-step, near-mapping intent like `examine`/`inspect`/`study`) produce a refusal entry — the resolver never invents an action it cannot perform AND never substitutes a near-mapping canonical action for an unsupported one.
- **SC-006**: After a short play session, players (in informal feedback) report that the game "understands what they meant" without needing to memorize a specific verb vocabulary.

## Assumptions

- This feature applies to the Play mode only. The Wizard view (introduced in feature 001 as a mock) is unaffected.
- English-language input only for v1. Non-English input behavior is undefined; the system should respond with a graceful refusal rather than crashing, but correct interpretation of non-English variants is not in scope.
- The fast canonical parser from features 003 and 004 is the source of truth for canonical commands and is not modified by this feature beyond receiving its existing `{:unknown, _}` outputs to route to the AI fallback.
- The AI resolver is invoked synchronously per player command — no background processing, no queueing, no batching. The fast path keeps the user experience instant for the canonical commands players have already learned.
- The set of canonical actions the resolver can select is fixed at deploy time. Adding new player actions requires shipping a new release with the resolver's action set updated. Dynamic / runtime action registration is out of scope.
- Players never see raw AI output. They see either the action's natural effect (e.g., the lantern moves to inventory) or a refusal message — same kinds of log entries as if they had typed the canonical form themselves.
- The resolver is stateless across invocations. It does not learn from prior commands, does not remember per-player phrasing, does not persist context. Each invocation receives a fresh context snapshot.
- The resolver cannot ask the player clarifying questions. If input is ambiguous, the resolver either picks a best guess from context or refuses.
- Cost is not the primary constraint for v1 (small player base; a small, fast model is sufficient; prompt context can be cached at the service level). Operational cost monitoring and per-player rate limits are deferred to a follow-up if needed.
- Content moderation (profanity filters, abuse detection) is not added by this feature. Player text reaching the `say` / `emote` / `tell` / `whisper` actions via the AI path is treated the same way as text from the fast path — verbatim broadcast, no filter.
- Desktop web only, matching the scope of features 001 / 002 / 003 / 004.
- Multi-step / chained intent ("take the lantern and head north") is explicitly out of scope and will be refused. Adding chained-intent support is a candidate future feature; this feature's design is structured so that addition does not require re-architecting.
- Conversational responses (the game replying in-character beyond refusals) are out of scope. The resolver's only outputs are action selections and refusals.
- NPC AI is explicitly out of scope. This feature introduces the AI-action-selection substrate that agentic NPCs will later inherit, but adding NPCs themselves is a separate feature.
