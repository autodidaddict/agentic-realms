# Phase 1 Data Model — Player Communication

Communication is **transient** (FR-022). There are no Ecto schemas, no migrations, no DB tables, no event-store streams, and no aggregates introduced by this feature. The only "data" is a pair of in-flight struct shapes that ride `Phoenix.PubSub` from sender to subscribers and are discarded after delivery.

This document specifies the wire shape of those structs and the input shape consumed by the `World.Communication` facade.

---

## Transient structs

Both new structs live in `lib/agenticrealms/world/ui_events.ex`, next to the existing 003 structs.

### `AgenticRealms.World.UIEvents.RoomUtterance`

A say, emote, or whisper. Broadcast on `room:<sender_room_id>`.

```elixir
defmodule AgenticRealms.World.UIEvents.RoomUtterance do
  @enforce_keys [:room_id, :actor_id, :actor_username, :actor_session_id, :kind, :text]
  defstruct [
    :room_id,           # binary - the sender's room at the moment of acceptance
    :actor_id,          # integer - sender's player_id
    :actor_username,    # binary - sender's display name at moment of acceptance
    :actor_session_id,  # reference - opaque per-LiveView session id, for self-filtering
    :kind,              # :say | :emote | :whisper
    :text,              # binary - already trimmed, already validated (1..500 chars, original case preserved)
    :recipient_id       # integer - present iff kind == :whisper; nil for :say and :emote
  ]
end
```

**Field rules**

| Field | Required | Notes |
|-------|----------|-------|
| `room_id` | yes | Sender's room at the moment `World.Communication.{say,emote,whisper}/_` was called. The room may have changed by the time witnesses process the broadcast; broadcast room remains authoritative for the entry. |
| `actor_id` | yes | Caller's player id, looked up by the facade from the calling LiveView. |
| `actor_username` | yes | Snapshot at acceptance time — a future rename does not retroactively change historical log entries (though there are no historical entries to change; this matters only for log entries already in-process in a `GameLive`'s log assign). |
| `actor_session_id` | yes | Opaque `reference()` minted by `GameLive.mount/3` and stored in socket assigns. Used by witness sessions to decide whether to suppress the broadcast (own-session-exclusion for `say`). |
| `kind` | yes | One of three atoms; `recipient_id` MUST be `nil` if not `:whisper`. |
| `text` | yes | UTF-8 string, length 1..500 codepoints (after trim, before render). HTML escaping happens at the template layer. |
| `recipient_id` | conditional | Required when `kind == :whisper`; MUST be `nil` otherwise. Whisper witnesses (`GameLive.handle_info/2`) drop the message unless `socket.assigns.current_player.id == recipient_id`. |

**Why one struct for three kinds, instead of three structs**: the three room-scoped verbs share a topic, share a sender-context payload, and differ only by `kind` and the presence of `recipient_id`. Pattern matching on `%RoomUtterance{kind: :say}` vs `:emote` vs `:whisper` in the LiveView is as clean as matching on three separate struct modules and avoids the proliferation of nearly-identical modules under `UIEvents.*`.

---

### `AgenticRealms.World.UIEvents.PrivateUtterance`

A tell. Broadcast on `player:<recipient_id>`.

```elixir
defmodule AgenticRealms.World.UIEvents.PrivateUtterance do
  @enforce_keys [:actor_id, :actor_username, :recipient_id, :kind, :text]
  defstruct [
    :actor_id,         # integer - sender's player_id
    :actor_username,   # binary - sender's display name at moment of acceptance
    :recipient_id,     # integer - resolved recipient's player_id
    :kind,             # :tell  (reserved for future verbs that also use the player topic)
    :text              # binary - 1..500 chars, original case preserved, trimmed
  ]
end
```

**Field rules**

| Field | Required | Notes |
|-------|----------|-------|
| `actor_id` | yes | Sender's player id. |
| `actor_username` | yes | Snapshot at acceptance time. |
| `recipient_id` | yes | Result of recipient resolution (FR-010). Used to set the broadcast topic; the value is redundant at receive time (the only subscribers are the recipient's sessions) but kept on the struct for assertion clarity in tests and future filtering. |
| `kind` | yes | `:tell` for this feature. Field exists so we can add private kinds later (e.g., system DMs) without changing the struct shape. |
| `text` | yes | Same length / encoding rules as `RoomUtterance.text`. |

**Why no `actor_session_id` on `PrivateUtterance`**: tell broadcasts go to `player:<recipient_id>`, which the sender's other sessions do NOT subscribe to. No self-filter is needed because the sender's sessions never receive the broadcast.

---

## Facade input shape

`AgenticRealms.World.Communication` accepts inputs from `GameLive` after parsing. The shapes are described in `contracts/communication_api.md`; this section names the conceptual entities so they're discoverable from the data model.

### `Sender` (conceptual; not a struct)

Identified by `{player_id :: integer(), username :: binary(), session_id :: reference(), current_room_id :: binary()}`. Sourced from `GameLive` socket assigns. Not packaged into a struct — passed positionally or as a small map (`%{id:, username:, session_id:, room_id:}`) at the facade boundary.

### `RecipientLookup` (conceptual)

The result of `Communication.RecipientResolver.resolve/2`:

```elixir
@type result ::
        {:ok, %{id: integer(), username: binary()}}
        | {:error, :not_found}
        | {:error, :ambiguous}
        | {:error, :self_target}
```

No struct module — a tagged tuple is enough and matches the project's existing style (see `World.Queries.current_room_of/1`).

---

## Validation rules (one place: the facade)

Validation runs in `World.Communication` after parsing and before broadcast. The order matters because each early refusal short-circuits the next check:

1. **Trim** the candidate text. The parser has already trimmed leading/trailing whitespace but we re-trim defensively at the facade boundary because callers other than the LiveView (e.g., tests) may bypass the parser.
2. **Non-empty** — empty/whitespace-only text → `{:error, :empty}`. (FR-007 / FR-009 / FR-015 / FR-021.)
3. **Length cap** — `String.length(text) > 500` → `{:error, :too_long}`. (FR-026.) Note: `String.length/1` counts codepoints, not bytes — appropriate for international characters where the 500 limit should mean "user-perceived characters."
4. **Recipient resolution** (tell, whisper only) — see `RecipientLookup` above.
5. **Self-target** — `{:error, :self_target}` if resolved id == sender id. (FR-010a.)
6. **Whisper room scope** — for whisper only: the resolved recipient must currently occupy the sender's room per `World.Queries.other_occupants_of/2`. If not, `{:error, :recipient_not_in_room}`. (FR-020.) The refusal MUST NOT distinguish "elsewhere in the world" from "in your room but offline" — same refusal text either way.
7. **Tell deliverability** (tell only) — `Phoenix.Presence` lookup; if zero metas, `{:error, :not_deliverable}`. (FR-016.)
8. **Broadcast** — construct the struct, broadcast on the appropriate topic, return `:ok`.

The LiveView maps each error tag to a refusal log entry per its own user-facing copy. The mapping table is part of `contracts/communication_api.md`.

---

## Entity relationship summary

```text
                ┌──────────────────────────────────┐
                │ GameLive (per LiveView session)  │
                │                                  │
                │  socket.assigns:                 │
                │    current_player.id  ─────┐     │
                │    current_player.username │     │
                │    current_room_id         │     │
                │    session_id (ref)        │     │
                └────────────────┬───────────┘     │
                                 │ submit_command  │
                                 ▼                 │
                ┌──────────────────────────────────┐
                │  World.CommandParser.parse/1     │
                │  → {:say,t} | {:emote,t}         │
                │    {:tell,r,t} | {:whisper,r,t}  │
                │    {:say_empty} | {:emote_empty} │
                │    {:tell_invalid} | …           │
                └────────────────┬─────────────────┘
                                 │ verb-specific call
                                 ▼
                ┌──────────────────────────────────┐
                │  World.Communication             │
                │   say/2 emote/2 tell/3 whisper/3 │
                │  ▸ trim, length-check            │
                │  ▸ RecipientResolver (tell/whp) │
                │  ▸ self-target check             │
                │  ▸ room-scope check (whisper)    │
                │  ▸ Presence check (tell)         │
                │  ▸ build struct, broadcast       │
                └────────────────┬─────────────────┘
                                 │ Phoenix.PubSub.broadcast/3
                                 ▼
        ┌────────────────────────────────────────────────┐
        │  Topic: room:<sid>   OR   player:<rid>         │
        │  Payload: %RoomUtterance{} OR %PrivateUtterance│
        └────────────────────────────────────────────────┘
                                 │ delivered to subscribers
                                 ▼
            ┌─────────────────────────────────────────┐
            │ GameLive.handle_info/2 (per subscriber) │
            │  filter (self-session for :say;         │
            │          recipient_id for :whisper)     │
            │  append :speech / :emote_action /       │
            │         :private_tell_in / :private_   │
            │         whisper_in log entry            │
            └─────────────────────────────────────────┘
```

No persistence layer appears in this diagram because there isn't one. The struct lives for the duration of the PubSub fan-out and the time it takes each subscriber to append a log entry to its in-memory socket assigns.

---

## What is explicitly NOT in the data model

| Not present | Where it would have lived | Why omitted |
|-------------|---------------------------|-------------|
| `world_utterances` Ecto schema | `lib/agenticrealms/world/schemas/utterance.ex` | FR-022: transient only. |
| `Spoken` / `Told` / `Whispered` domain events | `lib/agenticrealms/world/events/*.ex` | No Commanded involvement (research §2). |
| Communication aggregate | `lib/agenticrealms/world/communication_aggregate.ex` | No state to own. |
| `Utterance` projector | `lib/agenticrealms/world/projections/...` | Nothing to project — broadcast is the delivery mechanism, not a projection. |
| Per-recipient inbox | (would have been a new schema if persistence was chosen) | FR-022 / FR-016 — offline tells refused, not queued. |
| Chat history queries | (would have been new `Queries.*` functions) | FR-023 — no historical access. |
