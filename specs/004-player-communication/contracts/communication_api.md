# Contract — `AgenticRealms.World.Communication` public API

The facade module owns the entire write side of communication. Its inputs come from `GameLive` (after parsing); its outputs are PubSub broadcasts and tagged return values that the LiveView maps to log entries.

## Module location

`lib/agenticrealms/world/communication.ex`

This is parallel to (and intentionally distinct from) `lib/agenticrealms/world/commands.ex`. `Commands` is the Commanded write-side facade — it dispatches commands that mutate world state. `Communication` is the non-Commanded write-side facade — it broadcasts utterances that mutate nothing.

## Sender input shape

Every public function in `Communication` takes a `sender` map as the first argument:

```elixir
@type sender :: %{
        required(:id) => integer(),
        required(:username) => binary(),
        required(:session_id) => reference(),
        required(:room_id) => binary()
      }
```

The map is constructed by `GameLive` from socket assigns immediately before the call. No defaults; missing fields are programmer errors.

## Function contracts

### `say/2`

```elixir
@spec say(sender(), text :: String.t()) ::
        :ok
        | {:error, :empty}
        | {:error, :too_long}
```

**Behavior**:

1. Trim `text`.
2. If empty → `{:error, :empty}`.
3. If `String.length(text) > 500` → `{:error, :too_long}`.
4. Build `%RoomUtterance{room_id: sender.room_id, actor_id: sender.id, actor_username: sender.username, actor_session_id: sender.session_id, kind: :say, text: text, recipient_id: nil}`.
5. `Phoenix.PubSub.broadcast(AgenticRealms.PubSub, World.room_topic(sender.room_id), struct)`.
6. Return `:ok`.

Note: no Presence check (the broadcast is best-effort), no actor exclusion at the broadcast layer (witnesses self-filter via `actor_session_id` per `contracts/ui_events.md`).

### `emote/2`

```elixir
@spec emote(sender(), text :: String.t()) ::
        :ok
        | {:error, :empty}
        | {:error, :too_long}
```

**Behavior**:

1. Trim `text`.
2. If empty → `{:error, :empty}`.
3. If `String.length(text) > 500` → `{:error, :too_long}`.
4. Apply trailing-punctuation rule (FR-008): if `text` ends in `.`, `!`, or `?` keep as-is, else append `.`. This produces the final `text` carried in the struct.
5. Build `%RoomUtterance{..., kind: :emote, text: text_with_punctuation, recipient_id: nil}`.
6. Broadcast on `World.room_topic(sender.room_id)`.
7. Return `:ok`.

Trailing-punctuation handling is in the facade (not the rendering layer) so witnesses, including the actor, see the same final string. Single source of truth.

### `tell/3`

```elixir
@spec tell(sender(), recipient_name :: String.t(), text :: String.t()) ::
        {:ok, %{recipient_id: integer(), recipient_username: binary()}}
        | {:error, :empty}
        | {:error, :too_long}
        | {:error, :not_found}
        | {:error, :ambiguous}
        | {:error, :self_target}
        | {:error, :not_deliverable}
```

**Behavior**:

1. Trim `text`.
2. If empty → `{:error, :empty}`.
3. If `String.length(text) > 500` → `{:error, :too_long}`.
4. Resolve `recipient_name` via `Communication.RecipientResolver.resolve(recipient_name, sender.id)`:
   - `{:error, :not_found}`, `{:error, :ambiguous}`, `{:error, :self_target}` propagate.
   - `{:ok, %{id: rid, username: rname}}` continues.
5. Check Presence: `AgenticRealmsWeb.Presence.get_by_key(Presence.topic(), Integer.to_string(rid))`. If `nil` or `%{metas: []}` → `{:error, :not_deliverable}`.
6. Build `%PrivateUtterance{actor_id: sender.id, actor_username: sender.username, recipient_id: rid, kind: :tell, text: text}`.
7. `Phoenix.PubSub.broadcast(AgenticRealms.PubSub, World.player_topic(rid), struct)`.
8. Return `{:ok, %{recipient_id: rid, recipient_username: rname}}` so the LiveView can render the actor-side "You tell <rname>, '…'." confirmation with the canonical username casing.

### `whisper/3`

```elixir
@spec whisper(sender(), recipient_name :: String.t(), text :: String.t()) ::
        {:ok, %{recipient_id: integer(), recipient_username: binary()}}
        | {:error, :empty}
        | {:error, :too_long}
        | {:error, :not_found}
        | {:error, :ambiguous}
        | {:error, :self_target}
        | {:error, :recipient_not_in_room}
```

**Behavior**:

1. Trim `text`.
2. If empty → `{:error, :empty}`.
3. If `String.length(text) > 500` → `{:error, :too_long}`.
4. Resolve `recipient_name` (same call as `tell/3`).
5. Check room scope: `World.Queries.other_occupants_of(sender.room_id, sender.id)` and assert the resolved recipient is in the result. If not → `{:error, :recipient_not_in_room}`. (No Presence check needed — being in the room implies at least one session.)
6. Build `%RoomUtterance{room_id: sender.room_id, actor_id: sender.id, actor_username: sender.username, actor_session_id: sender.session_id, kind: :whisper, text: text, recipient_id: rid}`.
7. Broadcast on `World.room_topic(sender.room_id)`.
8. Return `{:ok, %{recipient_id: rid, recipient_username: rname}}`.

The room broadcast is intentional and correct: every room subscriber receives the struct, but every non-recipient subscriber drops it per the `kind: :whisper` rule in `contracts/ui_events.md`. The recipient's own room-topic subscription is what delivers the message to them — there's no separate whisper topic.

### `RecipientResolver.resolve/2`

```elixir
@spec resolve(name :: String.t(), sender_id :: integer()) ::
        {:ok, %{id: integer(), username: binary()}}
        | {:error, :not_found}
        | {:error, :ambiguous}
        | {:error, :self_target}
```

**Behavior**: see `research.md` §5. Single query:

```elixir
from(p in AgenticRealms.Accounts.Player,
  where: fragment("LOWER(?) = LOWER(?)", p.username, ^name),
  select: %{id: p.id, username: p.username}
)
|> AgenticRealms.Repo.all()
|> case do
  [] -> {:error, :not_found}
  [%{id: ^sender_id}] -> {:error, :self_target}
  [player] -> {:ok, player}
  [_ | _] -> {:error, :ambiguous}
end
```

The order matters: `:self_target` is checked BEFORE `:ambiguous` so that if a player typoed their own name and there happens to be another player with a case-variant of it, we'd still tell them they targeted themselves. But there's only one player matching their exact id in any case; the ordering distinction would only matter in pathological cases. The explicit ordering in the case clause locks the behavior.

## Concurrency

Each `Communication` function is a pure synchronous call from the LiveView process — no GenServer, no Task, no async. The Ecto query (recipient resolve) and the PubSub broadcast both happen in the calling process. There is no shared mutable state to coordinate. Two concurrent `say/2` calls produce two independent broadcasts; PubSub delivers each in FIFO order per subscriber.

## Error mapping (for `GameLive`)

`GameLive` maps facade error tags to user-facing refusal copy. See `contracts/ui_events.md` for the canonical table.

## Out-of-process callers

Tests are expected to call `Communication.say/2` etc. directly (skipping the parser and the LiveView) to assert the broadcast/refusal behavior in isolation. The contract guarantees this works — no LiveView-specific state is required at the facade boundary; only the `sender` map.
