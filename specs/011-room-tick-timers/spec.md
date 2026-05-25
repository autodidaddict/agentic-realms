# Feature Specification: Room-Scoped Tick Timers

**Feature Branch**: `011-room-tick-timers`  
**Created**: 2026-05-24  
**Status**: Draft  
**Input**: User description: "Room-scoped timers — a room starts its timer ticks when the population goes from 0 to ≥1 and stops them when the room becomes empty. Suitable grace periods are applied on both transitions to avoid timer-related spam. The base tick rate is configurable and defaults to 1 second; a behavior's tick frequency must be a multiple of this base rate. The room tick is responsible for triggering room-defined behaviors and the behaviors of any object in the room or carried by any player or NPC in the room — i.e., the room timer is the only thing that can fire the `tick` trigger on any object or NPC. A global timer is out of scope."

## Clarifications

### Session 2026-05-24

- Q: Object behaviors data model — add `behaviors` to Object now, or defer? → A: A — add `behaviors` JSONB field to the Object schema in this feature, so US4 ships fully (object-tick dispatch + handoff semantics included).
- Q: Occupancy definition for tick lifecycle (live sessions vs. persisted players)? → A: A — live online players only (Phoenix.Presence). Offline-but-persisted-in-room players DO NOT count as occupants for scheduler start/stop. After server restart, schedulers come back naturally as players reconnect.
- Q: Tick cadence anchor — what is "next fire" relative to? → A: A — last-fire-time-based: `next_fire = last_fire_time + interval`. Drift-free; standard periodic-timer semantics; handles long actions, dropped ticks, and dispatch jitter uniformly.
- Q: Behavior firing order within a single target on the same beat? → A: A — authored order (list position in `behaviors`). Matches feature 009 FR-008a; gives wizards a single mental model across all triggers/targets and lets them deliberately sequence dependent ticks.
- Q: Authoring validation for missing/malformed `interval_ms`? → A: A — strict reject at load time. Missing, null, or non-numeric `interval_ms` on a `tick` behavior raises a clear validator error and the behavior never enters rotation. Defaulting would conceal authoring mistakes.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — A room comes alive when a player enters (Priority: P1)

A player enters a room that has been empty. After a short grace period, the room's tick-triggered behaviors begin firing on schedule. The player sees the room "come alive" — an oil lamp flickers, a tankard is polished, dust motes drift through the air — without ever having to issue a command.

**Why this priority**: This is the MVP slice — without ticks ever firing for a real room, no other story can be demonstrated. It introduces the lifecycle event (occupant count transition 0 → 1), the per-room scheduler, and the dispatch of a single tick-triggered behavior. Every other story builds on this.

**Independent Test**: From a fresh login, the player walks into a room that has at least one `tick`-triggered behavior. After the configured grace period plus the behavior's first scheduled interval, the behavior's action is delivered to the player (e.g., a `say` from the room or a narration). Re-arriving the same player after a brief absence keeps the tick cadence stable (no double-fires).

**Acceptance Scenarios**:

1. **Given** an empty room with a single tick-triggered room behavior configured at a 1-second interval, **When** the first player enters the room, **Then** within roughly the join grace period plus 1 second the behavior's action fires, and continues firing approximately once per second while the player remains.
2. **Given** a room with both a tick-triggered behavior on the room itself AND a tick-triggered behavior on an NPC clone in that room, **When** the first player enters, **Then** both behaviors begin ticking on their own schedules — neither blocks the other and neither requires the player to do anything.
3. **Given** an empty room with NO tick-triggered behaviors, **When** the first player enters, **Then** no scheduler is started for that room and no tick activity occurs (zero waste).

---

### User Story 2 — A room goes quiet when the last player leaves (Priority: P1)

When the last player in a room leaves, the room's tick-driven behaviors stop firing after a grace period. Bystander resources (CPU, log noise, LLM calls for any tick-triggered chat-like actions) drop to zero for that room until a player returns.

**Why this priority**: This is the other half of the lifecycle and the cost-control guarantee. Without it, every room a player has ever visited keeps ticking forever — the system wastes work for empty scenes no one is observing.

**Independent Test**: Enter a room with a tick-triggered behavior, observe at least one tick fire, then leave. After the leave grace period plus a small buffer, the room's tick activity ceases. Re-entering the same room within the leave grace period keeps the tick cadence continuous (no stall); re-entering after the leave grace period resets the schedule cleanly (the tick clock starts over from the join grace plus the configured interval).

**Acceptance Scenarios**:

1. **Given** an occupied room with an active tick-driven behavior, **When** the last player leaves, **Then** after the leave grace period passes the room's tick activity ceases and no further tick-triggered behavior actions are emitted for that room.
2. **Given** a room whose last player just left, **When** another player enters that room within the leave grace period, **Then** the ticking continues without interruption — the schedule is not torn down and restarted.
3. **Given** a room whose last player left more than the leave grace period ago, **When** a player re-enters, **Then** a fresh tick schedule begins (join grace + first interval, exactly as for a first-time arrival).

---

### User Story 3 — A behavior with an N-second tick interval fires every N seconds (Priority: P2)

A wizard authors a tick behavior with an interval that is a multiple of the base tick rate (e.g., 5 seconds for a 1-second base). The behavior fires at the configured cadence in the room — not too fast, not too slow, not skipping.

**Why this priority**: Without this, the only thing the substrate can do is fire every behavior at the base rate, which over-noises rooms and makes the feature unusable for any slower atmospheric beat (e.g., a 30-second "wind moves through the courtyard"). Interval-as-multiple is the authoring lever wizards need.

**Independent Test**: Author a behavior with a 3-second tick interval. Observe over 30 seconds while in the room: the action fires approximately 10 times (within tolerance for the grace period and processing jitter). Author another behavior on the same room at a 5-second interval. Both fire on their own cadence; they don't drift together or step on each other.

**Acceptance Scenarios**:

1. **Given** a behavior with a 3-second tick interval and the base tick rate at 1 second, **When** the room is occupied for 30 seconds, **Then** the behavior's actions fire approximately 10 times (allowing reasonable jitter for grace periods and dispatch).
2. **Given** a behavior whose tick interval is NOT a multiple of the base tick rate (e.g., 0.5s when the base is 1s), **When** the room is authored or loaded, **Then** the system rejects or normalizes the interval per the validation rule (FR-005) and never silently fires it at the wrong cadence.
3. **Given** two behaviors with different tick intervals on the same room, **When** the room is occupied for long enough that both should fire, **Then** each fires on its own cadence and neither is suppressed or delayed by the other's schedule.

---

### User Story 4 — Tick behaviors on NPCs and on objects in the room are driven by the room timer (Priority: P2)

NPCs and objects in the room (or objects carried by any player or NPC currently in the room) can also have tick-triggered behaviors. Those behaviors are driven by the same room timer that drives the room's own behaviors — not by any standalone per-NPC or per-object scheduler.

**Why this priority**: It's what makes the substrate useful beyond ambient room narration: a lit torch crackles every few seconds; a magical amulet pulses; an innkeeper polishes the bar between attending to players. Centralizing this on the room timer also enforces the cost ceiling — a player carrying ten ticking objects through a room doesn't multiply the number of schedulers, just adds more entries to the one room's schedule.

**Independent Test**: Spawn an NPC with a tick-triggered emote behavior into a room. Place an object with a tick-triggered behavior in the same room. Enter the room as a player. Both the NPC's behavior and the object's behavior fire on their own schedules. Pick up the object — its tick behavior continues firing because you are still in the same room. Leave the room while still carrying the object — its tick behavior stops because the player carrying it is no longer in any room with a tick scheduler (until you arrive in a new room, where its behavior gets added to THAT room's schedule).

**Acceptance Scenarios**:

1. **Given** a room containing an NPC with a tick-triggered emote behavior, **When** a player is in the room, **Then** the NPC's emote behavior fires on its configured interval — sourced from the same scheduler that drives the room's own tick behaviors.
2. **Given** a player in a room, carrying an object that has a tick-triggered behavior, **When** the player is in that room, **Then** the object's tick behavior fires from that room's scheduler.
3. **Given** the same player carrying the same ticking object, **When** the player moves to a different room, **Then** the object's tick behavior stops firing in the old room and begins firing in the new room (driven by the new room's scheduler, which starts if necessary).
4. **Given** the same player carrying the same ticking object, **When** the player drops the object in a room and then leaves the room, **Then** the object's tick behavior continues to fire from the room's scheduler as long as another player or NPC is present, and ceases (along with the rest of the room's ticks) after the leave grace period.

---

### User Story 5 — The base tick rate is configurable (Priority: P3)

An operator can adjust the base tick rate via configuration (e.g., 250 ms for snappy testing, 5 s for cost-sensitive deployments) without re-authoring any behavior. Authored intervals must remain multiples of whatever base is configured at startup.

**Why this priority**: It's the dial that lets the game scale from a single-player dev console (where snappy tick cadence makes manual testing pleasant) to a multi-region production deployment (where slower ticks save cost). Without it the base is baked-in and operators have no recourse short of editing code.

**Independent Test**: With the base tick rate set to its default (1 s), confirm a 3-s interval behavior fires three ticks apart. Restart with the base set to 500 ms and confirm the same authored 3-s interval still fires three seconds apart (interval is in time, not in ticks — see FR-005). Change the base to 5 s and confirm a behavior authored with a 1-s interval is rejected/normalized (since 1 s is not a multiple of 5 s).

**Acceptance Scenarios**:

1. **Given** the base tick rate is configured at 500 ms, **When** the system starts, **Then** all room schedulers advance at the configured cadence and ticks behaviors at that resolution.
2. **Given** a base tick rate of 5 s and a behavior authored with an interval of 1 s, **When** the behavior is loaded into a room, **Then** the system rejects it (FR-005) — the operator's configuration cannot be silently bypassed by sub-base authoring.

---

### Edge Cases

- **No tick behaviors anywhere**: A room with no tick-triggered behaviors of its own, no NPCs with tick behaviors, and no objects with tick behaviors MUST NOT start a scheduler when a player enters. (FR-007 — pay-for-what-you-use.)
- **Bursty join/leave**: A player connects, immediately disconnects, immediately reconnects. The system MUST NOT churn schedulers up-and-down for this — the grace periods absorb bursts.
- **Several players enter at once**: Behaviors MUST NOT fire once per player-entered event — the scheduler is per ROOM, not per player, and fires on a single shared cadence regardless of how many players are present.
- **Behavior interval is zero or negative**: The system MUST reject any tick interval that is not a positive multiple of the base rate. Zero or negative authored intervals are an authoring error.
- **Server restart with players in rooms**: After a restart, schedulers must be re-established for every room that currently has at least one player present. The lifecycle should not depend on having observed the original 0 → 1 transition — the scheduler is keyed to "is the room occupied right now," not to a single event.
- **Action takes longer than the interval**: If a tick action is slow (e.g., a future tick-triggered LLM call), the next tick MUST NOT pile up onto the previous one. The scheduler skips a beat rather than fires concurrent overlapping copies of the same behavior.
- **Object held by a player in a room with no scheduler**: If an object's owner is somewhere with no tick scheduler (e.g., a non-existent or scheduler-less room), the object's tick behaviors are simply dormant. They reactivate the next time the player enters a room whose scheduler is running.
- **Object handed off**: If player A in room X drops a ticking object and player B in room X picks it up, the object's tick behavior continues firing from room X's scheduler uninterrupted (the room hasn't changed). If player B then moves to room Y, the behavior follows them to room Y.
- **NPC despawn mid-tick**: If an NPC is removed from the room between scheduled tick firings, its tick behaviors stop firing immediately — even if a tick was already scheduled for it. The scheduler skips entries whose targets no longer exist in the room.
- **Tick fires while a player is mid-`chat` with an NPC**: A tick-driven emote on that same NPC fires through its own private/public delivery path (whatever the action specifies); it MUST NOT cancel, mutate, or interrupt the ongoing chat (FR-020 in feature 010 governs concurrent chat calls, not ticks).
- **Authoring authority for tick behaviors**: Same seed-only authoring discipline as features 009 and 010. The authoring UI (wizard tab) is out of scope here.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST drive periodic `tick`-triggered behaviors via a per-room scheduler. There is one scheduler per active room, and a scheduler exists ONLY for rooms that are currently occupied AND that have at least one tick-triggered behavior in scope (room-level, NPCs in the room, or objects in or carried in the room).
- **FR-002**: A room's tick scheduler MUST be started when the room's **live-session occupant count** (players with an active connection currently in the room — measured via `Phoenix.Presence`, NOT `PlayerState.current_room_id`) transitions from 0 to ≥1, after a configured **join grace period** (default 250 ms). The grace period absorbs rapid reconnect bursts and gives the room a beat of stillness before ambient activity begins. Offline-but-persisted-in-room players DO NOT count as occupants for this purpose (consistent with feature 003b's offline-filter semantics).
- **FR-003**: A room's tick scheduler MUST be stopped when the room's live-session occupant count transitions from ≥1 to 0, after a configured **leave grace period** (default 5 s). If the live-session occupant count returns to ≥1 within the leave grace period, the scheduler continues uninterrupted — its schedule is preserved, not restarted.
- **FR-004**: The **base tick rate** MUST be configurable at the application level. Default is **1 second**. The base rate determines the cadence at which the scheduler advances and the minimum interval that any tick behavior can be authored at.
- **FR-005**: Any tick behavior's authored `interval_ms` MUST be present, MUST be a positive integer, and MUST be a positive integer multiple of the configured base tick rate. The validator MUST reject — with a clear error identifying the offending behavior, the configured base rate, and the offending value — every tick behavior that: (a) omits `interval_ms`; (b) has `interval_ms == null`; (c) has a non-numeric or non-integer `interval_ms`; (d) has a zero or negative `interval_ms`; or (e) has an `interval_ms` that is not an exact positive multiple of the base rate. Rejected behaviors MUST NOT enter active rotation and MUST NOT silently fire at any cadence. There is NO default `interval_ms` — omission is an authoring bug, not a shortcut.
- **FR-006**: A room's tick scheduler MUST drive: (a) tick behaviors attached to the room itself; (b) tick behaviors attached to every NPC clone currently in the room; (c) tick behaviors attached to every object currently in the room or currently held by any player or NPC in the room. No other process or schedule may fire a `tick` trigger on an object or NPC — the room scheduler is the only producer.
- **FR-007**: If a room is occupied but contains no tick-triggered behaviors in scope (no room behaviors, no in-room NPC behaviors, no in-room or in-inventory object behaviors), the system MUST NOT start a scheduler for it. Schedulers are created on demand to bound per-room cost.
- **FR-008**: Each scheduled tick MUST evaluate all tick behaviors whose authored interval has elapsed since their last fire (or since the scheduler started for a behavior that has never fired), and fire each matching behavior's actions exactly once for that beat. The "next fire" of a behavior is computed as `last_fire_time + interval_ms` — drift-free — NOT as `fire_completed_time + interval_ms` or as a beat-aligned grid offset from scheduler start. This means a behavior whose action runs late is followed by a tick on its ORIGINAL schedule (not stretched forward by the lateness, and not snapped to a global grid). Two behaviors that "fall due" on the same beat fire in a deterministic order (FR-008a).
- **FR-008a**: When multiple tick behaviors fall due on the same beat, fire order MUST be deterministic and as follows: (i) across target TYPES — room behaviors first, then NPC behaviors (ordered by the NPC's stable serial), then object behaviors (ordered by object id); (ii) within a single target — **authored order**, i.e., the order behaviors appear in that target's `behaviors` list. This mirrors feature 009 FR-008a's room-before-NPC convention and gives wizards a single predictable ordering model across all triggers and targets, including the ability to deliberately sequence dependent ticks (e.g., a setup tick followed by a state-using tick).
- **FR-009**: A tick behavior's action set MUST be drawn from the same authored vocabulary as feature 009 (currently `say`) and any actions added in future features. Tick is a TRIGGER; the action layer is shared substrate.
- **FR-010**: If a tick action is in flight (e.g., a long-running LLM call introduced by a future feature) and the next tick for the same behavior would fall due, the scheduler MUST skip the new tick rather than queue or overlap firings. Stale ticks are dropped. Once the in-flight action completes, `last_fire_time` is updated to the moment the action was originally DISPATCHED (the start of the fire that just completed) — NOT to the moment it finished — preserving the drift-free cadence from FR-008. The next eligible tick is then the first scheduler beat at or after `last_fire_time + interval_ms`.
- **FR-011**: After a server restart, schedulers MUST re-establish naturally as players reconnect and rejoin their rooms — driven by the same `Phoenix.Presence` join events that drive the normal 0 → 1 transition (FR-002). No special restart-recovery path is needed: a freshly-started node has an empty Presence table; as live sessions return, room schedulers come up exactly as if those rooms had just been newly entered. Lifecycle is bound to live presence, not to any persisted "is anyone supposed to be here" signal.
- **FR-012**: A scheduler MUST NOT fire tick behaviors for targets that have left its scope between schedule time and fire time. If an NPC has been despawned, or an object has moved to a different room (or to a player who has moved to a different room), or a player has left while carrying an object, the corresponding tick action MUST be skipped silently.
- **FR-013**: Tick behaviors MUST NOT alter the privacy or delivery semantics of their actions. A `say` action attached to a room's tick behavior is delivered exactly as feature 009 specifies for a room-attached `say`; the trigger source (`tick` vs. `player_entered`) does NOT change visibility.
- **FR-014**: The tick scheduler MUST tolerate dispatch jitter. A behavior with a 10 s interval MUST NOT be expected to fire on exact 10-second wall-clock boundaries — only at-or-after 10 s since its last fire, within a small dispatch tolerance.
- **FR-015**: Per-room schedulers MUST be cluster-friendly using the same discovery substrate already in the project (feature 010's Horde-backed registry pattern), so a player who reconnects to a different node finds the existing scheduler for any rooms they were occupying. Schedulers MUST NOT be node-local in a way that prevents migration.
- **FR-016**: Global / world-wide tickers are explicitly OUT OF SCOPE for this feature. Anything that would require ticking "everywhere at once" (e.g., a day/night cycle, an ambient-economy update) is left to a future feature with its own scheduler.
- **FR-017**: Objects MUST carry a `behaviors` attribute with the same shape as feature 009's room/NPC `behaviors` (a list of `{trigger, actions}` maps, with `tick` adding an `interval_ms` field). The attribute is authored directly on the object — there is no separate "object blueprint" notion in this feature. Empty list (`[]`) is the default and represents an object with no behaviors. The full object-tick dispatch path (carry, drop, room change, scheduler attach/detach) is implemented in this feature per US4.

### Key Entities *(include if feature involves data)*

- **Room Tick Scheduler**: A volatile, in-memory, per-room scheduler that drives `tick`-triggered behaviors for everything in scope for that room. Attributes: room id, base tick rate, set of in-scope behavior targets (room itself, NPC clones in the room, objects in or held within the room), per-target last-fire timestamps. Created on demand when the room transitions to occupied (and has at least one tick behavior in scope); torn down after the leave grace period when the room transitions to empty.
- **Tick Behavior**: A behavior whose trigger is `tick`. Carries an authored interval (in milliseconds, MUST be a positive multiple of the configured base tick rate) plus the same action list every other behavior uses. May be attached to a room, an NPC blueprint (and inherited by clones), or an object.
- **Tick Beat**: A single advance of a room's scheduler. On each beat, the scheduler evaluates which in-scope tick behaviors have an interval elapsed since their last fire; eligible behaviors fire their actions in the order specified by FR-008a.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After a player enters a previously empty room with a 1-second tick behavior, the first tick action is delivered within approximately the join grace period plus the configured interval (default ~1.25 s for a 1 s interval and 250 ms join grace).
- **SC-002**: After the last player leaves a room, tick activity for that room ceases within the leave grace period plus the base tick rate (default ~6 s for a 1 s base and 5 s leave grace). A short audit measures zero tick-driven log entries for that room after this window.
- **SC-003**: With the base tick rate at the default and a 3-second tick behavior, across a 60-second observation window the behavior fires 20 ± 1 times. (Tolerance allows for grace periods at the start and end of the window.)
- **SC-004**: With NO tick behaviors anywhere in a player's current room, NO NPC ticks in scope, and NO carried/in-room object ticks in scope, the player's session creates zero per-room schedulers and consumes no tick-related CPU beyond the lifecycle check itself.
- **SC-005**: An authored tick behavior with a missing, null, non-integer, zero/negative, or non-multiple `interval_ms` is rejected at load time with an error that identifies the offending behavior, the configured base rate, and the offending value (when applicable). Across the project's seed plus any test fixtures, zero invalid tick behaviors enter active rotation; the validator's reject path is exercised by tests for each of the five invalid shapes (missing, null, non-numeric, non-positive, non-multiple).
- **SC-006**: A player carrying an object with a tick behavior moves from room A to room B; the object's tick behavior pauses for room A and resumes from room B's scheduler within at most one base tick beat. Across 10 such transitions, no tick fires from both rooms simultaneously.
- **SC-007**: A simulated server restart while two rooms each have at least one player session results in tick schedulers being re-established for both rooms within roughly the join grace period of each player's reconnect — driven by Presence join events on reconnect, not by any persisted occupancy snapshot. Tick-driven log entries resume in each room without manual intervention.
- **SC-008**: A tick-driven action that takes longer than its behavior's interval to complete does NOT cause overlapping invocations. Across 10 such cases, the next fire is observed only AFTER the prior fire's action returns, and only at the next scheduler beat where the elapsed-since-last-fire exceeds the configured interval.

## Assumptions

- **Seed-only authoring in this feature**: tick behaviors are authored via the seed file or via blueprint creation commands (same path as feature 009 behaviors). A wizard UI for editing tick intervals is a later feature.
- **Behavior schema extends the feature 009 substrate**: a tick behavior is a behavior map with `"trigger": "tick"` and an additional `"interval_ms"` field, alongside the same `"actions"` list shape. The validator accepts/rejects the new trigger and interval per FR-005.
- **Default grace periods**: join grace 250 ms; leave grace 5 s. These are operator-configurable. The defaults assume modest player traffic and prioritize a "things settle before they happen" feel.
- **Default base tick rate**: 1 second. This balances responsive ambient activity against scheduler overhead. Tests override to a smaller value (e.g., 50 ms) so tick tests run quickly without artificial latency.
- **Object behaviors are a new persistent attribute**: per FR-017, the existing `Object` schema gains a `behaviors` JSONB field (default `[]`) with the same shape as feature 009's room/NPC behaviors. Object behaviors are authored directly on the object row — there is no separate "object blueprint" notion in this feature. (Object blueprints, with inheritance to spawned objects, can be a later feature; the field shape will match.)
- **Carried/inventory objects belong to the room of their carrier**: for tick-scope purposes, an object held by a player in room X is "in" room X. The carrier's current room defines the scope. (This is consistent with the existing inventory query model.)
- **No persisted tick state**: the scheduler's per-behavior last-fire timestamps are volatile. A server restart resets all schedules — tick behaviors begin firing fresh from the new scheduler start time (join grace + interval), not from where they were in the prior process.
- **Tick triggers are independent of `player_entered` / `player_left`**: a room may have any mix of triggers; tick co-exists alongside the existing event-driven triggers without coordination beyond shared action execution.
- **Action-mode parity with feature 009/010**: tick actions render via the same paths as their event-triggered counterparts. A `say` triggered by a tick at room scope renders as `:room_speech` exactly as it does today; an emote action (added in a separate feature) will follow the same rule.
- **One scheduler per room, not per BEAM node**: when multiple nodes are in a cluster, the scheduler for a given room lives on exactly one node (per Horde uniform distribution). Cross-node access to the scheduler is transparent — same pattern as feature 010's `NPCChat.Conversation`.
- **Performance budget**: a room with 10 in-scope tick behaviors and a 1 s base rate must consume on the order of microseconds of CPU per beat (essentially: a few map lookups and a small number of function calls). LLM-bound actions, when introduced in a later feature, will dominate cost — the scheduler itself should be a non-factor.
