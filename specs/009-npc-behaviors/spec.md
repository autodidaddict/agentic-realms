# Feature Specification: NPC and Room Behaviors (Triggers + Actions, Minimal Set)

**Feature Branch**: `009-npc-behaviors`
**Created**: 2026-05-24
**Status**: Draft
**Input**: User description: "Introduce a behavior system for NPCs and rooms. Behaviors are authored as data — a list of (trigger, [actions]) tuples attached to either an NPC blueprint or a room. Two triggers ship in this feature: `player_entered` (fires when a player arrives in the room) and `player_left` (fires when a player leaves the room). One action ships: `say <text>` which emits a speech utterance from the entity the behavior is attached to (the NPC clone for NPC-blueprint behaviors, the room itself for room behaviors). The speaker is implicit from the attach point — wizards don't specify a speaker. This feature lifts feature 007's FR-018 restriction that NPCs cannot speak. Authoring is seed-only in this feature (no wizard tab yet — that's a later feature). The seed extends Garrick's blueprint with a `player_entered → say \"Welcome to the Stone Atrium.\"` behavior so the feature is demonstrable from a fresh login. Behaviors on NPC blueprints are inherited by clones at spawn time via the full-copy semantics already established in feature 008."

## Background

Feature 007 introduced NPCs as inert room-bound entities ("they cannot move, speak, participate in combat, or do anything else other than exist"). Feature 008 split NPCs into authored blueprints and in-world clones, with full-copy semantics at spawn time. This feature gives NPCs (and rooms) their first dynamic behavior: they respond to player arrival and departure by emitting speech.

The shape of the behavior system is **data, not code**: a behavior is a `(trigger, [actions])` tuple. Triggers and actions are drawn from a small, well-defined vocabulary owned by the core team. The wizard-tab feature (a later feature) will let non-engineer content authors compose these primitives via natural language; this feature ships the substrate they will sit on, authored via the existing seed mechanism only.

The minimum useful primitive set in this feature is **two triggers + one action** — enough for the canonical "greeter NPC" scenario the user described: "when a player enters the room, say 'hello'" and "when a player leaves the room, say 'goodbye'." Future features will expand the primitive vocabulary (more triggers like `on_examine`, more actions like `emote`, `give`, `move_clone`) as concrete scenarios demand them.

**Two attach surfaces**: behaviors live either on an NPC blueprint (where they are inherited by every clone of that blueprint at spawn time, per feature 008's full-copy semantics) or directly on a room. The speaker of a `say` action is implicit from the attach point — an NPC clone speaks when the behavior was authored on its blueprint; the room itself speaks when the behavior was authored on the room. Authors never specify a speaker.

**Scope discipline**: only `player_entered` / `player_left` / `say` ship. All other authoring primitives (additional triggers, additional actions, behavior removal, behavior editing, the wizard tab) are explicitly out of scope and tracked for later features.

## Clarifications

### Session 2026-05-24

- Q: How are behavior-sourced speech entries rendered relative to feature 004's player speech entries? → A: Three distinct log entry kinds: `:speech` (player, unchanged), `:npc_speech` (new — NPC-clone speakers, rendered with the clone's display name, e.g., `Garrick the Innkeeper says, "Welcome."`), and `:room_speech` (new — room-attached behavior output, rendered WITHOUT any speaker attribution — just the line text itself, as ambient narration with no "The room says" framing). The distinct kinds also serve as forward affordance for future trigger types like `on_player_said` / `on_npc_said` that need to filter by the speech's origin.
- Q: When both a room and an NPC have behaviors on the same trigger that fire for the same player movement, in what order do their entries appear in the player's log? → A: Room narration first, then NPC speech. The room sets the scene; then the characters in the scene react. Applies to both `player_entered` (room narration before NPC greeting) and `player_left` (room narration before NPC farewell).
- Q: Does the leaving player receive their own goodbye speech entry? And how is room narration scoped vs. NPC speech? → A: Two distinct delivery rules by entry kind:
  - `:npc_speech` follows feature 004's player-`say` targeting — delivered to ALL player sessions in the speaker's room (the triggering player + other players in that room + each player's multiple concurrent sessions). For `player_left`, the leaving player IS treated as "still in the source room" for this delivery so they receive the goodbye (FR-017 honored).
  - `:room_speech` is delivered ONLY to the player whose movement triggered the behavior, NEVER to other players in the room. Otherwise, a player standing in the Atrium while people come and go would be spammed by room narration on every arrival and departure — irritating noise. Room narration is personal to the player whose action caused it.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - An NPC greets a player who enters its room (Priority: P1)

A player walks into the Stone Atrium where Garrick the Innkeeper is standing. The narrative log displays a speech entry from Garrick: `Garrick the Innkeeper says, "Welcome to the Stone Atrium."` The player did not type any command to trigger this; Garrick spoke because the behavior `player_entered → say "Welcome to the Stone Atrium."` was authored on his blueprint and fired the moment the player arrived in the same room.

**Why this priority**: This is the canonical greeter scenario the user explicitly named when scoping the feature. It exercises the full behavior pipeline end-to-end: trigger detection (player arrival), entity-resolution (which NPCs are in the destination room), behavior execution (the `:say` action), and rendering (a `:speech` log entry). Until this works, the feature has shipped nothing player-visible. Every other story is a variant of this primary path.

**Independent Test**: From a fresh world (`mix ecto.reset`), log in as a new player. Once placed in the Stone Atrium, the narrative log MUST include a speech entry whose actor is `Garrick the Innkeeper` and whose body is `Welcome to the Stone Atrium.` The entry MUST appear without any explicit player command. The same entry MUST appear for any second player who arrives in the Atrium later; it MUST NOT appear when a player moves between rooms that do NOT contain Garrick.

**Acceptance Scenarios**:

1. **Given** a seeded world where Garrick's blueprint has `player_entered → say "Welcome to the Stone Atrium."` attached, **When** a fresh player logs in and is placed in the Stone Atrium, **Then** the narrative log includes a speech entry attributed to `Garrick the Innkeeper` with the body `Welcome to the Stone Atrium.`
2. **Given** Garrick is in the Stone Atrium and a player Alice is in the North Corridor, **When** Alice moves south (back into the Atrium), **Then** Garrick's greeting fires again for Alice's arrival.
3. **Given** Garrick is in the Stone Atrium, **When** a player moves from the North Corridor to the Dusty Library (neither room contains Garrick), **Then** no speech entry from Garrick appears in their log.
4. **Given** two clones of the same NPC blueprint exist in two different rooms, **When** a player arrives in either of those rooms, **Then** the appropriate clone (the one IN the player's destination room) speaks — not both.
5. **Given** a player arrives in a room with Garrick, **When** the behavior fires, **Then** any OTHER players already present in that room ALSO see Garrick's speech entry (the utterance is a room-scoped event, not a private message to the arriving player).

---

### User Story 2 - An NPC says goodbye when a player leaves its room (Priority: P1)

A player is in the Stone Atrium with Garrick the Innkeeper. The player issues `go north` (or any other movement command) and moves to the North Corridor. Just before the player's session settles into the new room, Garrick speaks: `Garrick the Innkeeper says, "Farewell, traveler."` The speech entry appears in the player's log AS the room change happens, so the last thing the player sees in the Atrium is Garrick saying goodbye. Any other player still in the Atrium also sees this entry.

**Why this priority**: The symmetric counterpart to Story 1. Without it, Garrick is half-alive — he greets arrivals but ignores departures, which feels unfinished and gives wizards an incomplete primitive vocabulary. The implementation cost is small (the same pipeline as Story 1 with a different trigger and a different room-resolution direction), so shipping it alongside Story 1 is the right call.

**Independent Test**: With the seeded world extended so Garrick's blueprint also has `player_left → say "Farewell, traveler."`, log in and arrive in the Stone Atrium. Move north. The log MUST include a speech entry attributed to Garrick with body `Farewell, traveler.` delivered at the moment of departure (i.e., visible in the player's log before or alongside the rendered North Corridor room view). Repeat with two players in the Atrium; the player who STAYS in the Atrium MUST also see the departure-witness speech entry.

**Acceptance Scenarios**:

1. **Given** Garrick has `player_left → say "Farewell, traveler."` attached AND a player Alice is in the Atrium with Garrick, **When** Alice moves to the Corridor, **Then** Alice's log includes a speech entry from Garrick with body `Farewell, traveler.` delivered at departure time.
2. **Given** Alice and Bob are both in the Atrium with Garrick, **When** Alice moves out, **Then** Bob (still in the Atrium) ALSO sees Garrick's farewell speech in his log.
3. **Given** Alice is in the Atrium with Garrick, **When** Alice's session disconnects (per feature 003a's offline handling — not a movement command), **Then** Garrick's `player_left` behavior MUST NOT fire. Disconnection is distinct from movement.
4. **Given** Alice moves between two rooms that BOTH contain NPCs with `player_left` behaviors authored, **When** the movement completes, **Then** only the NPC in Alice's SOURCE room speaks (the player_left trigger fires in the room being left), not the NPC in the destination room (whose `player_entered` will fire instead).

---

### User Story 3 - A room emits atmospheric narration on player arrival (Priority: P2)

A player walks into a room that has its OWN behaviors authored (no NPC required) — for example, the Stone Atrium might have a `player_entered → say "The cool air carries the scent of rain."` behavior attached. When the player arrives, the log appends a line of ambient narration matching that text. The line renders WITHOUT any speaker attribution — there is no "Stone Atrium says, ..." prefix. The text appears as if narrated by an unseen storyteller, making it feel like a property of the room rather than dialogue from a character.

**Why this priority**: Validates the second attach surface explicitly (rooms-with-behaviors), which is structurally different from NPC behaviors (rooms aren't blueprinted in feature 008 — they store behaviors directly on the room row). The room-attached path doesn't introduce a new architectural concept beyond the NPC path — it shares the trigger plumbing — but it ships the second log entry kind (`:room_speech`) and the no-attribution rendering rule (clarified 2026-05-24). P2 rather than P1 because the headline NPC scenarios in Stories 1 and 2 deliver the primary user value; room narration is a content-authoring affordance for atmospheric content.

**Independent Test**: Seed a room with a `player_entered → say "<some line>"` behavior. Log in or move into that room. The log MUST include a narration line whose body matches the seeded text, WITHOUT any "X says" attribution prefix, distinguishable from NPC speech entries (which DO have attribution).

**Acceptance Scenarios**:

1. **Given** the Stone Atrium itself has a `player_entered → say "The cool air carries the scent of rain."` behavior attached (in addition to Garrick's behavior), **When** a player arrives in the Stone Atrium, **Then** the log includes TWO entries delivered in this strict order: FIRST the room's `:room_speech` line (just the literal text `The cool air carries the scent of rain.` with no attribution prefix), THEN Garrick's `:npc_speech` greeting (with `Garrick the Innkeeper says, "..."` attribution). The room sets the scene; the NPC speaks second.
2. **Given** a room has a `:room_speech`-producing behavior, **When** the entry renders, **Then** NO actor name precedes the text. The rendered HTML MUST NOT contain `<actor> says,` framing or quotation marks around the text. It MUST be visually distinguishable from `:npc_speech` (which has attribution) and from `:speech` (which is also attributed).
3. **Given** Alice is already in the Atrium and the Atrium has a `player_entered → say "<line>"` behavior attached, **When** Bob arrives in the Atrium, **Then** Bob receives the room narration line in his log BUT Alice does NOT — `:room_speech` is delivered only to the triggering player (the arriving one). Alice would have received it on her own arrival earlier; bystanders are NOT re-spammed.
4. **Given** a player moves out of a room with a room-attached `player_left` behavior, **When** the move completes, **Then** the leaving player receives the room's departure narration in their log. Players staying in the room do NOT receive it. (NPC speech in the same room WOULD reach the stayers per FR-015 — only room narration is triggering-player-only.)

---

### User Story 4 - Multiple behaviors compose on the same trigger (Priority: P2)

A wizard (or in this feature, the seed author) attaches MULTIPLE behaviors to the same entity for the same trigger. For example, Garrick's blueprint has TWO `player_entered` behaviors: one says "Welcome to the Stone Atrium." and another says "Mind the loose flagstone by the door." Both fire when a player arrives, in the order they were authored. The player sees two speech entries from Garrick in quick succession.

**Why this priority**: Validates that the behavior storage shape is genuinely a LIST of `(trigger, [actions])` tuples, not a singleton per trigger. The wizard tab (a future feature) will let authors build up an NPC's repertoire by appending behaviors; if the pipeline only supported one behavior per trigger, every wizard edit would need to choose between "replace" and "append" awkwardly. By proving multi-behavior composition now, we lock in the ergonomic answer for the wizard tab. P2 because it's a property of the substrate rather than a primary player-facing story.

**Independent Test**: Seed Garrick's blueprint with two `player_entered` behaviors. Log in and arrive in the Atrium. The log MUST include TWO speech entries from Garrick, one per behavior, in the order they were attached on the blueprint.

**Acceptance Scenarios**:

1. **Given** Garrick's blueprint has two `player_entered` behaviors `B1` and `B2` (in that authored order), **When** a player arrives, **Then** the log contains B1's speech entry strictly before B2's speech entry.
2. **Given** Garrick's blueprint has both a `player_entered → say "Welcome."` AND a `player_left → say "Farewell."` behavior, **When** a player enters, **Then** ONLY the entered behavior fires; when the same player leaves, ONLY the left behavior fires. Triggers are independent.
3. **Given** a behavior list with N entries authored on the same trigger, **When** that trigger fires, **Then** all N action lists run in order — none are skipped.

---

### User Story 5 - Multiple actions inside one behavior compose in order (Priority: P3)

A wizard authors a behavior with a single trigger but MULTIPLE actions: e.g., `player_entered → [say "Welcome.", say "Take care."]`. When the trigger fires, both `say` actions run in order: the player sees `Welcome.` first, then `Take care.` as a second speech entry from the same speaker. The two actions are part of one logical behavior — the wizard intended them to fire together — but they render as separate utterances.

**Why this priority**: Validates that the action LIST within a behavior is genuinely ordered and supports multiple entries. With only one action type (`:say`) in this feature, multi-action behaviors are mostly a "we proved the shape works" exercise rather than a frequent authoring pattern — most wizards will write one action per behavior in this feature. But it locks in the storage shape for future features (e.g., `attack → [damage, emit_quip]`) where multi-action composition is the whole point. P3 because the test value is largely structural; if Story 4 + Stories 1-3 pass, this is essentially a smoke test of the action-list shape.

**Independent Test**: Seed Garrick's blueprint with one `player_entered` behavior whose action list contains TWO `say` calls. Arrive in the Atrium. The log MUST include both speech entries from Garrick in the authored order.

**Acceptance Scenarios**:

1. **Given** Garrick's blueprint has a single `player_entered` behavior with `[say "First line.", say "Second line."]` as its action list, **When** a player arrives, **Then** Garrick's "First line." entry appears strictly before his "Second line." entry in the player's log.
2. **Given** an action in an action list raises an error (e.g., a malformed `say` action with a non-string body) — a defensive case not expected during normal authoring — **When** the trigger fires, **Then** subsequent actions in the same action list MUST still execute (one bad action does not abort the rest of the behavior), AND the player MUST NOT see a partial or scary error message.

---

### Edge Cases

- **A player moves between two rooms in rapid succession**: each room change fires `player_left` in the source and `player_entered` in the destination. The pipeline processes them in the order the underlying movement events are emitted. No deduplication, no debouncing.
- **An NPC clone arrives in a room AFTER a player is already there**: the player's arrival happened before the clone existed. The clone's `player_entered` behavior MUST NOT fire retroactively for that pre-existing player. Behaviors only fire on the FUTURE crossings of their trigger condition, not historical ones.
- **An NPC clone is in a room where a player departs**: the clone's `player_left` behavior fires for that departure, as expected.
- **A player who has NEVER been in a room enters it for the first time**: the room's (and any present NPC's) `player_entered` behavior fires. There's no "first-time" vs "returning" distinction — every arrival is an arrival.
- **A player disconnects (offline) from a room without issuing a movement command**: this is NOT a `player_left` event for this feature's purposes. The `player_left` trigger fires only on intentional movement (the `PlayerMoved` event from feature 003). Disconnection is handled by feature 003a's offline-player filtering — out of scope here.
- **The same player triggers `player_entered` for multiple sessions of the same account**: each session arrival is a separate trigger, but per feature 003's multi-session model, the underlying `PlayerSpawned` / `PlayerMoved` event fires once per session. The behavior accordingly fires for each session's arrival.
- **A behavior with an empty `say` body**: the seeded behavior MUST have a non-empty text. Empty/nil text in the action data is rejected at the behavior-authoring layer.
- **A behavior with a very long `say` body**: the same 500-character input cap from features 004 / 005 applies to behavior action text. Authoring a `say` action longer than 500 characters is refused at authoring time.
- **A trigger fires when there are ZERO NPCs in the room and ZERO room behaviors**: no speech entries appear. Nothing fires; nothing is logged. This is the no-op base case.
- **Garrick speaks; another player is in the room; the speaking player has filtered/muted Garrick or himself**: out of scope. There is no user-facing mute mechanism in this feature; every player in the destination/source room sees the room-scoped speech entry uniformly.
- **The arriving player IS the NPC's blueprint author**: behaviors fire identically regardless of who the player is. There is no special "don't greet the wizard" rule.
- **Behaviors fire during the seed-time spawn of an NPC** (feature 007's arrival witness): out of scope. Seed-time NPC spawns produce `<name> arrives.` system entries (feature 007 FR-011), but they do NOT trigger any `player_entered` behaviors (no player has entered — the NPC has been added; players are the only triggering actors for this feature's triggers).
- **A wizard authors a behavior on a blueprint AFTER clones have been spawned**: not exposed in this feature (no wizard tab, no blueprint update path). Future features will define propagation semantics; this feature's full-copy posture (inherited from 008) is the default.

## Requirements *(mandatory)*

### Functional Requirements

**Behavior entity**:

- **FR-001**: System MUST introduce a new authoring concept called a "behavior." A behavior is a `(trigger, [actions])` tuple where `trigger` is drawn from a closed vocabulary of trigger types and `[actions]` is an ordered list of action invocations, each drawn from a closed vocabulary of action types. Both vocabularies are owned by the core team in this feature; the wizard tab (a later feature) lets authors compose these but does not let them introduce new trigger or action types.
- **FR-002**: This feature MUST ship exactly **two trigger types**: `player_entered` (fires when a player arrives in the room the behavior's attach entity occupies) and `player_left` (fires when a player departs the room the behavior's attach entity occupies). No other triggers MUST be added in this feature.
- **FR-003**: This feature MUST ship exactly **one action type**: `say` (emits a speech utterance from the behavior's attach entity, with the action's text as the body). No other actions MUST be added in this feature.
- **FR-004**: A behavior's `say` action MUST require a non-empty `text` parameter. Authoring a `say` action with empty or nil text MUST be refused at authoring time. The text MUST be capped at 500 characters, matching the input cap from features 004 / 005.

**Attach surfaces**:

- **FR-005**: Behaviors MUST be attachable to NPC blueprints. Behaviors authored on a blueprint are inherited by every clone of that blueprint at spawn time, via the full-copy semantics established in feature 008 (i.e., the behavior list is denormalized onto the clone at the moment of spawning, and subsequent blueprint edits do NOT propagate to existing clones).
- **FR-006**: Behaviors MUST be attachable directly to rooms. Rooms do NOT have a blueprint/clone split (feature 008 deferred room blueprints); behaviors live on the room row itself. Each room MAY hold its own independent behavior list.
- **FR-007**: A single entity (NPC blueprint OR room) MUST be able to hold multiple behaviors, organized as an ordered list. When a trigger fires, ALL behaviors on the entity whose trigger matches MUST execute in the authored order. Behaviors on different triggers are independent — only matching-trigger behaviors fire for a given event.
- **FR-008**: Within a single behavior, the `[actions]` list MUST be processed in order. If multiple actions are present (e.g., `[say "First.", say "Second."]`), they MUST run sequentially and produce their effects in that order.
- **FR-008a**: When multiple entities in the SAME ROOM have behaviors firing on the same trigger event (e.g., both the room AND one or more NPC clones have `player_entered` behaviors), the room's behaviors MUST execute FIRST and the NPC clones' behaviors MUST execute SECOND. Within "all NPC clones in the room," the firing order across distinct clones is unspecified but MUST be deterministic (implementation chooses a stable order — e.g., clone-spawn order). The room-before-NPCs rule applies to both `player_entered` and `player_left`.

**Speaker resolution**:

- **FR-009**: The speaker of a `say` action MUST be the attach entity itself, NOT specified by the action's data. For NPC blueprint behaviors, the speaker is the CLONE that inherited the behavior (NOT the blueprint, which is never in the world). For room behaviors, the speaker is the ROOM itself (rendered without explicit attribution — see FR-010).
- **FR-010**: Behavior-sourced speech MUST be rendered using two new log entry kinds, distinct from feature 004's player `:speech` kind:
  - `:npc_speech` — NPC-clone speaker. Renders WITH attribution using the clone's display name (e.g., `Garrick the Innkeeper says, "Welcome to the Stone Atrium."`).
  - `:room_speech` — room speaker. Renders the text WITHOUT any "X says" attribution. The line appears as ambient narration (e.g., the literal text `The cool air carries the scent of rain.` with no actor name, no quotation marks framing it as speech, no "The room says" prefix). The room never speaks "as itself" — it produces atmospheric narration that happens to be authored via the same `:say` primitive.
  - Both kinds MUST be visually distinguishable from player `:speech` (feature 004) and from feature 007 FR-011 NPC arrival system entries.

**Trigger semantics**:

- **FR-011**: The `player_entered` trigger MUST fire for every NPC clone and every room in the player's DESTINATION room when a player's `PlayerSpawned` (first-time arrival via spawn) or `PlayerMoved` (movement between rooms) event is processed. The trigger MUST NOT fire for entities in other rooms.
- **FR-012**: The `player_left` trigger MUST fire for every NPC clone and every room that the player is LEAVING when a `PlayerMoved` event is processed. The trigger fires on the SOURCE room (the room being left), NOT the destination. The trigger MUST NOT fire on a `PlayerSpawned` event (first arrival has no "source" room).
- **FR-013**: Triggers MUST NOT fire as a result of player disconnection (offline transition). Per feature 003a's offline-player model, disconnection is distinct from movement; only the explicit `PlayerMoved` event drives `player_left`.
- **FR-014**: Triggers MUST NOT fire retroactively for state that existed before the behavior was authored. A behavior authored AFTER players are already in the room (via the seed or a future authoring path) MUST NOT fire for those pre-existing players — only future trigger events count.

**Action delivery**:

- **FR-015**: When a `say` action executes, delivery of the resulting entry differs by entry kind:
  - `:npc_speech` MUST be delivered to EVERY player session currently in the same room as the speaking NPC clone. This matches feature 004's player-`say` targeting (FR-035 multi-session model). It includes the player whose movement triggered the behavior, any other players in the room, AND every concurrent session of every player in the room.
  - `:room_speech` MUST be delivered ONLY to the player whose movement triggered the behavior — and to all of that player's concurrent sessions, per FR-035. It MUST NOT be delivered to other players in the same room. This prevents bystanders from being spammed with room narration on every arrival/departure that happens around them.
- **FR-016**: Behavior-sourced entries (`:npc_speech` and `:room_speech`) MUST be strictly ephemeral. Specifically:
  - **No domain event MUST be emitted by a behavior firing.** The `:say` action MUST NOT append anything to the Commanded event store. There is no `BehaviorFired` event, no `NPCSpoke` event, no `RoomNarrated` event — nothing persisted. Behavior outputs are transient PubSub broadcasts only, generated by the behavior interpreter at trigger time and dispatched directly to subscribed sessions. This matches the non-event-sourced posture of feature 004's player `say` (which is also a direct PubSub broadcast with no domain event).
  - The entries MUST NOT be persisted as part of any player's room state, MUST NOT be replayed when a player re-enters the room later, and MUST NOT surface on any `look` query (room view, examination, inventory).
  - They share the same "live, not historical" posture as feature 003's witness entries (FR-030) — visible at the moment they fire, gone the moment they scroll out of the player's log.
- **FR-016a**: A consequence of FR-016 is that **event-store replay does NOT replay behavior firings**. Replaying the event store re-processes the underlying trigger events (`PlayerSpawned`, `PlayerMoved`), which COULD in principle re-fire behaviors — but those re-firings MUST NOT happen in practice. The behavior interpreter MUST be configured so it processes trigger events only when they are emitted in the LIVE forward direction, not when they are projected from historical events during a read-model rebuild. The implementation mechanism (e.g., starting the interpreter only after projector catchup completes, or guarding behavior firings behind a "live mode" flag) is deferred to the planning phase.
- **FR-017**: For `player_left`, the leaving player MUST be treated as "still in the source room" for the purpose of `:npc_speech` delivery — they receive any NPC farewell speech entries even though the underlying `PlayerMoved` event has already updated their `current_room_id` to the destination. The implementation choice for how that delivery reaches the leaving player's session (e.g., delaying their source-room topic unsubscribe, routing through the player-topic, capturing `player_id` from the move event for direct dispatch) is deferred to the planning phase. For `:room_speech`, FR-015 already routes the entry to the triggering player only, so the leaving player naturally receives any room-narration goodbye.
- **FR-017a**: Ordering of entry delivery relative to the player's room view transition: for `player_entered`, behavior-sourced entries appear AFTER the player's destination room view is rendered (the player is "in the room" first, then the room/NPC reacts). For `player_left`, behavior-sourced entries appear BEFORE or AT the same logical moment as the destination room view rendering (the leaving player sees the farewell as they leave, not after they've already mentally moved on).

**Feature 007 FR-018 relaxation**:

- **FR-018**: This feature MUST relax feature 007's FR-018 ("NPCs MUST NOT be able to speak, emote, whisper, tell, or otherwise participate in the player communication verbs"). NPCs gain SPEECH (via the `say` action) as their first dynamic capability. The remaining feature 007 restrictions (NPCs cannot move, cannot participate in combat) continue to hold.

**Authoring path**:

- **FR-019**: Behaviors MUST be authorable only via the seed mechanism in this feature. No wizard UI, no in-game command, and no admin REST endpoint MUST be exposed for behavior authoring in this feature. Future features will introduce authoring surfaces.
- **FR-020**: The seed MUST be extended so Garrick the Innkeeper's blueprint includes at least one `player_entered → say "Welcome to the Stone Atrium."` behavior. This is the demonstrable end-to-end smoke for the feature.
- **FR-021**: The seed MUST also extend Garrick's blueprint with at least one `player_left → say "Farewell, traveler."` behavior, exercising both triggers from a fresh login.
- **FR-022**: The seed MUST attach at least one room-level behavior to demonstrate the room-attach surface (Story 3 / FR-006). The choice of which room and which message is at the implementer's discretion; the spec recommends a Stone Atrium atmospheric line so the room-behavior path is exercised from the same fresh-login flow.

**Out of scope (this feature)**:

- **FR-023**: This feature MUST NOT introduce additional triggers (e.g., `on_examine`, `on_attack`, `on_time_elapsed`). Only `player_entered` and `player_left` ship.
- **FR-024**: This feature MUST NOT introduce additional actions (e.g., `emote`, `move_clone`, `give_object`, `damage`). Only `say` ships.
- **FR-025**: This feature MUST NOT introduce a wizard tab, behavior editing UI, or any LLM-based authoring surface. Authoring is seed-only.
- **FR-026**: This feature MUST NOT introduce behavior REMOVAL or EDITING at runtime. Behaviors are seeded once and persist; modifying or removing them is out of scope (and consistent with feature 008's blueprint-immutability posture).
- **FR-027**: This feature MUST NOT introduce a way to mute, filter, or suppress speech entries from behaviors at the player layer. Every player in the room sees the entries uniformly.
- **FR-028**: This feature MUST NOT introduce a way for behaviors to reference state (e.g., "say this only on the third arrival"). All behaviors fire unconditionally on their trigger. Conditional / stateful behaviors are a future feature.
- **FR-029**: This feature MUST NOT introduce NPC movement, combat, or any other player-communication verbs (`emote`, `whisper`, `tell`) for NPCs. Only the `say` action ships.

### Key Entities

- **Behavior**: A `(trigger, [actions])` tuple. The trigger is a closed enum value (`player_entered` or `player_left` in this feature). The action list is an ordered sequence of action invocations (each a `(action_type, params)` pair — `(say, %{text: "..."})` in this feature). Behaviors have no identity of their own beyond their position in their attach entity's behavior list.
- **Behavior Attach Entity**: Either an NPC blueprint or a room. The "owner" of one or more behaviors. The attach entity determines the speaker for `say` actions: NPC blueprint behaviors produce speech from each spawned CLONE of that blueprint; room behaviors produce speech from the ROOM itself.
- **Trigger Event**: A momentary world event that matches a behavior's trigger type and the room scope. `player_entered` events arise from `PlayerSpawned` and the destination-room arc of `PlayerMoved`. `player_left` events arise from the source-room arc of `PlayerMoved`.
- **Behavior-Sourced Log Entries**: Two new log entry kinds produced by `:say` actions, distinct from feature 004's player `:speech` kind:
  - `:npc_speech` — the NPC clone is the speaker. Renders with the clone's display name (e.g., `Garrick the Innkeeper says, "Welcome."`). **Delivery scope**: every player session in the speaker's room (feature 004 say semantics, multi-session model).
  - `:room_speech` — the room is the source. Renders WITHOUT any "X says" attribution — just the line text, as ambient narration. **Delivery scope**: only the player whose movement triggered the behavior (and all their concurrent sessions). NOT delivered to other players in the room — prevents bystander spam from arrivals/departures.

  Both are visually distinguishable from player `:speech` (feature 004) and from NPC arrival entries (feature 007 FR-011). Future trigger types like `on_player_said` / `on_npc_said` will be able to filter by these kinds.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of fresh `mix ecto.reset` + fresh-login flows produce Garrick's `Welcome to the Stone Atrium.` speech entry in the player's log within 200ms of the player landing in the Atrium. Measured by integration test that asserts the entry is present immediately after the room view renders.
- **SC-002**: 100% of player movements between two rooms where the source room contains an NPC with a `player_left` behavior produce that NPC's farewell speech entry in the player's log at or before the destination room renders. Measured by integration test that captures log entry ordering during movement.
- **SC-003**: 100% of behaviors authored as `[(trigger, [a1, a2, ..., aN])]` produce N speech entries in the player's log in the authored order when the trigger fires. Validated by an integration test that seeds a multi-action behavior and asserts ordering.
- **SC-004**: Behaviors fire ONLY for entities in the destination room (for `player_entered`) or source room (for `player_left`) — verified by an integration test where NPCs exist in MULTIPLE rooms and only the appropriate room's NPC speaks for a given movement.
- **SC-005**: 100% of player-disconnection scenarios (offline transitions per feature 003a) produce ZERO behavior firings. Verified by an integration test that disconnects a player and asserts no `player_left` speech entries are emitted from NPCs in the room the player was last in.
- **SC-006**: 0 player-facing surfaces include the `<name>#<serial>` debug identity from feature 008 in any behavior-sourced speech entry. Behaviors render with the clone's bare display name (`Garrick the Innkeeper`), never with `Garrick the Innkeeper#1`. Verified by a regex assertion in the integration test.
- **SC-007**: Behavior-sourced speech entries are delivered to ALL players in the speaker's room (not just the triggering player). Verified by a parallel-session integration test where two players are in the Atrium; one arrives, both see Garrick's greeting.
- **SC-008**: After this feature ships, feature 007 FR-018's regression coverage is intentionally **reversed** for NPCs: NPCs CAN now produce speech via behaviors. Other prohibitions from feature 007 (no movement, no combat) MUST continue to be enforced and verified by their existing tests, which MUST continue to pass unchanged.

## Assumptions

- The minimal vocabulary (2 triggers + 1 action) is sufficient to demonstrate the substrate end-to-end. Future features will expand the vocabulary one primitive at a time as concrete needs surface; this feature deliberately resists pre-loading additional primitives.
- The speaker for a `say` action is unambiguously determined by the behavior's attach point — wizards never specify a speaker. If a future feature introduces behaviors with a configurable speaker (e.g., "this NPC says something on behalf of that NPC"), that's a new feature with new design; this feature locks in the implicit-speaker rule.
- Room-level behaviors live directly on the room row (via a new column) because feature 008 deferred room blueprints. If a future feature introduces room blueprints with clone-style separation, room behaviors may migrate to a blueprint layer; this feature does not anticipate that move.
- Behavior storage shape for NPC blueprints follows feature 008's full-copy semantics: the blueprint carries the behavior list, and at clone spawn time the list is denormalized onto the clone. Existing clones do NOT receive behaviors added to their blueprint after they were spawned (the same "no live propagation" rule from feature 008).
- Two new log entry kinds (`:npc_speech`, `:room_speech`) extend feature 004's `:speech` family. The render code adds two new clauses; the underlying delivery is the same Phoenix.PubSub fan-out that feature 004 already uses for player speech. No new persistence layer.
- The PlayerSpawned / PlayerMoved domain events from feature 003 are the canonical triggers. Behaviors execute via a new event handler subscribed to those events; no new player-side commands or LiveView pathways are required for the trigger pipeline.
- **Behavior firings are non-event-sourced.** They produce transient PubSub broadcasts only, never Commanded events, never event-store entries. This matches feature 004's player-speech posture and is the deliberate symmetry the design conversation locked in. As a consequence, behavior-sourced speech is NOT replayable from history and does NOT appear in any audit log of world events — wizards and players see it only when it fires live.
- Behavior execution is single-threaded per movement event (the event handler processes one event at a time), so ordering within a behavior list and across behaviors on the same entity is deterministic without additional locking.
- The 500-character text cap on `:say` action bodies matches features 004 / 005's player-input cap. Future features may raise or lower this cap; behaviors inherit the same constraint to stay consistent with the player communication surface.
- Performance budget is generous: the worst observed firing fan-out in this feature is a single NPC clone in a room with a single small action list — well under 1ms of execution. No need for batching, caching, or async dispatch in this feature.
- Desktop web only, English-language only, matching the scope of all prior features (001–008).
- The wizard tab is the next feature after this one (anticipated as feature 010). It will introduce the LLM-tooled authoring surface that lets non-engineer wizards compose behaviors via natural language. The structural design choices in this feature (data-shaped behaviors, closed vocabulary, implicit speaker) are deliberate substrate for that future feature.
