# Phase 0 Research: NPC and Room Behaviors

Five design questions resolved before tasks generation. The spec is clarified — there are no `NEEDS CLARIFICATION` markers in Technical Context. These are implementation-level decisions that drive Phase 1's contracts.

## R1. Replay safety for the behavior interpreter (FR-016a)

**Decision**: The `World.Behaviors.Interpreter` Commanded event handler is configured with `start_from: :current`. On boot, it subscribes from the current event-store HEAD position rather than from the beginning. Historical events that landed in the store before the interpreter was added are never processed by it; only events emitted in the live forward direction trigger behaviors.

**Rationale**:
- FR-016 establishes that behavior firings are non-event-sourced — they produce only transient PubSub broadcasts. FR-016a strengthens this: replaying the event store MUST NOT re-fire behaviors.
- The cleanest implementation is to never let the interpreter see historical events at all. Commanded's `start_from: :current` does exactly this — built into the handler config, no custom logic needed.
- The other projector handlers (WorldProjector, UIEventBroadcaster) use the default `start_from: :origin` because they DO need to replay history to rebuild the read model. The interpreter is the opposite case: it must NOT replay.
- Operational implication: on first boot after this feature deploys, the interpreter subscribes from the current HEAD. Any historical `PlayerSpawned` / `PlayerMoved` events that fired before deploy are skipped. Future events (post-deploy) fire normally. This is the correct behavior — replaying a player's old movements should NOT trigger their NPC greetings retroactively.
- On a `mix event_store.reset && mix ecto.reset` dev workflow, the event store is wiped and rebuilt from scratch via seed. The seed dispatches `SpawnPlayer` / `MovePlayer` exactly zero times during seed (the seed only sets up rooms, exits, objects, NPCs). The interpreter's subscription, starting at HEAD = 0, will then process every real player movement that happens after seed completes. Same correct behavior.

**Alternatives considered**:
- **`start_from: :origin` + replay guard**: every `handle/2` clause checks a "live mode" flag set by some external coordinator after projector catchup. Rejected — much more code, and the failure mode (firing behaviors during replay) is silent.
- **Check event metadata for replay vs. live**: Commanded does not expose a reliable per-event `is_replay?` field in its standard handler API. Plus, even if it did, every clause would have to check it.
- **Defer interpreter startup until projector catchup completes**: would require introspecting handler positions and coordinating start ordering. Brittle.

## R2. Delivery topic choice: player-topic over room-topic

**Decision**: The interpreter broadcasts `BehaviorUtterance` UI events on `World.player_topic(player_id)` for each individual recipient, NOT on `World.room_topic(room_id)`. The interpreter enumerates recipients at firing time and broadcasts N times (where N is the number of player recipients for the specific entry).

**Rationale**:
- Two specific requirements conflict with room-topic delivery:
  1. `:room_speech` is triggering-player-only (FR-015). A room-topic broadcast fans out to every subscriber, so a separate filtering mechanism would be needed in GameLive. The simpler answer: broadcast only to the triggering player's player-topic.
  2. The triggering player (arriving or leaving) experiences a subscription window during movement: they unsubscribe from the source room and subscribe to the destination room around `Commands.move/2`'s return. If behaviors fire on the source-room topic DURING `Commands.move/2`, the leaving player may still be subscribed; but if they fire on the destination-room topic, the player isn't subscribed yet. Player-topic sidesteps this entirely — GameLive subscribes to its own `player_topic` on mount and never unsubscribes during movement.
- Player-topic delivery costs ~N PubSub broadcasts per behavior firing (one per recipient), versus 1 room-topic broadcast. For a starter map with a handful of players in a room, this is negligible.
- Feature 004's player `say` uses room-topic. The behavior system departs from that pattern because the recipient set is different: feature 004 broadcasts to everyone in the speaker's current room; feature 009 routes by player_id specifically. The different broadcast strategy is appropriate to the different recipient logic.

**Recipient determination at firing time**:

| Action source | Trigger | Recipients |
|---|---|---|
| `:room_speech` | `player_entered` | The arriving player only (`event.player_id`). |
| `:room_speech` | `player_left` | The leaving player only (`event.player_id`). |
| `:npc_speech` | `player_entered` | The arriving player (`event.player_id`) + every OTHER player in the destination room (queried via `Queries.other_occupants_of/2` or equivalent, excluding the arriving player). |
| `:npc_speech` | `player_left` | The leaving player (`event.player_id`) + every OTHER player still in the source room. |

For `:npc_speech` on `player_left`, the "other players in the source room" query may or may not still include the leaving player depending on whether the `WorldProjector` has run first. Including `event.player_id` explicitly (via direct player-topic broadcast) AND querying for other occupants guarantees the leaving player receives the entry without depending on projector ordering. If the query happens to also return the leaving player (because the projector hasn't run yet), the duplicate is harmless — only one player-topic broadcast is sent per id by using a `MapSet`.

**Alternatives considered**:
- **Room-topic with filtering in GameLive**: rejected for `:room_speech` (would require every subscriber to inspect the message's `triggering_player_id` field and filter). Adds load to every session in the room for an event that only matters to one. Player-topic is the inversion: filter at broadcast time, deliver only to the right inboxes.
- **Direct PID-send to GameLive processes**: would require tracking GameLive process PIDs per player session. Phoenix.Presence has this information but it's awkward to consume from a Commanded event handler. Player-topic via PubSub is simpler.

## R3. Behavior validator shape

**Decision**: `World.Behaviors.Validator` is a pure module with `validate/1` returning `:ok | {:error, atom_with_context}`. Input is a behavior list (the JSONB structure as Elixir data). Validation rules:

```text
- The input MUST be a list.
- Each entry MUST be a map with exactly two keys: "trigger" (string) and "actions" (list).
- The "trigger" string MUST be one of "player_entered" | "player_left".
- The "actions" list MUST be non-empty (a behavior with zero actions is meaningless).
- Each action MUST be a map with at minimum a "type" key (string).
- For "type" == "say": the action MUST also have a "text" key (string), non-empty,
  ≤500 characters.
- No other "type" values are accepted in this feature.
```

**Returns**: `:ok` on success, `{:error, {:unknown_trigger, "..."}}` / `{:error, {:unknown_action, "..."}}` / `{:error, :empty_text}` / `{:error, :text_too_long}` / `{:error, :empty_actions}` / `{:error, :not_a_list}` on failure.

**Called by**: the seed (validates each behavior list it intends to dispatch before calling `CreateNPCBlueprint` or `Repo.update_all` on room behaviors). When the wizard tab feature lands, the wizard's authoring path will also call this validator before persisting.

**NOT called by**: the interpreter at firing time. The interpreter trusts the stored data shape — it's been validated at write time. If a malformed action somehow reaches the interpreter (e.g., a future bug bypasses the validator), the interpreter's pattern-match on action shape fails, the offending action is logged and skipped, and execution continues with the remaining actions in the list. One bad action does NOT crash the whole behavior list.

**Rationale**:
- Separating authoring-time validation from runtime execution keeps the hot path fast and the validation logic in one place.
- The validator's input shape (raw maps with string keys) matches what JSONB deserialization produces. The interpreter operates on the same shape.
- Skipping (not crashing on) malformed actions at runtime is defensive — for this feature it's overengineering, but it sets the right posture for the eventual wizard tab where user-authored data might contain bugs.

**Alternatives considered**:
- **Validation only at runtime (in the interpreter)**: rejected. Authoring-time validation gives clean error atoms during seed, surfaces bugs early, and is cheaper.
- **Validation via a typed struct (e.g., `%Behaviors.Behavior{}`)**: rejected for now. The JSONB round-trip is plain maps; coercing to/from structs adds boilerplate without unlocking anything beyond what shape-matching gives us.

## R4. Firing order between rooms and NPCs (FR-008a implementation)

**Decision**: The interpreter, per trigger event, fires behaviors in this strict order:

```text
1. Room's behaviors (for the trigger room).
2. NPC clones in the trigger room, ordered by `serial` ascending.
   For each clone:
     For each of the clone's behaviors:
       For each action in the behavior's action list:
         Execute the action.
```

The room behaviors fire as a single block before any NPC behaviors. Within "NPC clones," the deterministic ordering is by `serial` (the per-blueprint monotonic counter from feature 008 — for a given blueprint, clone#1 fires before clone#2, etc.). Across blueprints, clones with the same serial fire in an unspecified-but-deterministic order (e.g., by `npc_clones.inserted_at` or `clone_id` UUID — the implementer chooses one tiebreaker).

**Rationale**:
- FR-008a explicitly requires room-before-NPCs.
- The within-NPC tiebreaker by `serial` matches the user's mental model from the LPMud framing: clones are identified by their serial within a blueprint, so within a blueprint they fire in spawn order.
- For the starter map (one blueprint, one clone in the Atrium), this ordering question is academic — there's only one NPC. The deterministic ordering surfaces when future content has multiple clones of multiple blueprints in one room.

**Alternatives considered**:
- **NPCs first, then room**: rejected by Q2 clarification (room sets the scene).
- **Strict authored order across entities**: would require a global authoring timestamp on behaviors. Out of scope; not needed.

## R5. Log-entry CSS treatment for the new render kinds

**Decision**: Add two new HEEx render clauses in `GameComponents.log_entry/1`:

```text
:npc_speech →
  <div class="log-entry speech speech-npc">
    <span class="who">{@entry.actor_name}</span> says,
    &ldquo;{@entry.text}&rdquo;
  </div>

:room_speech →
  <div class="log-entry narrate narrate-room">
    {@entry.text}
  </div>
```

CSS for `.speech-npc` defaults to the same styling as `.speech` (feature 004's player speech) — the visual differentiation comes from the actor name (player vs NPC display name), not from color. A future styling pass can add a subtle visual cue (e.g., NPCs in a slightly different color), but the default is consistent.

CSS for `.narrate-room` mirrors the existing `:narrate` kind (italicized, slightly dimmed) — appropriate for ambient narration. The `narrate-room` modifier is reserved for future per-room styling if content authors want it.

**Rationale**:
- Reusing the `.speech` and `.narrate` base classes preserves visual consistency. The kind-specific modifiers (`.speech-npc`, `.narrate-room`) give future styling work a clean hook.
- The user explicitly stated that room narration has NO attribution. The render template enforces that — no `<span class="who">` is emitted for `:room_speech`.
- The "says" framing for `:npc_speech` matches the project's existing speech rendering convention.

**Alternatives considered**:
- **Distinct top-level classes (`.npc-speech` vs `.player-speech`)**: rejected. Reusing `.speech` keeps the CSS hierarchy clean and lets the modifier classes do their job.
- **Plain-text rendering of room narration (no HTML wrapper)**: rejected. We want the line to land as a distinct log entry that can be styled, copied, and accessibility-announced — same affordances as every other log entry.

## R6. Backward compatibility for `NPCClonedFromBlueprint` and `NPCBlueprintCreated` events

**Decision**: Both events gain an optional `:behaviors` field with default `[]` in their `defstruct`. The `@enforce_keys` are unchanged. Existing events in the event store (from feature 008) deserialize cleanly — they have no `behaviors` field in their JSON payload, but Elixir's default-field mechanism kicks in to provide `[]`.

For the `NPCBlueprintCreated` event specifically, an additional concern: the projector's `handle/2` clause now needs to set `npc_blueprints.behaviors` from the event. Existing legacy events deserialize with `behaviors: []`, which the projector inserts as the empty list. So a developer with feature 008 history in their event store rebuilds with `behaviors: []` for all pre-009 blueprints — correct (those blueprints had no behaviors).

Similarly for `NPCClonedFromBlueprint`: existing events project with `behaviors: []` on the clone row.

For the legacy `NPCSpawnedInRoom` event (feature 007), the projector's synthetic-blueprint path already creates synthetic blueprints. With this feature, synthetic blueprints also get `behaviors: []` — correct (legacy events had no behaviors concept).

**Rationale**:
- Backward compatibility is a hard requirement: the project's event store accumulates events over feature lifetimes, and we don't rewrite history.
- The optional-field-with-default pattern is the standard Elixir idiom for this; Jason's encoder/decoder handles it correctly via struct defaults.

**Alternatives considered**:
- **New event types (`NPCBlueprintCreatedV2` etc.)**: rejected — would require two projection paths per event type and is overkill for a single field addition.
- **Event-payload migration during deploy**: rejected — violates "event store is immutable history."
