# Feature Specification: External NPC Brains — Game-Side Contract API

**Feature Branch**: `018-external-npc-api`
**Created**: 2026-07-01
**Status**: Draft
**Input**: User description: "external NPC brains - the game should no longer directly manage the decisions of NPCs. Instead, NPCs will be managed externally by temporal workflows, as described in ../agentic-realms-npc specs. To facilitate this, Agentic Realms needs to expose the relevant API calls to allow these external NPC workflows to query their identity (including lore), the contents of the room around them, and to be able to submit commands such as move. This API is authenticated via a shared bearer token secret, which is also described in the feature 0001 spec in agentic-realms-npc."

## Overview

An NPC's decision about whether and where to move is moving **out** of the game.
From this feature forward, the authoritative, autonomous "what should this NPC do
next" decision is owned by a separate, off-world mind service (one durable
workflow per NPC, defined in the companion `agentic-realms-npc` project). The
game stops being the place where autonomous NPC movement is decided and becomes
the place where those decisions are **enacted and witnessed**.

To make that possible, the game must do two things. First, it must own each
NPC's **mind lifecycle**: when an NPC is spawned, the game starts exactly one
external mind for it (a durable workflow in the orchestration server); when the
NPC is removed or destroyed, the game terminates that NPC's mind. Second, it must
expose a small, authenticated **contract** the running mind calls to (1) read an
NPC's identity and lore, (2) read the NPC's current surroundings, and (3) submit
a move on the NPC's behalf. The game remains the single source of truth for every
NPC's identity, location, and world state, and the sole writer of every world
change: the external mind only proposes intent through this contract; the game
validates, decides, and writes.

There are two distinct, one-directional integrations here, and they never cross:

1. **Game → Temporal server (mind lifecycle).** Starting and terminating an NPC
   mind is a call the game makes to the **Temporal server** over its HTTP API —
   it starts and terminates a Temporal workflow (`NpcWorkflow`, id `npc-<entity_id>`,
   task queue `npc-minds`). This call is made to the Temporal server, **not** to
   the `agentic-realms-npc` worker service that hosts the mind code. The game
   never contacts that worker at all.
2. **Mind (worker) → Game (the contract).** The running mind — hosted by the
   `agentic-realms-npc` worker, which connects out to the same Temporal server and
   polls for work — calls back into the game over the authenticated HTTP contract
   to read identity, read surroundings, and submit moves.

The HTTP contract is therefore the **only** direct coupling between the game and
the mind worker service; the game's only other outward integration is with the
Temporal server for lifecycle. The contract is secured by a shared-secret bearer
token required on every route, used identically in local development and in
hosted deployments. The exact wire shapes are pinned in a single agreed contract
schema that both systems share (feature `001` in `agentic-realms-npc`).

Importantly, the game does not gain any in-game autonomous NPC movement logic in
this feature — and, per the architectural boundary this feature establishes, it
must not. Starting a mind is not the game deciding an NPC's moves; it is the game
delegating those decisions to the external mind. Existing reactive, scripted NPC
content (e.g. an NPC greeting a player who enters) is unrelated to autonomous
decision-making and is unaffected.

## Clarifications

### Session 2026-07-01

- Q: Which spawned NPCs should the game start an external mind for? → A: Every spawned NPC — no per-NPC gating; the ungettable `fixed` flag (which means "cannot be picked up", not "stationary") does not exempt an NPC.
- Q: NPCs are only removed today via the transient-region hard-purge (which emits no subscribable domain event) — how should mind-termination be triggered? → A: Introduce a first-class, event-sourced NPC-removal command/event and terminate the mind on it; also terminate out-of-band in the transient-region purge path (which deletes the stream and so cannot carry an event).
- Q: If the Temporal server is unreachable when an NPC spawns/despawns, how hard must the game try to start/stop the mind (world change never blocked)? → A: Best-effort single attempt that never blocks the world change, backed by a periodic reconciliation sweep that converges minds to the set of live NPCs (starts missing minds, terminates orphaned ones).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Enact an externally-decided move that players witness (Priority: P1)

An external mind, having decided that its NPC should walk through a specific
exit, asks the game to enact that move. The game verifies the NPC is still where
the mind expected and that the requested exit is real, relocates the NPC through
its existing movement path, and every player in the origin room sees the NPC
leave while every player in the destination room sees it arrive — exactly as they
would for any other move. If the NPC has meanwhile moved, or the exit does not
exist, the game refuses and tells the caller why, without ever relocating the NPC
incorrectly.

**Why this priority**: This is the whole premise of the feature — the game
enacting externally-decided NPC movement as a first-class, player-visible world
change. Without it, nothing the external mind decides can affect the world, and
the identity and surroundings reads have no payoff. It is also the only
world-mutating route, so it carries the most risk and must be defined first.

**Independent Test**: With an NPC placed in a known room that has at least one
exit, submit a move request naming that exit and the NPC's current room as the
expected origin; confirm the NPC relocates to the exit's destination and that
players in both rooms receive the standard "NPC left" and "NPC arrived"
notifications. Then submit a move naming a stale origin room and confirm it is
refused as a conflict with no relocation; submit a move naming a direction that
is not an exit of the room and confirm it is refused as an invalid exit.

**Acceptance Scenarios**:

1. **Given** an NPC in a room with an exit to the north, **When** a move request for direction "north" with the NPC's current room as expected origin is submitted, **Then** the NPC's location changes to the northern room, the caller receives a success result naming the origin and destination rooms, and players in the origin room are notified the NPC left while players in the destination room are notified it arrived.
2. **Given** an NPC that has already been moved out of room A by another actor, **When** a move request is submitted with room A as the expected origin, **Then** the game refuses it as a conflict, performs no relocation, and emits no player-visible event.
3. **Given** an NPC in a room that has no exit to the west, **When** a move request for direction "west" is submitted, **Then** the game refuses it as an invalid/no-such exit, performs no relocation, and emits no player-visible event.
4. **Given** a move request that succeeds, **When** the identical request is retried (e.g. after a transient network failure) while the NPC is no longer in the original expected room, **Then** the retry is refused as a conflict and the NPC is relocated exactly once in total, never twice.
5. **Given** an autonomous, externally-driven relocation and an otherwise identical player- or content-driven relocation of the same NPC between the same two rooms, **When** players witness each, **Then** the two are indistinguishable in the notifications and information players receive — no "thinking", planning, or decision events are ever emitted.

---

### User Story 2 - Provide an NPC's live surroundings to its external mind (Priority: P1)

Before deciding, an external mind asks the game where its NPC currently is: which
room, that room's usable exits and their directions, and everything else present
in the room. The game answers with a fresh, read-only snapshot that changes the
world in no way. If the NPC has been removed from the world or is placed nowhere,
the game says so plainly (an empty, non-actionable snapshot) rather than
erroring, so the mind simply takes no action that cycle.

**Why this priority**: A move can only be legally proposed against exits the NPC
actually has right now, from the room it is actually in. Without a trustworthy,
per-cycle surroundings read, the external mind cannot make a valid move request,
so this is required for User Story 1 to be usable by a real mind. It is a pure
read and carries no world-mutation risk, but it gates correct movement.

**Independent Test**: For an NPC placed in a known room, request its surroundings
and confirm the response reports the correct room, the room's current exits with
their directions and destinations, and every entity present tagged by kind
(player, NPC, or object); confirm the read changes nothing in the world. Then
request surroundings for an NPC that has been removed/placed nowhere and confirm
an empty, non-actionable snapshot is returned rather than an error.

**Acceptance Scenarios**:

1. **Given** an NPC in a room with exits and other occupants, **When** its surroundings are requested, **Then** the response reports the NPC's current room, each current exit with its direction and destination room, and every entity present (players, NPCs, objects) each identified and tagged with its kind.
2. **Given** an NPC currently in the world, **When** its surroundings are requested any number of times, **Then** no world change occurs and no player-visible effect is produced by the read.
3. **Given** an NPC that has been removed from the world or is placed nowhere, **When** its surroundings are requested, **Then** the response is a well-formed empty snapshot (no room, no exits, no occupants) rather than an error.
4. **Given** an identifier that is not an existing NPC, **When** its surroundings are requested, **Then** the game reports the entity as unknown.

---

### User Story 3 - Guard the contract with a shared secret (Priority: P1)

An operator configures a single shared secret that the external mind service must
present on every contract call. The game accepts calls that present the correct
secret and rejects every call that presents a missing, malformed, or incorrect
secret, on all three routes, before any read or world change occurs. The same
mechanism works identically in local development and in hosted deployments, and
the operator can change the secret through configuration without a code change.

**Why this priority**: The move route mutates the world and the reads expose NPC
data, so exposing any of these routes without authentication is unacceptable.
Authentication is a hard gate that must ship together with the routes it
protects, hence P1.

**Independent Test**: Call each of the three routes with no credential, with an
incorrect credential, and with the correct configured secret; confirm the first
two are rejected without performing any read or world change, and only the last
is honored. Change the configured secret and confirm the old value is now
rejected and the new value is honored, with no code change.

**Acceptance Scenarios**:

1. **Given** the shared secret is configured, **When** any contract route is called without a credential, **Then** the request is rejected as unauthorized and no read or world change is performed.
2. **Given** the shared secret is configured, **When** any contract route is called with an incorrect credential, **Then** the request is rejected as unauthorized and no read or world change is performed.
3. **Given** the shared secret is configured, **When** any contract route is called with the correct credential, **Then** the request is processed normally.
4. **Given** a deployment, **When** the operator changes the configured secret, **Then** the previously valid secret is rejected and the new secret is honored, with no code change and identical behavior in local and hosted environments.

---

### User Story 4 - Automatically start a mind when an NPC is spawned (Priority: P1)

When **any** NPC is spawned into the world through the game's existing flow, the
game reacts to that spawn by submitting a start request for that NPC's mind to the
orchestration server, with no manual step. Every spawned NPC gets a mind — there
is no per-NPC gating, and the ungettable `fixed` flag (which means "cannot be
picked up", not "stationary") does not exempt an NPC; a character that should
stay put simply has a mind that tends to choose "stay". The request is keyed to
the NPC's
deterministic identity and carries the agreed id-conflict policy. Crucially, the
game does not check whether a mind already exists and does not enforce uniqueness
itself: exactly-one-mind-per-NPC is a property of the **orchestration server**.
If the spawn is retried or replayed, the game simply re-submits the same start,
and the orchestration server's id-conflict handling ensures the NPC still ends up
with exactly one mind, never two. Because the mind is generic and derives all
behavior from the NPC's runtime data, a brand-new NPC invented at runtime gains a
working mind with no code change or redeployment.

**Why this priority**: "NPCs will be managed externally" is only real if spawned
NPCs actually get a mind automatically. Without the start handoff, no NPC is ever
animated and the contract routes have no caller. Getting exactly one mind per NPC
(never two) is a correctness requirement — delegated to the orchestration server,
not the game — so this is P1.

**Independent Test**: Spawn a new NPC through the existing flow and confirm the
game submits a start for that exact NPC's mind to the orchestration server, and
that a mind runs. Trigger the spawn again (retry/replay) for the same NPC and
confirm the game re-submits the same start and that no second mind results (the
orchestration server deduplicates by identity). Confirm a previously unknown NPC
invented at runtime also gains a mind with no deployment.

**Acceptance Scenarios**:

1. **Given** the existing NPC spawn flow, **When** an NPC is spawned, **Then** the game submits a start for that NPC's mind keyed to the NPC's deterministic identity, and the orchestration server ensures exactly one mind runs, without any manual action.
2. **Given** an NPC that already has a running mind, **When** the spawn signal for that NPC fires again (retry or replay), **Then** the game re-submits the same start and the orchestration server's id-conflict handling results in no additional mind — the NPC continues with exactly one mind, and the game does no duplicate detection of its own.
3. **Given** a brand-new NPC type invented at runtime, **When** it is spawned, **Then** it gains a mind with no code change and no redeployment.
4. **Given** the orchestration server is temporarily unavailable, **When** an NPC is spawned, **Then** the NPC is still spawned normally in the world, no player sees an error, and the failure to start the mind does not roll back or block the spawn.

---

### User Story 5 - Automatically terminate a mind when an NPC is removed (Priority: P2)

When an NPC is removed or destroyed from the world, the game reacts by submitting
a terminate request for that NPC's mind to the orchestration server so no
orphaned mind keeps running for an NPC that no longer exists. Today the game has
no first-class NPC-removal signal (NPCs are only removed by the transient-region
hard-purge, which deletes the NPC's stream and emits nothing subscribable), so
this feature **introduces a first-class, event-sourced NPC-removal command and
event**; termination is triggered from that event. In addition, the existing
transient-region purge path also terminates the minds of the NPCs it removes —
done out-of-band, because the purge deletes the stream and so cannot carry an
event. As with the start, the game does not track which NPCs have minds and does
not check whether a mind is actually running: it submits the terminate for the
NPC's deterministic identity and relies on the **orchestration server** to
tolerate a terminate that targets a mind which is already stopped or was never
started. Safe, no-op-on-absent termination is therefore a property of the
orchestration server, not game-side bookkeeping.

**Why this priority**: This keeps the mind population in step with the live NPC
population and prevents orphaned minds accumulating, but the world remains
correct without it (an orphaned mind simply finds no actionable surroundings and
moves nothing). So it hardens the lifecycle rather than enabling the core loop,
making it P2.

**Independent Test**: With an NPC that has a running mind, remove/destroy the NPC
through the existing flow and confirm the game submits a terminate and the mind
stops in the orchestration server. Remove an NPC that has no running mind and
confirm the game still submits the terminate and the removal completes with no
error (the orchestration server no-ops the absent target).

**Acceptance Scenarios**:

1. **Given** an NPC with a running mind, **When** the NPC is removed via the new first-class NPC-removal command/event, **Then** the game submits a terminate for that NPC's mind to the orchestration server and the mind stops.
2. **Given** an NPC with a running mind that sits in a transient region, **When** that region is purged, **Then** the purge path also terminates that NPC's mind (out-of-band, since the purge carries no event) and the mind stops.
3. **Given** an NPC with no running mind, **When** the NPC is removed, **Then** the game still submits the terminate for the NPC's deterministic identity, the orchestration server tolerates the absent target, and the removal completes cleanly with no error — without the game checking mind existence beforehand.
4. **Given** the orchestration server is temporarily unavailable, **When** an NPC is removed, **Then** the NPC is still removed normally in the world, no player sees an error attributable to the mind termination, and the later reconciliation sweep terminates the now-orphaned mind.

---

### User Story 6 - Provide an NPC's identity and lore to its external mind (Priority: P3)

When an external mind first comes online for an NPC, it asks the game who that
NPC is: its name, its short and long descriptions, and its lore. The game answers
from its content/blueprint-derived data with a stable snapshot the mind can read
once and keep for its lifetime. This is what lets the mind's decisions be
characterized by the NPC's personality and backstory rather than being generic.

**Why this priority**: Identity/lore enriches the *quality* of externally-made
decisions but is not strictly required for a valid move: a mind can move an NPC
through valid exits without knowing its backstory. So this enriches the core loop
rather than enabling it, making it the lowest priority.

**Independent Test**: For an existing NPC, request its identity and confirm the
response includes its name, short and long descriptions, and lore, matching the
game's content data for that NPC. Request identity for an identifier that is not
an existing NPC and confirm the game reports it as unknown.

**Acceptance Scenarios**:

1. **Given** an existing NPC with authored lore, **When** its identity is requested, **Then** the response includes the NPC's name, short description, long description, and lore as held in the game.
2. **Given** an identifier that is not an existing NPC, **When** its identity is requested, **Then** the game reports the entity as unknown.
3. **Given** an NPC's identity has been read once, **When** the underlying content data has not changed, **Then** repeated reads return the same stable snapshot.

---

### Edge Cases

- **Unknown NPC**: A request naming an identifier that is not an existing NPC is reported as unknown on every route, rather than returning empty-but-valid data or performing a partial action.
- **NPC placed nowhere / removed**: A surroundings read for an NPC that is in the void or has been removed returns a well-formed empty snapshot (no room, no exits, no occupants); a move for such an NPC is refused (there is no expected room it still occupies), never forced.
- **Missing / malformed / wrong credential**: Rejected as unauthorized on every route before any read or world change; the specific reason (missing vs. wrong) need not be disclosed to the caller.
- **Stale expected origin (conflict)**: A move whose expected origin room no longer holds the NPC is refused as a conflict and never applied on top of whatever move already happened.
- **Non-existent / invalid exit**: A move naming a direction that is not a current exit of the expected room is refused as an invalid exit and never applied.
- **Concurrent relocation by another actor**: If a player, content tick, or another action relocates the NPC at the same instant, the game's single-writer ordering decides the outcome; the external move is either applied cleanly or refused as a conflict, never interleaved into an inconsistent state.
- **Retry after transient failure**: Re-submitting the same move must never double-move the NPC; if the NPC is still where expected it results in exactly one relocation, and if it has moved on it is refused as a conflict.
- **Restricted or private exits**: Exits that are not part of the shared, generally-traversable world (for example, owner-only private exits belonging to another actor) are neither reported in an NPC's surroundings nor honored as a move destination for an NPC.
- **Per-player-gated content**: The surroundings read is a trusted service view, not a specific player's view; it reports occupants of the room as they exist, independent of any single player's per-player content gating.
- **Duplicate spawn handoff**: A retried or replayed NPC spawn must never produce a second mind for the same NPC. The game re-submits the same deterministic-identity start; the "never two" guarantee is provided by the orchestration server's id-conflict handling, not by any game-side check.
- **Terminating a non-existent mind**: Removing an NPC that has no running mind (already terminated, or never started) must complete cleanly without error. The game submits the terminate unconditionally; the orchestration server no-ops the absent target — the game does not verify existence first.
- **Orchestration server unavailable during lifecycle handoff**: If the orchestration server cannot be reached when an NPC is spawned or removed, the world spawn/removal must still succeed, no player may see an error, and the handoff failure must not roll back or block the world change. The periodic reconciliation sweep later brings the mind population back in line — starting the mind that was missed, or terminating the mind that was orphaned.
- **NPC removed while its mind is mid-cycle**: Terminating the mind and any in-flight contract call from that mind must not corrupt world state; a late move from a mind whose NPC is gone is simply refused (unknown entity or conflict), never applied.

## Requirements *(mandatory)*

### Functional Requirements

**Architectural boundary (game no longer decides)**

- **FR-001**: Autonomous NPC movement decisions MUST be owned outside the game; the game MUST NOT contain or add in-game logic that autonomously decides whether or where an NPC moves.
- **FR-002**: The game MUST enact NPC moves only in response to an explicit, authenticated external request through this contract (or an equivalent existing player-/content-driven cause); it MUST NOT originate autonomous NPC moves on its own.
- **FR-003**: The game MUST remain the single source of truth for every NPC's identity, lore, and location and the sole writer of every world change; the external mind proposes intent only and never writes to the world by any other means.
- **FR-004**: Existing reactive, scripted NPC content that responds to world triggers (e.g. speaking when a player enters or leaves) MUST be unaffected by this feature; such content is not an autonomous movement decision and is out of this feature's boundary.

**Identity read**

- **FR-005**: The game MUST expose a read that, given an NPC identifier, returns that NPC's name, short description, long description, and lore from its content/blueprint-derived data.
- **FR-006**: The identity read MUST be a pure read that changes nothing in the world and is safe to call repeatedly.
- **FR-007**: The identity read MUST report the entity as unknown when the identifier does not correspond to an existing NPC.
- **FR-008**: The identity snapshot MUST be stable for a given NPC while its underlying content data is unchanged, so that a mind may read it once and retain it for its lifetime.

**Surroundings read**

- **FR-009**: The game MUST expose a read that, given an NPC identifier, returns the NPC's current room, that room's current exits (each with a direction and its destination room), and the room's occupants.
- **FR-010**: The surroundings occupants MUST include every entity present in the room — players, NPCs, and objects — each identified and tagged with its kind.
- **FR-011**: The surroundings read MUST be a pure read that performs no world change and produces no player-visible effect, and MUST be safe to call on every decision cycle.
- **FR-012**: When the NPC is placed nowhere or has been removed from the world, the surroundings read MUST return a well-formed empty snapshot (no room, no exits, no occupants) rather than an error.
- **FR-013**: The surroundings read MUST report the entity as unknown when the identifier does not correspond to an existing NPC.
- **FR-014**: The surroundings read MUST report only exits that belong to the shared, generally-traversable world; exits that are private/restricted to a specific other actor MUST NOT be reported to an NPC's mind.

**Move command**

- **FR-015**: The game MUST expose a command that, given an NPC identifier, a direction, and the room the caller expected the NPC to be in, enacts the NPC's move through the game's existing movement command path.
- **FR-016**: The move command MUST honor a compare-and-swap on the expected origin room: if the NPC is no longer in the expected room, the game MUST refuse the move as a conflict and MUST NOT relocate the NPC.
- **FR-017**: The move command MUST refuse a move whose direction is not a current, traversable exit of the expected room, reporting it as an invalid/no-such exit, and MUST NOT relocate the NPC.
- **FR-018**: On success, the move command MUST report the outcome including the origin room and the destination room the NPC moved to.
- **FR-019**: The move command MUST be safe to retry: re-submitting the same request MUST result in at most one relocation for that decision — exactly one if the NPC is still where expected, or a conflict refusal if it has moved on — never a duplicate move.
- **FR-020**: The move command MUST report the entity as unknown when the identifier does not correspond to an existing NPC.
- **FR-021**: An externally-submitted move MUST never bypass, override, or race the game's ordering of world changes; concurrent relocation by any other actor MUST be resolved by the game's single-writer ordering, with the external move either applied cleanly or refused as a conflict.

**Player-visible result**

- **FR-022**: A successful externally-driven relocation MUST be witnessed by players exactly as an equivalent player- or content-driven relocation of an NPC is — the same room-scoped "NPC left" notification to the origin room and "NPC arrived" notification to the destination room, with the same information.
- **FR-023**: No aspect of the external decision process (waiting, planning, deliberation, refused attempts) may be emitted to the world; only a successfully enacted move becomes player-visible.

**Mind lifecycle (spawn / despawn handoff)**

- **FR-024**: The game MUST react to **every** NPC being spawned through its existing flow by submitting a start request for that NPC's mind to the **Temporal server over its HTTP API** (starting the agreed Temporal workflow), with no manual step and no per-NPC gating (the ungettable `fixed` flag does NOT exempt an NPC). This call MUST be made to the Temporal server and MUST NOT be made to the `agentic-realms-npc` mind worker service; the game never contacts the worker directly.
- **FR-025**: The game MUST submit the mind start keyed to the NPC's deterministic identity and carrying the agreed id-conflict policy, and MUST rely solely on the orchestration server to guarantee at most one mind per NPC. On a retried or replayed spawn the game MUST re-submit the same start; the single-mind (exactly-one, never-two) guarantee is the orchestration server's, NOT the game's. The game MUST NOT maintain any registry of which NPCs have minds, MUST NOT check for an existing mind before starting, and MUST NOT perform any duplicate detection of its own.
- **FR-026**: The game MUST start the mind using the workflow type, workflow-id scheme (one deterministic id per NPC identity), task queue, input shape, and id-conflict policy agreed with the mind service, so the correct generic mind is animated for the correct NPC and so the orchestration server can enforce uniqueness by identity.
- **FR-027**: The game MUST react to an NPC being removed or destroyed by submitting a terminate request for that NPC's mind to the **Temporal server over its HTTP API** (terminating the `npc-<entity_id>` workflow). As with the start, this call MUST be made to the Temporal server and MUST NOT be made to the `agentic-realms-npc` mind worker service.
- **FR-027a**: Because the game has no first-class NPC-removal signal today, this feature MUST introduce an event-sourced NPC-removal command and event (command → aggregate → event → projector), and mind termination MUST be triggered from that removal event. Additionally, the existing transient-region purge path MUST terminate the minds of the NPCs it removes; since the purge hard-deletes the NPC's stream and cannot carry an event, that termination MUST be invoked directly within the purge flow via the same reusable terminate step.
- **FR-028**: The game MUST submit the mind terminate keyed to the NPC's deterministic identity WITHOUT first checking whether a mind is running, and MUST rely solely on the orchestration server to tolerate a terminate that targets a mind which is already stopped or was never started; such a no-op termination MUST NOT surface an error to the removal flow. The game MUST NOT track mind existence to decide whether to submit the terminate.
- **FR-029**: The mind lifecycle handoff (start on spawn, terminate on removal) MUST NOT block, delay, or roll back the underlying world change: it is a best-effort attempt, and if the orchestration server is unavailable or the handoff fails, the NPC MUST still be spawned or removed in the world and no player may see an error attributable to the handoff.
- **FR-029a**: The game MUST run a periodic reconciliation sweep that converges the set of running minds to the set of live NPCs: it MUST start a mind for any live NPC missing one and terminate any mind whose NPC no longer exists. Reconciliation is what makes the best-effort handoff eventually consistent after a transient orchestration-server outage; it MUST rely on the orchestration server's start-idempotency and terminate-tolerance (per FR-025/FR-028) and MUST NOT require game-side mind bookkeeping beyond the live-NPC set the game already owns.

**Authentication & security**

- **FR-030**: Every contract route — identity read, surroundings read, and move command — MUST require a shared-secret bearer token presented by the caller, and MUST reject any request that presents a missing, malformed, or incorrect token before performing any read or world change.
- **FR-031**: The same authentication mechanism MUST be used identically in local development and in hosted deployments.
- **FR-032**: The shared secret MUST be supplied by configuration and MUST be changeable without a code change; a changed secret MUST immediately reject the old value and honor the new one.
- **FR-033**: A rejected (unauthorized) request MUST perform no read and no world change and MUST NOT leak whether the failure was a missing versus an incorrect credential.

**Shared contract & configurability**

- **FR-034**: The shapes of the data exchanged across the contract — the identity snapshot, the surroundings snapshot, and the move request and its response — MUST conform to a single agreed contract schema shared with the external mind service, and this HTTP contract MUST be the only **direct** coupling between the game and the mind worker service (the game's only other outward integration being the Temporal server for mind lifecycle). The game MUST NOT call the mind worker service, and the mind worker service reaches the game only through this contract.
- **FR-035**: The contract MUST use string identifiers for entities and rooms, and player identifiers MUST be represented as strings, consistent with the shared schema.
- **FR-036**: The set of movement directions accepted and reported by the contract MUST match the game's world directions as defined in the shared schema.
- **FR-037**: The Temporal server's HTTP API address, namespace, and credentials, and the mind task queue, MUST all be supplied by configuration and changeable without a code change; the same mechanism MUST work for a locally-run Temporal server (e.g. a developer's local instance) and a hosted one (e.g. Temporal Cloud).

### Key Entities *(include if feature involves data)*

- **Identity Snapshot**: The immutable-for-its-lifetime description of an NPC used to characterize its behavior — name, short description, long description, and lore — sourced from the game's content/blueprint-derived data. Read once per mind.
- **Surroundings Snapshot**: The volatile, current view of where an NPC is — its current room, that room's traversable exits (each with a direction and destination room), and the room's occupants (every entity present — players, NPCs, objects — each tagged with its kind) — sourced from the live world. Read every decision cycle. May be empty when the NPC is placed nowhere or removed.
- **Move Request**: A request to relocate an NPC, carrying the NPC identifier, the chosen direction, and the room the caller expected the NPC to be in (the compare-and-swap guard).
- **Move Result**: The outcome of a move request — success (with origin and destination rooms), a conflict (NPC not in the expected room), an invalid/no-such exit, or unknown entity.
- **Shared Secret**: The single configured bearer token that every contract caller must present; owned by the operator, changeable via configuration, used identically across environments.
- **Shared Contract Schema**: The single agreed definition of the identity snapshot, surroundings snapshot, and move request/response shapes, used by both the game and the mind worker service; the only direct coupling between the game and that worker service (the game's lifecycle integration with the Temporal server is separate).
- **NPC Mind**: The external, durable decision-maker for a single NPC, run in the orchestration server. Exactly one exists per live NPC, keyed to the NPC's identity via a deterministic per-NPC workflow id. Its uniqueness is enforced by the orchestration server, not the game. The game submits start-on-spawn and terminate-on-removal requests for it, but owns none of its internal state and keeps no record of its existence.
- **Temporal Server (orchestration server)**: The external durable-workflow engine that hosts and runs NPC minds and is the **authority for mind lifecycle guarantees** — deduplicating starts by identity (at most one mind per NPC) and tolerating terminates that target an absent mind. The game calls its **HTTP API** to submit start (on spawn) and terminate (on removal) requests for the agreed workflow (type, per-NPC workflow-id scheme, task queue, input shape, and id-conflict policy); the game does no bookkeeping of its own. This is a different system from the mind worker service: the game calls the Temporal server, never the worker. Its HTTP API address, namespace, and credentials are configuration.
- **Mind Worker Service (`agentic-realms-npc`)**: The external process that hosts the mind workflow code, connects out to the Temporal server, and polls the task queue to run minds. The game never calls it; it reaches the game only through the authenticated HTTP contract (identity/surroundings/move).
- **NPC Removal Command/Event**: A new, first-class, event-sourced way to remove an NPC from the world (command → aggregate → event → projector), introduced by this feature because none exists today. Its removal event is the primary trigger for terminating the NPC's mind. (The transient-region purge remains a separate removal path that terminates minds out-of-band, since it deletes streams and carries no event.)
- **Reconciliation Sweep**: A periodic game-side process that compares the set of live NPCs to the set of running minds and converges them — starting a mind for any live NPC missing one and terminating any mind whose NPC is gone. It is the backstop that makes the best-effort lifecycle handoff eventually consistent after transient orchestration-server outages, relying on the orchestration server's start-idempotency and terminate-tolerance.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of successful externally-driven NPC relocations are witnessed by players identically to an equivalent player- or content-driven relocation — same "left"/"arrived" notifications, same information, and 0 additional or "thinking" events.
- **SC-002**: 100% of enacted external moves land the NPC in a valid destination of the NPC's actual current room; 0% relocate from a stale room or through a non-existent exit.
- **SC-003**: When an NPC's location changes between the surroundings read and the move attempt, 0% of those stale moves are applied — every such move is refused as a conflict.
- **SC-004**: Re-submitting the same move request produces at most one relocation for that decision — measured as 0 duplicate relocations across repeated/retried identical requests.
- **SC-005**: 100% of contract requests presenting a missing, malformed, or incorrect credential are rejected with 0 reads and 0 world changes performed; 100% of correctly-credentialed requests are processed.
- **SC-006**: The shared secret can be changed through configuration alone, with 0 code changes, after which the old value is rejected and the new value honored.
- **SC-007**: A surroundings read for an NPC placed nowhere or removed returns a well-formed empty snapshot in 100% of cases, with 0 errors surfaced and 0 forced moves.
- **SC-008**: The game contains 0 in-game code paths that autonomously decide NPC movement; every NPC relocation is attributable to an explicit external request or an existing player-/content-driven cause.
- **SC-009**: The three exchanged shapes (identity, surroundings, move request/response) match the shared contract schema exactly, verified by the external mind service consuming them without a game-side code change.
- **SC-010**: Every NPC spawned through the existing flow results in the game submitting exactly one deterministic-identity start request; across repeated or replayed spawns for the same NPC, no more than one mind runs (0 duplicate minds), with the game performing 0 duplicate-detection checks of its own (the guarantee is the orchestration server's).
- **SC-011**: Every NPC removed or destroyed results in the game submitting a terminate request for that NPC's mind; after removal, 0 orphaned minds remain running for NPCs that no longer exist, and terminating a mind that is absent produces 0 errors — with the game performing 0 mind-existence checks beforehand.
- **SC-012**: When the orchestration server is unavailable during a spawn or removal, 100% of those world spawns/removals still succeed and 0 player-visible errors are attributable to the mind lifecycle handoff.
- **SC-013**: After a transient orchestration-server outage, the periodic reconciliation sweep converges to exactly one running mind per live NPC and 0 orphaned minds within one sweep interval, with 0 manual intervention.

## Assumptions

- **No existing autonomous NPC decider to remove**: The game today has no autonomous NPC movement/decision subsystem — NPCs are placed statically and react only to scripted triggers (e.g. speaking on player arrival). This feature therefore establishes and enforces the architectural boundary that autonomous movement lives externally, rather than removing an existing in-game decider.
- **Reuse of the existing movement path and its guard**: Moves are enacted through the game's existing movement command, including its origin-room compare-and-swap guard, and are witnessed through the game's existing NPC left/arrived room notifications; no new movement semantics are introduced.
- **Identity from content/blueprint-derived read model**: The identity snapshot is served from the game's existing denormalized NPC read data (name, descriptions, lore); no new content authoring is required.
- **Single shared secret for the milestone**: One shared secret authenticates all callers on all routes. Richer authentication (per-caller credentials, mutual TLS, per-route scopes) may be added later without changing this feature's behavior. Secure transport is assumed to be provided by the deployment environment.
- **Trusted service view for reads**: The surroundings read is a trusted internal/service view rather than a specific player's view; it reports the room's occupants as they exist and is not filtered by any one player's per-player content gating. Objects are reported regardless of quest-specific per-player visibility.
- **Only globally-traversable exits for NPCs**: An NPC's surroundings report and honor only exits that are part of the shared world; private/owner-restricted exits belonging to another actor are excluded.
- **Spawn signal exists; removal signal is introduced here**: The game already emits a spawn/placement signal for every NPC (the existing clone/spawn flow), which drives the mind start with no new spawn logic. There is, however, **no** first-class NPC-removal signal today — NPCs are only removed by the transient-region hard-purge, which deletes the stream and emits nothing subscribable — so this feature introduces an event-sourced NPC-removal command/event (per the event-sourcing mandate) as the primary termination trigger, and additionally terminates within the purge flow for the NPCs a purge removes.
- **Reconciliation is the backstop for eventual consistency**: A periodic reconciliation sweep converges running minds to live NPCs (start-missing, terminate-orphaned), leaning on the orchestration server's start-idempotency and terminate-tolerance. It is what turns the best-effort, non-blocking handoff into an eventually-consistent "exactly one mind per live NPC" guarantee after transient outages.
- **Lifecycle calls target the Temporal server, not the worker**: Starting and stopping a mind is a call the game makes to the **Temporal server over its HTTP API** to start/terminate a Temporal workflow (`NpcWorkflow`, id `npc-<entity_id>`, task queue `npc-minds`). It is explicitly **not** a call to the `agentic-realms-npc` worker service — the worker connects out to the Temporal server and polls for work on its own. The game and the worker never call each other directly; their only interaction is the worker calling the game's contract routes.
- **Lifecycle handoff is best-effort relative to the world change**: Starting and terminating a mind is decoupled from the durability of the world change itself — the world spawn/removal is authoritative and never blocked by the handoff. Robustness of the handoff (e.g. retry on transient orchestration-server failure) is expected but is not allowed to gate the world change.
- **Deterministic per-NPC mind identity, guarantees owned by the orchestrator**: The mind is uniquely identified by the NPC's identity (a deterministic per-NPC workflow id). Idempotency of the start (at most one mind per NPC) and safe no-op tolerance of a terminate against an absent mind are guaranteed by the **orchestration server** — via its id-conflict handling and its tolerance of terminating an already-stopped/absent workflow — NOT by any game-side bookkeeping. The game holds no registry of which NPCs have minds and performs no existence checks; it simply submits deterministic-id start and terminate requests and lets the orchestration server enforce the invariants.
- **Identifiers as strings**: Entity and room identifiers are strings, and player identifiers are stringified, consistent with the shared contract schema.

## Dependencies

- **Mind worker service (`agentic-realms-npc`)**: The consumer of the HTTP contract; it hosts the mind workflow code, connects out to the Temporal server, polls for work, and calls back into the game to read identity/surroundings and submit moves. Its feature `001` defines the companion side, including the shared-secret bearer authentication described here. The game does not call this service.
- **Shared contract schema**: The single agreed definition (in `agentic-realms-npc`, feature `001`) of the identity snapshot, surroundings snapshot, and move request/response shapes; both systems must conform to it.
- **Existing game movement command and guard**: The origin-room compare-and-swap movement path used to enact and reject moves safely.
- **Existing NPC read data and room queries**: The denormalized NPC identity data and the live room/exits/occupants queries used to answer the reads.
- **Existing NPC room notifications**: The room-scoped "NPC left"/"NPC arrived" notifications used so external moves are witnessed like any other move.
- **Existing NPC spawn signal**: The game-side spawn/placement signal for NPCs that drives the mind start handoff. (There is no existing NPC-removal signal; this feature introduces the event-sourced NPC-removal command/event that drives the terminate handoff.)
- **Transient-region purge path (feature 017)**: The existing hard-purge flow that removes NPCs in a purged region; this feature adds a mind-terminate step to it (invoked directly, since the purge carries no event).
- **Temporal server (orchestration server)**: The durable-workflow engine that hosts NPC minds. The game calls its **HTTP API** to start a mind on spawn and terminate a mind on removal, using the agreed workflow type, per-NPC workflow-id scheme, task queue, input shape, and id-conflict policy. This is the game's lifecycle target — distinct from the mind worker service, which the game never calls. Locally a developer-run instance (e.g. `temporal server start-dev` with its HTTP port); later a hosted one (e.g. Temporal Cloud's HTTP API).

## Out of Scope

- The external mind service itself, its decision/planning logic, and its durable-workflow runtime (owned by `agentic-realms-npc`); the game starts and terminates minds but does not implement them.
- Any inbound push or signal from the game to a *running* mind (e.g. reactive nudges, combat/conversation triggers); the game only starts and terminates minds and answers their pull/command contract. The running loop is pull-plus-command only.
- NPC behaviors beyond movement — combat, conversation-driven steering, and other autonomous behaviors.
- Richer authentication or authorization (per-caller credentials, mutual TLS, per-route scopes, rate limiting) beyond a single shared-secret bearer token.
- Multi-step path planning, goals, or pathfinding; the move command enacts a single, already-decided one-exit move.
- Any change to how existing reactive, scripted NPC content behaves.
