# Feature Specification: Player Communication — Say, Emote, Whisper

**Feature Branch**: `004-player-communication`
**Created**: 2026-05-19
**Status**: Clarified (5/5 questions resolved 2026-05-19)
**Input**: User description: "Add player-to-player communication on top of the persisted world from 003. Players in the same room can speak and emote and see each other's utterances in real time; players can also whisper to a specific named player privately. Communication is transient and room-scoped (except whisper); it does not mutate world state."

## Clarifications

### Session 2026-05-19

- Q: How should utterances (say / emote / tell / whisper) be persisted? → A: Transient only — PubSub-only delivery, no event-store entry; players who weren't online or in the room when an utterance was sent never see it; tells to offline recipients are refused. Mirrors feature 003's UI-event architecture and keeps this feature's scope minimal. Chat history, if ever needed, will be a separate future feature.
- Q: How should `tell` and `whisper` resolve the `<recipient>` token to a player? → A: Case-insensitive exact match against the display name. Both verbs use the same rule. Duplicate display names (case-insensitively) MUST be refused as ambiguous; no prefix or fuzzy matching.
- Q: When a `tell` recipient resolves to a real player who currently has zero connected sessions, what should happen? → A: Refuse with a neutral "could not be delivered" entry that acknowledges the recipient exists but does NOT reveal whether they are online, offline, or in any particular room. Same refusal phrasing is used regardless of whether the recipient is offline now or disconnects mid-delivery.
- Q: What is the per-utterance text length cap? → A: 500 characters. Submissions over the cap MUST be refused with a refusal entry; the system MUST NOT silently truncate. Applies uniformly to say, emote, tell, and whisper.
- Q: What should happen when a player tells or whispers to themselves? → A: Refuse with a refusal entry (e.g., "You can't tell yourself.") for both verbs. No broadcast, no self-recipient entry.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Player Speaks Aloud in a Room (Priority: P1)

An authenticated player standing in a room types `say hello there` (or the apostrophe shortcut `'hello there`). Every other player currently in that same room sees a speech log entry attributed to the speaker; the speaker sees a confirmation entry in their own log. Players in adjacent or other rooms see nothing.

**Why this priority**: Speech is the foundational social verb. Without it, the multi-player aspect of the persisted world from feature 003 — where players can already see each other arrive, leave, and manipulate objects — remains observable but mute. Every other communication verb in this feature (emote, whisper) is a variation on the same room-scoped broadcast plumbing, so shipping `say` first proves out the substrate.

**Independent Test**: With two LiveView sessions in the same room, submit `say <text>` from session A and verify session B's log appends a speech entry with the speaker's name and the spoken text within 100 ms, while a third session in a different room receives nothing.

**Acceptance Scenarios**:

1. **Given** two players A and B in the same room, **When** A submits `say hello`, **Then** B's log appends a speech entry attributing the utterance to A and showing the text `hello`, and A's log appends a confirmation entry showing what A said.
2. **Given** two players A and B in different rooms, **When** A submits `say hello`, **Then** B's log is unchanged.
3. **Given** a player alone in a room, **When** they submit `say hello`, **Then** only their own confirmation entry appears (no broadcast to any other player).
4. **Given** an authenticated player, **When** they submit `say` with no text (or only whitespace), **Then** no broadcast occurs and the log appends a refusal entry indicating that nothing was said.
5. **Given** a player with two concurrent sessions in the same room, **When** they submit `say hello` from session 1, **Then** session 1 sees the actor-side confirmation entry and session 2 sees the witness-side speech entry (mirroring the multi-session pattern from 003).

---

### User Story 2 - Player Performs an Emote (Priority: P2)

A player types `emote waves at the fire` (or one of the aliases `me waves at the fire`, `:waves at the fire`). Every player in the room — **including the actor** — sees a third-person narration entry such as `Alice waves at the fire.` in their narrative log.

**Why this priority**: Emotes add expressiveness that pure speech cannot — body language, tone, action narration — and they materially change how the world feels inhabited. They reuse the same room-scoped broadcast as `say` but with a distinct rendering, so they are cheap to add once `say` is shipped. They are P2 because the world remains socially functional without them.

**Independent Test**: With two sessions in the same room, submit `:waves` from session A and verify both A and B see a third-person narration entry beginning with A's display name.

**Acceptance Scenarios**:

1. **Given** two players A and B in the same room, **When** A submits `emote waves at the fire`, **Then** both A's and B's logs append a narration entry rendered as `<A's display name> waves at the fire.` (with a trailing period if the text does not already end in `.`, `!`, or `?`).
2. **Given** a player, **When** they submit `emote` with no text, **Then** no broadcast occurs and the log appends a refusal entry.
3. **Given** the aliases `me` and `:`, **When** a player submits `me bows` or `:bows`, **Then** the result is identical to `emote bows`.

---

### User Story 3 - Player Tells Another Player Privately Across Rooms (Priority: P3)

A player types `tell alice meet me by the well` (or the alias `t alice meet me by the well`). The named recipient — and only the named recipient — sees a private tell entry attributed to the sender, regardless of which rooms the sender and recipient are in. The sender sees a confirmation entry. No other player in either room receives anything.

**Why this priority**: Cross-room private messaging is the basic out-of-band coordination channel — the "DM" of a MUD. Unlike whisper, it does not depend on physical co-location, so players scattered across the map can agree to meet, ask each other questions, or strategize without first having to track each other down. Tell is P3 because the world remains socially functional with only same-room communication, but cross-room coordination is very awkward without it.

**Independent Test**: With two sessions A and B placed in *different* rooms, submit `tell B hi` from A and verify B's log shows a private tell entry from A within 100 ms, A's log shows a confirmation, and any third session in either room is unchanged.

**Acceptance Scenarios**:

1. **Given** players A and B in different rooms and a third player C in either of those rooms, **When** A submits `tell B hi`, **Then** B's log appends a private tell entry attributing `hi` to A, A's log appends a confirmation entry showing what they told B, and C's log is unchanged.
2. **Given** players A and B in the *same* room, **When** A submits `tell B hi`, **Then** A and B receive the same entries as in scenario 1; sharing a room does not change tell's behavior. No other player in the room receives the tell.
3. **Given** a player A, **When** A submits `tell nobody hi` where no player matches `nobody`, **Then** no message is delivered and A's log appends a refusal entry indicating the recipient was not found.
4. **Given** a player A, **When** A submits `tell B` with no message text, **Then** no message is delivered and the log appends a refusal entry.
5. **Given** a player A with two concurrent sessions, and player B (in a different room) with two concurrent sessions, **When** A submits `tell B hi` from session 1, **Then** A's session 1 sees the confirmation, A's session 2 sees nothing, and *both* of B's sessions see the tell entry.
6. **Given** a player A, **When** A submits `tell A hi` targeting themselves, **Then** the system refuses with a self-target refusal entry (e.g., "You can't tell yourself.") and produces no recipient-side entry. The same rule applies to self-whisper in US4.

---

### User Story 4 - Player Whispers Privately to Another Player in the Same Room (Priority: P4)

A player types `whisper alice meet me by the well` (or the alias `w alice meet me by the well`) while both players are in the same room. The named recipient sees a private whisper entry attributed to the sender; the sender sees a confirmation entry. No other player in the room receives the content of the whisper. If the recipient is not in the sender's current room, the whisper is refused — for cross-room private messaging, the sender should use `tell` (US3) instead.

**Why this priority**: Whisper is the intimate, physically-grounded counterpart to `tell`: it implies the speaker and recipient are close enough to lean in and lower their voice. Mechanically it is a stricter-scope variant of tell, so once tell ships, whisper is a small addition. It is P4 (below tell) because tell already covers the practical "send a private message" need; whisper exists primarily for roleplay flavor and to leave room for future affordances like "nearby players notice you whispering but don't hear the content."

**Independent Test**: With three sessions — A, B, and C, all in the same room — submit `whisper B hi` from A and verify B's log shows a private whisper entry from A, A's log shows a confirmation, and C's log is unchanged. Then move C to another room, repeat with `whisper C hi` from A, and verify A receives a "not nearby" refusal.

**Acceptance Scenarios**:

1. **Given** players A, B, and C all in the same room, **When** A submits `whisper B hi`, **Then** B's log appends a private whisper entry attributing `hi` to A, A's log appends a confirmation entry showing what they whispered to B, and C's log is unchanged.
2. **Given** players A and B in *different* rooms, **When** A submits `whisper B hi`, **Then** no message is delivered, B's log is unchanged, and A's log appends a refusal entry indicating B is not in the same room (and optionally hinting at `tell` as the cross-room alternative).
3. **Given** a player A, **When** A submits `whisper nobody hi` where no player matches `nobody`, **Then** no message is delivered and A's log appends a refusal entry indicating the recipient was not found. The refusal MUST NOT reveal whether `nobody` exists in some other room.
4. **Given** a player A, **When** A submits `whisper B` with no message text, **Then** no message is delivered and the log appends a refusal entry.
5. **Given** a player A, **When** A submits `whisper A hi` targeting themselves, **Then** the system refuses with a self-target refusal entry; no broadcast, no recipient-side entry. (Mirrors US3 scenario 6.)

---

### Edge Cases

- Very long utterances: resolved — text length is capped at 500 characters; over-cap submissions are refused (see FR-026), never silently truncated.
- Rate limiting per player: **deferred** to planning phase. v1 default is **no per-player rate limit** — submissions are processed as fast as PubSub can fan them out. Revisit only if abuse is observed in practice (e.g., a "flood detected, slow down" refusal threshold could be added later without changing the rest of the model).
- What happens when the speaker moves rooms between submission and broadcast? Should the utterance go to the room they were in at submission time or arrival time? Recommendation: the room at the moment the command is accepted; the speaker cannot be in two rooms.
- Recipient mid-delivery disconnect for tell or whisper: resolved by FR-022 (transient) + FR-016 — delivery is best-effort PubSub with no retry. If a recipient session disconnects between the sender's command acceptance and its own PubSub processing, the message is silently dropped for that session; the sender has already received their actor-side confirmation and is not notified.
- Offline tell recipient at submission: resolved by FR-016 — neutral "could not be delivered" refusal.
- How is text rendered safely? All user-provided text MUST be HTML-escaped before rendering in the log; no markup is interpreted.

## Requirements *(mandatory)*

### Functional Requirements

**Command parsing**:

- **FR-001**: System MUST parse `say <text>` and the apostrophe shortcut `'<text>'` as a Say command. Leading/trailing whitespace in `<text>` MUST be trimmed.
- **FR-002**: System MUST parse `emote <text>`, `me <text>`, and `:<text>` as an Emote command.
- **FR-003**: System MUST parse `tell <recipient> <text>` and the alias `t <recipient> <text>` as a Tell command, where `<recipient>` is a single whitespace-delimited token.
- **FR-004**: System MUST parse `whisper <recipient> <text>` as a Whisper command, where `<recipient>` is a single whitespace-delimited token. Whisper and Tell are distinct commands with distinct scope rules (see FR-016 and FR-020); `tell` MUST NOT be accepted as a whisper alias and vice versa. (Implementation note 2026-05-19: a `w` alias was originally specified but conflicted with feature 003's `w`-for-west movement shortcut; resolved in favor of the existing movement convention. Use the full word `whisper`.)

**Say behavior**:

- **FR-005**: On Say with non-empty text, System MUST broadcast a speech utterance to every player currently in the speaker's room **other than the speaker**, rendered in each recipient's log as a speech entry attributed to the speaker's display name.
- **FR-006**: On Say, the speaker's originating session MUST append an actor-side confirmation entry showing what they said. Other concurrent sessions of the speaker that are in the same room MUST receive the witness-side broadcast (matching the multi-session pattern established in feature 003 spec §Clarifications Q5).
- **FR-007**: On Say with empty or whitespace-only text, System MUST refuse the command and append a refusal entry to the originating session's log; no broadcast occurs.

**Emote behavior**:

- **FR-008**: On Emote with non-empty text, System MUST broadcast a narration utterance to every player currently in the actor's room, **including the actor**, rendered as `<display name> <text>` with a trailing period if `<text>` does not already end in `.`, `!`, or `?`.
- **FR-009**: On Emote with empty or whitespace-only text, System MUST refuse the command and append a refusal entry; no broadcast occurs.

**Recipient resolution (shared by Tell and Whisper)**:

- **FR-010**: System MUST resolve `<recipient>` to a player by **case-insensitive exact match** against the display name. Tell and Whisper MUST use this same rule. If two or more players share a display name (compared case-insensitively), the command MUST be refused as ambiguous with a refusal entry naming the recipient string the player typed. Resolution MUST NOT use prefix or fuzzy matching.
- **FR-010a**: If `<recipient>` resolves to the sender themselves (i.e., the resolved player id equals the sender's player id), Tell and Whisper MUST be refused with a self-target refusal entry. No broadcast occurs, no recipient-side entry is produced. Applies uniformly to both verbs.

**Tell behavior** (cross-room private):

- **FR-011**: On successful Tell resolution with non-empty text, System MUST deliver a private tell utterance to **all** of the recipient's currently-connected sessions and **only** to those sessions. No other player MUST receive the utterance.
- **FR-012**: Tell delivery is **independent of the sender's and recipient's current rooms** — the message is delivered regardless of whether they share a room and regardless of which rooms either occupies.
- **FR-013**: On Tell, the sender's originating session MUST append an actor-side confirmation entry showing what they told the recipient and to whom. Other concurrent sessions of the sender MUST NOT receive any tell entry (mirrors the actor-side multi-session rule from feature 003).
- **FR-014**: On Tell with no matching recipient, System MUST refuse and append a refusal entry naming the unresolved recipient.
- **FR-015**: On Tell with empty or whitespace-only message text, System MUST refuse and append a refusal entry.
- **FR-016**: On Tell where the recipient resolves but has zero connected sessions, System MUST refuse the command with a neutral refusal entry (e.g., "Your message could not be delivered.") that acknowledges nothing about the recipient's online status, room, or any other state beyond the failure itself. The same refusal phrasing applies whether the recipient was already offline at submission or all their sessions disconnect mid-delivery; sender-side disconnect or mid-flight delivery failures are best-effort and never retried (consistent with the transient model of FR-022).

**Whisper behavior** (same-room intimate):

- **FR-017**: On successful Whisper resolution with non-empty text, System MUST deliver a private whisper utterance to **all** of the recipient's currently-connected sessions that are in the sender's current room, and **only** to those sessions. No other player in the room MUST receive the utterance.
- **FR-018**: On Whisper, the sender's originating session MUST append an actor-side confirmation entry showing what they whispered and to whom.
- **FR-019**: On Whisper with no matching recipient anywhere in the world, System MUST refuse and append a refusal entry naming the unresolved recipient. The refusal MUST NOT reveal which room (if any) the named player occupies.
- **FR-020**: On Whisper where the recipient resolves but is **not in the sender's current room**, System MUST refuse and append a refusal entry indicating the recipient is not nearby. The refusal MAY hint at `tell` as the cross-room alternative.
- **FR-021**: On Whisper with empty or whitespace-only message text, System MUST refuse and append a refusal entry.

**Persistence and history**:

- **FR-022**: Utterances of every kind (say, emote, tell, whisper) MUST be transient — delivered via the same real-time PubSub transport as the witness UI events from feature 003 and never appended to the durable event log or any other persistence layer. No utterance history is queryable after delivery.
- **FR-023**: Players who join a room, come online, or open a new session after an utterance was broadcast MUST NOT see that prior utterance — including tell entries directed at them while they were offline.

**Safety and rendering**:

- **FR-024**: All player-supplied text in utterances MUST be HTML-escaped before rendering in any log entry. No HTML, markdown, or other markup is interpreted.
- **FR-025**: Speech, emote, tell, and whisper entries MUST each be visually distinguishable from each other and from the existing log entry types established in feature 003 (room descriptions, confirmations, refusals, witness events, system messages). Tell and whisper entries MUST be clearly marked as private so the recipient does not confuse them with public speech.
- **FR-026**: Player-supplied utterance text MUST be capped at **500 characters** (measured after the trimming defined in FR-001/FR-002/FR-003/FR-004). Submissions whose text exceeds the cap MUST be refused with a refusal entry indicating the limit was exceeded; the system MUST NOT silently truncate, MUST NOT broadcast the over-cap text, and MUST apply the cap uniformly across say, emote, tell, and whisper.

### Key Entities

- **Utterance** (transient — not persisted): a single act of speech, narration, or private message. Attributes: speaker (player id and display name at time of utterance), kind (`:say` / `:emote` / `:tell` / `:whisper`), room id (the speaker's room at the moment of acceptance — used to scope `:say`, `:emote`, and `:whisper` delivery; informational only for `:tell`), recipient player id (present iff kind is `:tell` or `:whisper`), text, timestamp. Carried over the same real-time transport as feature 003's UI events; never appended to the event store.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: From the moment a Say or Emote command is accepted by the speaker's session, every same-room recipient session sees the corresponding log entry within 100 ms p95 (matching the witness-event latency target from feature 003).
- **SC-002**: Zero cross-room leakage: for any Say or Emote, no player whose current room differs from the speaker's room receives the utterance.
- **SC-003**: Zero non-recipient leakage: for any Tell or Whisper, no player other than the sender (in their originating session) and the resolved recipient (across the recipient's eligible sessions per FR-011 / FR-017) receives the utterance.
- **SC-003a**: Whisper scope correctness: for any Whisper where the resolved recipient is not in the sender's current room, the message MUST be refused and zero recipient sessions receive it.
- **SC-004**: 100% of empty or whitespace-only Say/Emote/Whisper submissions produce a refusal entry and never produce a broadcast.
- **SC-005**: 100% of submitted text is HTML-escaped on render — no player-supplied text causes markup to be interpreted in another player's log.

## Assumptions

- Feature 003 (persisted world with rooms, occupants, and same-room PubSub broadcasting) is the substrate. The "room:<id>" topics and per-player session subscriptions established there are reused for Say and Emote.
- Player display names come from the existing Account/Player model established in feature 002 and are stable for the lifetime of a session.
- No persistent chat history in this feature. Utterances are real-time only (locked by FR-022).
- No moderation, profanity filtering, blocking, muting, or admin-controlled silencing in this feature. These can be added later without changing the broadcast model.
- No cross-room shouting (`shout` / global channels) in this feature. Communication scope is room-local for Say and Emote, same-room player-to-player for Whisper, and unrestricted player-to-player for Tell.
- Whisper and Tell are treated as a paired set of verbs differing only in scope: Whisper is the in-fiction, same-room intimate variant (potential future affordances: "nearby players notice you whispering but don't hear the content"); Tell is the out-of-band, anywhere-to-anywhere private channel. Their recipient-resolution and refusal semantics are deliberately kept symmetric (per FR-010) so the difference between the two is only about *where* delivery is allowed.
- No voice or emoji-specific affordances. Text only, rendered in the same narrative log as feature 003.
- Desktop web only, mirroring the scope of features 001 / 002 / 003.
- The wizard view introduced in feature 001 is unaffected by this feature.
