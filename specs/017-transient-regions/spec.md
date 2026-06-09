# Feature Specification: Transient Regions

**Feature Branch**: `017-transient-regions`  
**Created**: 2026-06-08  
**Status**: Draft  
**Input**: User description: "Transient regions. A transient region is a region that is created entirely on demand. It can be created for a quest or on demand for a group (groups not supported yet) to go have a private mission, or it can be created on demand for some reason we haven't yet predicted. All rooms in a transient realm are durable and can survive a process crash just the same way all other rooms can. Transient regions are provisioned on behalf of a particular user. That region will then purge all of its content once the provision-owner logs off. Note that this is different than the region being empty of players. If no one is in the region, it can still remain provisioned if the provision target is still logged in somewhere else. The rooms in these regions are provisioned upon request. A future optimization may change this so that rooms only exist when entered, but that optimization is out of scope. For the MVP we will simulate a call out to a procedural generator when the transient region is provisioned. So for the initial MVP, it will just use a seed-like function to create a few rooms suitable for testing. The core requirements is that these regions must be durable across process crash the same way any other 'permanent' room is and that all data associated with these regions (current and historical) is purged when the region is destroyed. Regions are destroyed when the provisioning target player logs off, or when a long timeout has passed (60 minutes) to avoid a player staying logged in forever and hoarding resources."

## Clarifications

### Session 2026-06-08

- Q: When a transient region is destroyed with players still inside it, where are they relocated? → A: To the location each player occupied immediately before entering the region (pre-entry location, recorded on entry).
- Q: How long is the grace period before the provision-owner is treated as logged off (tolerating refresh/reconnect)? → A: Approximately 2 minutes.
- Q: What happens when the provision-owner already has an active transient region and another is requested? → A: Reject the new request — exactly one active transient region per owner at a time.
- Q: In the MVP, who triggers provisioning of a transient region? → A: System triggers only — no player-facing command; provisioning is invoked programmatically / by system flows (exercised via system/test invocation in the MVP).

## User Scenarios & Testing *(mandatory)*

A **transient region** is a region created entirely on demand for a single owning user (the *provision-owner*) — for a quest, a future private group mission, or any not-yet-predicted purpose. While it exists it behaves like any other part of the world: its rooms are durable and crash-safe. What makes it *transient* is its lifecycle: it is generated on request, lives only as long as its provision-owner is logged in (subject to a hard 60-minute cap), and when it ends, every trace of it — current and historical — is purged.

### User Story 1 - Provision a transient region on demand and explore it (Priority: P1)

The system provisions a private transient region on behalf of a specific user (the *provision-owner*). For the MVP this is system-initiated — invoked programmatically (a system/test request), not via a player-facing command. The system simulates a call to a procedural generator, which produces a small set of interconnected rooms. The provision-owner is placed into the region and can move between its rooms exactly as they would in the permanent world.

**Why this priority**: This is the enabling capability. Without on-demand provisioning and a navigable result, none of the lifecycle behavior matters. It is the minimum slice that delivers a usable, demonstrable feature.

**Independent Test**: Invoke the provisioning capability (system-initiated) for a logged-in user, confirm a region with several connected rooms is created, the owner lands inside it, and the owner can walk between the generated rooms.

**Acceptance Scenarios**:

1. **Given** a logged-in user with no transient region, **When** the system provisions a transient region on their behalf, **Then** the system generates a small set of interconnected rooms, marks that user as the provision-owner, and places them in the region's entry room.
2. **Given** a freshly provisioned transient region, **When** the provision-owner moves through the region's exits, **Then** they navigate between the generated rooms the same way they would in a permanent region.
3. **Given** the simulated generator produces rooms, **When** the region is provisioned, **Then** all of the region's rooms exist immediately (rooms are not deferred until first entry).
4. **Given** a provision-owner inside a transient region, **When** they observe their surroundings, **Then** the transient rooms are indistinguishable from permanent rooms in look and behavior except for their temporary lifecycle.
5. **Given** a provision-owner who already has an active transient region, **When** the system attempts to provision another on their behalf, **Then** the request is rejected and no second region is created.

---

### User Story 2 - Transient region survives a process crash (Priority: P2)

A transient region has been provisioned and is in use. The server process crashes and restarts. The region and all its rooms are restored intact, and the provision-owner (and any other occupants) can continue exploring without loss of region state.

**Why this priority**: Durability across crashes is an explicit core requirement — transient regions must offer the *same* survival guarantee as permanent rooms. A region that evaporated on every restart would be unusable for quests or missions.

**Independent Test**: Provision a region, populate/enter it, force a process restart, then confirm every generated room still exists, retains its state, and remains navigable.

**Acceptance Scenarios**:

1. **Given** a provisioned transient region whose owner is still logged in, **When** the server process crashes and restarts, **Then** the region and all of its rooms are restored and remain navigable.
2. **Given** a provision-owner standing in a transient room before a crash, **When** the process restarts and they reconnect, **Then** they are still able to occupy and move through the region.
3. **Given** a transient region restored after a crash, **When** its remaining lifetime is evaluated, **Then** the 60-minute cap is measured from the original provisioning time (the crash does not reset or extend the lifetime).

---

### User Story 3 - Region is destroyed and fully purged when its owner logs off (Priority: P2)

When the provision-owner logs off entirely (no remaining active sessions anywhere), their transient region is destroyed and every piece of data associated with it — rooms, contents, and historical records — is purged. Crucially, the region's existence tracks the *owner's login status*, not whether players happen to be inside it: an empty region stays alive while its owner is logged in elsewhere, and a populated region still ends when its owner logs off.

**Why this priority**: Purging all data on destruction is the second explicit core requirement and the defining "transient" behavior. It is what reclaims resources and keeps private missions private.

**Independent Test**: Provision a region, verify it persists while empty as long as the owner stays logged in, then log the owner off completely and confirm the region and all of its associated data are gone with no residue.

**Acceptance Scenarios**:

1. **Given** a transient region with no players inside it, **When** its provision-owner remains logged in (in any session), **Then** the region remains provisioned and is not destroyed.
2. **Given** a provision-owner with multiple concurrent sessions, **When** one session ends but at least one other remains active, **Then** the region is not destroyed.
3. **Given** a provision-owner logged into a session unrelated to the region, **When** that owner has no remaining sessions anywhere (fully logged off), **Then** the region is destroyed and all of its data is purged.
4. **Given** a destroyed transient region, **When** its data is inspected afterward, **Then** no rooms, contents, current records, or historical records associated with it remain.
5. **Given** a provision-owner whose session briefly drops and reconnects (e.g., a page refresh) within the ~2-minute grace period, **When** the reconnect completes, **Then** the region is not destroyed.

---

### User Story 4 - Region is destroyed after the 60-minute lifetime cap (Priority: P3)

Even if a provision-owner stays logged in indefinitely, their transient region is automatically destroyed and purged no later than 60 minutes after it was provisioned, so that a long-lived session cannot hoard region resources forever.

**Why this priority**: A safety/resource-governance backstop. It matters, but only after the primary provisioning, durability, and owner-logoff behaviors exist.

**Independent Test**: Provision a region, keep the owner continuously logged in, advance time past the 60-minute cap, and confirm the region is destroyed and fully purged.

**Acceptance Scenarios**:

1. **Given** a transient region whose owner has stayed logged in continuously, **When** 60 minutes have elapsed since provisioning, **Then** the region is destroyed and all of its data is purged.
2. **Given** a region destroyed by the lifetime cap, **When** the purge completes, **Then** the result is identical to an owner-logoff destruction (no rooms, contents, or history remain).
3. **Given** a region that reaches its lifetime cap while its owner is logged off (logoff and timeout coincide), **When** destruction runs, **Then** the region is torn down exactly once with no error or double-purge.

---

### Edge Cases

- **Occupied region at destruction**: When a region is destroyed (by owner logoff or timeout) while players — including non-owners — are inside it, those players are relocated to the location they occupied immediately before entering the region and told the region has ended, before the region's data is purged. No player is left standing in a purged room.
- **Duplicate provisioning request**: If a provision-owner already has an active transient region, a further provisioning request on their behalf is rejected rather than creating a second region.
- **Non-owner occupants vs. owner logoff**: A non-owner can be inside the region while the owner is elsewhere; the region still ends when the *owner* logs off, evicting those non-owners.
- **Partial provisioning failure**: If the simulated generator fails partway through, no half-built or orphaned region is left behind — provisioning fails cleanly and the requester is informed.
- **Crash before purge completes**: If the owner logs off (or the cap elapses) and the process crashes before the purge finishes, recovery detects that the destruction conditions are already met and completes the purge rather than leaving an orphaned region.
- **Entry during teardown**: Once a region's destruction has begun, no new entry into it is allowed.
- **Crash mid-provisioning**: If the process crashes while a region is still being generated, recovery does not surface a partially-generated region as usable.
- **Owner never enters**: A region whose owner provisioned it but never entered still obeys the same lifecycle (owner-logoff and 60-minute cap) and still purges fully.

## Requirements *(mandatory)*

### Functional Requirements

**Provisioning**

- **FR-001**: System MUST provision a transient region on demand on behalf of a specific user, recording that user as the region's provision-owner. For the MVP, provisioning is system-initiated (invoked programmatically / by system flows or test invocation); there is no player-facing provisioning command.
- **FR-021**: System MUST reject a provisioning request for a provision-owner who already has an active transient region (the MVP supports exactly one active transient region per owner at a time) and surface that the request was rejected.
- **FR-002**: System MUST, at provisioning time, invoke a region generator to produce the region's rooms. For the MVP this generator is simulated by a deterministic, seed-like function that produces a small set (≈3) of interconnected rooms suitable for testing, standing in for a future procedural/external generator.
- **FR-003**: System MUST create all of a transient region's rooms up front at provisioning time. Deferred ("only when entered") room creation is explicitly out of scope.
- **FR-004**: System MUST record, for each transient region, the provision-owner and the provisioning time.
- **FR-005**: System MUST distinguish transient regions and their rooms from permanent regions and rooms, so that transient lifecycle rules apply only to transient ones.
- **FR-006**: System MUST place the provision-owner into the region (an identified entry room) upon successful provisioning.

**Durability**

- **FR-007**: Rooms in a transient region MUST be durable and survive a process crash/restart with the same guarantees as permanent rooms, with no loss of region or room state.
- **FR-008**: After a crash/restart, System MUST restore each transient region whose destruction conditions are not yet met to a navigable state, with its remaining lifetime still measured from the original provisioning time.

**Navigation & occupancy**

- **FR-009**: Players inside a transient region MUST be able to move between its rooms using the same navigation behavior as permanent rooms.
- **FR-010**: A transient region MUST remain provisioned even when it contains no players, for as long as its provision-owner remains logged in (in any session) and the lifetime cap has not elapsed.
- **FR-011**: System MUST prevent new entry into a transient region once its destruction has begun.

**Destruction triggers**

- **FR-012**: System MUST destroy a transient region when its provision-owner is no longer logged in on any session.
- **FR-013**: System MUST treat the provision-owner as logged off only when they have no active sessions anywhere, tolerating a grace period of approximately 2 minutes so that page refreshes and brief transient disconnects do not trigger destruction.
- **FR-014**: System MUST destroy a transient region no later than 60 minutes after it was provisioned, regardless of the owner's login status or in-region activity.
- **FR-015**: Region destruction MUST be idempotent — when multiple conditions trigger destruction of the same region (e.g., logoff and lifetime cap together), the region is torn down exactly once with no error.

**Purge**

- **FR-016**: When a transient region is destroyed, System MUST purge all data associated with it — all of its rooms, their contents, and all current and historical records — leaving no residual data.
- **FR-017**: Purging a transient region MUST NOT affect permanent regions/rooms, permanent world history, or any other transient region.
- **FR-018**: On recovery after a crash, System MUST destroy and purge any transient region whose destruction conditions are already met (owner logged off, or lifetime elapsed) rather than leaving it orphaned.

**Occupant handling & failure**

- **FR-019**: When a transient region is destroyed while players (owner or non-owner) are inside it, System MUST relocate each such player to the location they occupied immediately before entering the transient region, notify any **online** occupants that the region has ended, and only then purge the region's data. (A player who is offline at destruction — e.g., a logged-off owner — receives no live notice; they are simply relocated and find themselves at their pre-entry location on return.)
- **FR-020**: If region generation fails during provisioning, System MUST NOT leave a partially-created or orphaned region; provisioning fails cleanly and the requester is informed.
- **FR-022**: System MUST record each player's pre-entry location when they enter a transient region, to serve as their relocation destination if the region is destroyed while they are inside it. (MVP: because the entry exit is owner-only, the sole occupant is the provision-owner, so this is the single `source_room_id` recorded at provisioning time.)

### Key Entities

- **Transient Region**: A region created on demand and bound to a single provision-owner. Carries a provisioning timestamp and a fixed maximum lifetime (60 minutes). Owns a set of rooms. Distinguished from permanent regions. Lifecycle: provisioned → active → destroyed/purged.
- **Provision-Owner**: The user on whose behalf a transient region exists. The region's continued existence is tied to this user's overall login status (and the lifetime cap) — not to whether any players are currently inside the region.
- **Transient Room**: A durable room belonging to a transient region. Identical to a permanent room in durability and navigation, but purged when its region is destroyed.
- **Region Generator (simulated)**: The on-demand source of a transient region's rooms. In the MVP, a deterministic seed-like function that produces a small, fixed, interconnected room set for testing — a placeholder for a future procedural generator or external generation call.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A logged-in user can request a transient region and be standing in an explorable, multi-room region within 5 seconds of the request.
- **SC-002**: 100% of a transient region's rooms remain present and navigable, with state intact, after a process crash and restart (zero loss).
- **SC-003**: Once a provision-owner's logoff is confirmed — i.e., the ~2-minute reconnect grace (FR-013) elapses without a reconnect — 100% of that region's associated data (rooms, contents, current and historical records) is purged within 1 minute of confirmation, verifiable by the absence of any residual records.
- **SC-004**: A transient region whose owner stays continuously logged in is automatically destroyed and purged within 1 minute of reaching its 60-minute lifetime cap.
- **SC-005**: A transient region remains available for the entire time its owner stays logged in (up to the 60-minute cap) even with zero players inside — demonstrated by successful re-entry after the region has been empty.
- **SC-006**: Destroying a transient region causes zero changes to permanent regions/rooms, permanent history, or other transient regions (no permanent data altered or lost).
- **SC-007**: 100% of players inside a region at destruction time are relocated to their pre-entry location (online occupants receive a clear end-of-region notice) — no player is ever stranded in a purged room.

## Assumptions

- **Provisioning trigger (MVP)**: Provisioning is system-initiated — there is no player-facing provisioning command in the MVP. It is invoked programmatically (e.g., via system/test invocation) on behalf of a specific user, who becomes the provision-owner and is moved into the region. Production triggers such as quest acceptance reuse the same provisioning capability and are out of scope for this feature.
- **Groups out of scope**: The group private-mission use case is acknowledged but not supported; provisioning is per individual user.
- **Simulated generation**: The procedural generator is simulated by a deterministic seed-like function that creates a few interconnected rooms suitable for testing. Real procedural or external generation is out of scope.
- **Eager room creation**: All rooms are created at provisioning time; lazy "rooms exist only when entered" creation is explicitly out of scope (a noted future optimization).
- **Absolute lifetime cap**: The 60-minute cap is measured from provisioning time (an absolute lifetime, not an idle/inactivity timer) and is not reset by crashes or restarts.
- **Logged-off semantics**: "Logged off" means the provision-owner has no active sessions on any device; a grace period of approximately 2 minutes tolerates refreshes and transient disconnects, consistent with the project's existing multi-session presence model.
- **Occupant relocation target**: Players displaced by destruction are returned to the location they occupied immediately before entering the transient region (recorded on entry), which lies in the permanent world.
- **Destroyable history phase**: The project is currently in a phase where the event/history log is destroyable, so purging current and historical data does not require stream-migration tooling.
- **One active region per owner (MVP)**: The MVP supports exactly one active transient region per provision-owner at a time; a further provisioning request while one is active is rejected (FR-021). When an owner logs off, their transient region is destroyed.
- **Permanent regions/rooms unaffected**: Existing permanent regions and rooms, and the seeded world, are unchanged by this feature except for being the fallback destination for displaced occupants.
