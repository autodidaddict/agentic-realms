# Contract — UI events for player communication

This contract specifies the new PubSub topics, message payloads, and subscriber rules introduced by feature 004. The patterns are deliberately consistent with `specs/003-persisted-world/contracts/ui_events.md` — the same `AgenticRealms.PubSub` instance, the same topic strings (`room:<id>` and `player:<id>`), and the same "transient struct, no persistence" convention.

## Topics (no new topic names)

| Topic                            | Producer                                   | Subscribers                                  |
|----------------------------------|--------------------------------------------|----------------------------------------------|
| `room:<sender_room_id>`          | `World.Communication.{say,emote,whisper}/_` | every `GameLive` whose `current_room_id == sender_room_id` |
| `player:<recipient_id>`          | `World.Communication.tell/3`                | every `GameLive` whose `current_player.id == recipient_id` |

Both topics already exist from feature 003 — every `GameLive` subscribes to its current room topic on mount and its player topic on mount, so no subscription bookkeeping is needed in this feature.

## Payloads

### `%AgenticRealms.World.UIEvents.RoomUtterance{}`

Broadcast on `room:<sender_room_id>` by `World.Communication.say/2`, `emote/2`, and `whisper/3`.

| Field             | Type        | Required | Notes |
|-------------------|-------------|----------|-------|
| `room_id`         | `binary()`  | yes      | UUID of sender's room at the moment of acceptance. |
| `actor_id`        | `integer()` | yes      | Sender's `players.id`. |
| `actor_username`  | `binary()`  | yes      | Snapshot of sender's username at acceptance time. |
| `actor_session_id`| `reference()` | yes    | The sender's per-LiveView session id (assigned at mount). Witnesses compare this to their own `socket.assigns.session_id` to suppress own-broadcast for `:say` (FR-005 actor exclusion). |
| `kind`            | `:say \| :emote \| :whisper` | yes | Determines rendering kind and recipient-filter rule. |
| `text`            | `binary()`  | yes      | Already trimmed and validated (1..500 chars). Original casing preserved. NOT HTML-escaped here — escaping happens at the template layer (FR-024). |
| `recipient_id`    | `integer()` or `nil` | conditional | Required iff `kind == :whisper`; `nil` otherwise. |

### `%AgenticRealms.World.UIEvents.PrivateUtterance{}`

Broadcast on `player:<recipient_id>` by `World.Communication.tell/3`.

| Field            | Type        | Required | Notes |
|------------------|-------------|----------|-------|
| `actor_id`       | `integer()` | yes      | Sender's `players.id`. |
| `actor_username` | `binary()`  | yes      | Snapshot of sender's username at acceptance time. |
| `recipient_id`   | `integer()` | yes      | Resolved recipient id (also the topic suffix). |
| `kind`           | `:tell`     | yes      | Reserved-shape field for future private kinds. |
| `text`           | `binary()`  | yes      | 1..500 chars, trimmed, original case. |

Tell carries no `actor_session_id` because tells are broadcast on the *recipient's* player topic — the sender's other sessions do not subscribe to it and therefore never receive the broadcast. The actor-side confirmation is appended inline in the originating `GameLive`.

## Subscriber rules (`GameLive.handle_info/2`)

The clauses below are added to the existing `handle_info/2` in `game_live.ex`. Order matches the existing-feature pattern: pattern-match the struct, decide actor exclusion / recipient filter, append the log entry.

### `RoomUtterance` with `kind: :say`

```text
if actor_session_id == socket.assigns.session_id:
  ignore (own broadcast — actor saw it inline as a confirmation)
else:
  append %{kind: :speech, actor: actor_username, text: text} to log
```

Mirrors FR-005 (excludes the speaker's own originating session) and FR-006 (the speaker's *other* sessions in the same room DO see it, because their `session_id` differs).

### `RoomUtterance` with `kind: :emote`

```text
append %{kind: :emote_action, actor: actor_username, text: text} to log
```

No filter — emotes are visible to all room subscribers including the actor (FR-008). The actor sees the same third-person narration witnesses see; the LiveView does NOT append a separate confirmation entry inline for emote.

### `RoomUtterance` with `kind: :whisper`

```text
if recipient_id == socket.assigns.current_player.id:
  append %{kind: :private_whisper_in, actor: actor_username, text: text} to log
else:
  ignore (not the recipient)
```

This filter is what makes whisper "private within a room": every same-room subscriber receives the broadcast, but only the recipient renders it. The sender's other sessions in the same room have `current_player.id == sender_id ≠ recipient_id`, so they also ignore — satisfying FR-018 (originating session only).

### `PrivateUtterance` with `kind: :tell`

```text
append %{kind: :private_tell_in, actor: actor_username, text: text} to log
```

No filter needed. Only the recipient's sessions subscribe to `player:<recipient_id>`, so reaching this clause already proves we're the right recipient.

## Self-session id

`GameLive.mount/3` assigns `:session_id` to a fresh `make_ref/0` in socket assigns. The value is opaque, unique within the node, and stable for the lifetime of the LiveView process. It is NEVER persisted, never serialized to the client, and exists solely to disambiguate the sender's originating LiveView from the sender's other LiveViews on the same node.

## Actor-side confirmation entries (not broadcast)

For completeness — these are appended inline by `GameLive.handle_event("submit_command", …)`, not broadcast on PubSub:

| Verb     | Originating-session log entry                     |
|----------|---------------------------------------------------|
| `say`    | `%{kind: :speech_self, text: text}` (e.g., "You say, 'hello'.") |
| `emote`  | none — the actor reads the same broadcast all room witnesses get (FR-008) |
| `tell`   | `%{kind: :private_tell_out, recipient: recipient_username, text: text}` |
| `whisper`| `%{kind: :private_whisper_out, recipient: recipient_username, text: text}` |

These confirmation kinds are rendered by `game_components.ex` with copy specific to first-person narration ("You tell Alice, '…'") and are visually distinct from the inbound private kinds.

## Refusal log entries (not broadcast)

All refusals are appended inline in the originating session by `GameLive.handle_event(…)` after mapping the `World.Communication` error tag. Refusals are NEVER broadcast.

| Error tag from facade          | Log kind             | Copy guidance                                          |
|--------------------------------|----------------------|--------------------------------------------------------|
| `:empty`                       | `:system`            | Verb-specific: "Say what?" / "Emote what?" / "Tell whom what?" / "Whisper to whom what?" |
| `:too_long`                    | `:system`            | "Your message is too long (max 500 characters)."       |
| `:not_found`                   | `:system`            | "There is no one named '<typed-name>' here or anywhere." (whisper / tell — same copy, no presence leak per FR-019) |
| `:ambiguous`                   | `:system`            | "Multiple players match '<typed-name>'. Use the full unique name." |
| `:self_target`                 | `:system`            | "You can't tell yourself." / "You can't whisper to yourself." |
| `:recipient_not_in_room` (whisper only) | `:system`   | "<recipient> is not nearby. Try `tell` instead." (FR-020) |
| `:not_deliverable` (tell only) | `:system`            | "Your message could not be delivered." (FR-016 — neutral)        |

The exact strings are UX copy and may be tuned at implementation time; the contract is the *log kind* (`:system`, reusing the existing 003 kind used for "You can't go that way" etc. — keeps refusal styling consistent across all features) and the information disclosed.
