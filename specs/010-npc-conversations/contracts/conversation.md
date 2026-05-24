# Contract: `AgenticRealms.World.NPCChat.Conversation` (GenServer)

The per-pair state holder. One process per `(player_id, npc_clone_id)` registered in `NPCChat.Registry`. Holds rolling history, enforces lockout, manages idle timeout, fronts the Anthropic call via an internal Task, and broadcasts reply UI events.

## Process registration

```elixir
{:via, Horde.Registry, {AgenticRealms.World.NPCChat.Registry, {player_id, npc_clone_id}}}
```

## Init

```elixir
@spec start_link({integer(), %NPCClone{}}) :: GenServer.on_start()
```

Init args: `{player_id, npc_clone}` (the clone is passed in so init doesn't have to re-query — `NPCChat.send/3` already has it).

Init body caches `npc_name`, `npc_clone_id`, `lore` from the clone struct, sets `turns: []`, `pending?: false`, `last_activity_at: nil`, then `{:ok, state, @idle_timeout}`.

## Calls

### `{:send, player_id, message}`

Returns `{:ok, :new | :continuing}` or `{:error, :still_thinking}`.

Behavior:

- If `pending? == true` → `{:reply, {:error, :still_thinking}, state, @idle_timeout}`. State unchanged.
- Otherwise:
  1. Determine `new_or_continuing`:
     - `last_activity_at == nil` OR `now - last_activity_at > 60_000` → `:new` (with a fresh history — drop any stale `turns`).
     - Otherwise → `:continuing`.
  2. Stash `pending_player_message = message`, set `pending? = true`, set `last_activity_at = now`.
  3. Spawn an async Task under `NPCChat.TaskSupervisor` that:
     - Builds the request via `NPCChat.Context.build_request/3` (lore + system prompt + tools + history + current user message).
     - Calls `Anthropic.create_message/1`.
     - Sends `{:llm_result, pid, result}` to `self()` (the Conversation pid).
     - Errors are mapped to `{:llm_result, pid, {:error, reason}}`.
  4. Reply with `{:reply, {:ok, new_or_continuing}, state, @idle_timeout}`.

If the `:send` is for a NEW conversation (case 1.i above), the Conversation MUST emit a `ChatSystemMessage{kind: :chat_new}` on `player_topic` BEFORE returning. (The "new" indicator MUST render before any reply per FR-003.) For a continuing conversation, emit `ChatSystemMessage{kind: :chat_continuing}` BEFORE returning.

### `{:get_state}` (test-only)

Returns `{:reply, state, state, @idle_timeout}`. Used by tests to inspect history, pending state, etc.

## Casts

None in this feature.

## Info messages

### `{:llm_result, task_ref, {:ok, response_body}}`

1. Parse `response_body` via `NPCChat.Reply.parse/1`. Result is `{:speech, text} | {:emote, text} | {:error, :malformed}`.
2. If `{:error, :malformed}`: treat as a failed call (next case).
3. Append the player turn (`pending_player_message`) AND the NPC turn (mode + text) to `turns`.
4. Trim `turns` so `length(turns) <= 40` (= 20 player+NPC pairs); drop from the head.
5. Broadcast `ChatUtterance{kind: :chat_speech | :chat_emote, ...}` on `player_topic(player_id)`.
6. Clear `pending?`, `pending_player_message`, `task_ref`.
7. `{:noreply, new_state, @idle_timeout}`.

### `{:llm_result, task_ref, {:error, reason}}`

1. DO NOT append `pending_player_message` to `turns` (FR-011 — failed call doesn't pollute history).
2. Broadcast `ChatSystemMessage{kind: :chat_fallback, npc_name: state.npc_name, text: "{npc_name} seems lost in thought.", ...}` on `player_topic(player_id)`.
3. Clear `pending?`, `pending_player_message`, `task_ref`.
4. `{:noreply, new_state, @idle_timeout}`.

### `:timeout`

Idle for 60s. Return `{:stop, :normal, state}`. Horde reaps the registry entry.

### `{:DOWN, ref, :process, _, reason}` (Task.Supervisor.async_nolink result)

If `ref == task_ref` and `reason != :normal`: treat as `:llm_result` failure.

## Configuration

- `@idle_timeout`: read from `Application.get_env(:agenticrealms, AgenticRealms.World.NPCChat, [])[:idle_timeout_ms]`, default `60_000`. Tests override to a small value (e.g., `200`).
- `@max_tokens`: hardcoded at `256` (matches FR-019b default).
- `@history_cap_pairs`: hardcoded at `20`.

## Test surface

- `ConversationTest`:
  - On a fresh Conversation, first `:send` returns `{:ok, :new}` and broadcasts a `ChatSystemMessage{kind: :chat_new}` BEFORE returning.
  - A subsequent `:send` within 60s returns `{:ok, :continuing}` and broadcasts a `ChatSystemMessage{kind: :chat_continuing}` BEFORE returning.
  - While `pending?: true`, a second `:send` returns `{:error, :still_thinking}` and does NOT mutate state.
  - On `{:llm_result, _, {:ok, valid_speech_response}}`: history grows by 2 entries (player + NPC), `pending?` clears, `ChatUtterance{kind: :chat_speech}` is broadcast.
  - On `{:llm_result, _, {:ok, valid_emote_response}}`: same as above with `kind: :chat_emote`.
  - On `{:llm_result, _, {:error, reason}}`: history does NOT grow; `pending?` clears; `ChatSystemMessage{kind: :chat_fallback}` is broadcast.
  - On `{:llm_result, _, {:ok, malformed_response}}`: same as failure path.
  - History trim: after 21 successful turns the history has exactly 20 pairs (40 entries); the oldest pair is gone.
  - Idle-timeout: with override `idle_timeout_ms = 200`, the process terminates within ~250ms of inactivity; `Process.alive?/1` returns false; Horde.Registry lookup returns `[]`.
