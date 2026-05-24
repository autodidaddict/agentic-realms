# Contract: `AgenticRealms.World.NPCChat` (public API)

Top-of-tree module that GameLive (and the IntentResolver) call to initiate a chat turn. Resolves the Conversation pid (cluster-aware) and forwards the request. Does NOT itself talk to the LLM.

## Functions

### `send(player_id, npc_token, message)`

```elixir
@spec send(integer(), String.t(), String.t()) ::
        {:ok, :new | :continuing}
        | {:error, :too_long}
        | {:error, :empty_message}
        | {:error, {:no_such_npc, String.t()}}
        | {:error, {:ambiguous_npc, [String.t()]}}
        | {:error, :still_thinking}
        | {:error, :no_current_room}
def send(player_id, npc_token, message)
```

**Behavior**:

1. Trim `message`. If empty → `{:error, :empty_message}`.
2. If `String.length(message) > 500` → `{:error, :too_long}` (FR-019a).
3. Resolve the player's current room via `Queries.current_room_of/1`. On failure → `{:error, :no_current_room}`.
4. Resolve `npc_token` against NPC clones in that room using `Examine.resolve/2`-style matching. On failure → `{:error, {:no_such_npc, npc_token}}` (FR-016) or `{:error, {:ambiguous_npc, candidate_names}}`.
5. Find or start the `Conversation` for `{player_id, npc_clone_id}` via `NPCChat.Supervisor.find_or_start/2`.
6. Forward the message via `GenServer.call(pid, {:send, player_id, message}, 5_000)`.
7. Return the GenServer's reply unchanged: `{:ok, :new | :continuing}` on accept, `{:error, :still_thinking}` on FR-020 lockout.

**Side effects**:
- May start a new Conversation GenServer (under Horde.DynamicSupervisor).
- Triggers asynchronous LLM call from inside the Conversation (the LiveView does NOT see this Task directly).

**Non-effects**:
- Does NOT broadcast any UI event itself. UI events flow only from the Conversation GenServer.
- Does NOT block on the LLM call.

### `find(player_id, npc_clone_id)`

```elixir
@spec find(integer(), String.t()) :: {:ok, pid()} | :error
def find(player_id, npc_clone_id)
```

Returns the registered Conversation pid for the pair, or `:error` if none exists. Exposed for testing and debugging. Does NOT start a new Conversation.

---

## Cluster semantics

- Calls succeed regardless of which node `NPCChat.send/3` is invoked on. `Horde.Registry` lookup is cluster-aware.
- If a new Conversation must be started, it spawns on a Horde-determined node (uniform distribution).
- A `GenServer.call` to a remote-node Conversation works transparently (BEAM distribution).

## Error semantics

- Every error variant is a tuple atom (or `{atom, payload}`) — no exception-driven control flow.
- The caller (GameLive) maps these to user-facing strings and renders them as ChatSystemMessage entries.

## Test surface

- `NPCChatTest.send/3`:
  - Returns `:no_such_npc` when the room has no matching NPC.
  - Returns `:ambiguous_npc` when multiple NPCs match.
  - Returns `:too_long` for inputs > 500 chars.
  - Returns `:empty_message` for whitespace-only input.
  - Returns `{:ok, :new}` on first send to a pair.
  - Returns `{:ok, :continuing}` on second send within the idle window.
  - Returns `{:error, :still_thinking}` while a prior call is in flight (FR-020).
  - Returns `{:ok, :new}` again after the idle timeout has elapsed.

- `NPCChat.find/2`:
  - Returns `:error` for a pair that has never chatted.
  - Returns `{:ok, pid}` for a pair with an active Conversation.
  - Returns `:error` after that Conversation's idle timeout elapses.
