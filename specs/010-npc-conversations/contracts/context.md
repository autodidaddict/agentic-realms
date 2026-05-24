# Contract: `AgenticRealms.World.NPCChat.Context`

Assembles the per-turn LLM request from current state. Splits into two concerns: the system prompt context map (passed to `SystemPrompt.text/1`) and the messages array (history + current utterance).

## Functions

### `snapshot(player_id, npc_clone)`

```elixir
@spec snapshot(integer(), %NPCClone{}) :: %{
        npc_name: String.t(),
        lore: String.t(),
        room_name: String.t(),
        room_description: String.t(),
        other_players: [String.t()],
        objects: [%{name: String.t(), short_description: String.t()}],
        player_name: String.t()
      }
def snapshot(player_id, npc_clone)
```

Queries the read side (rooms, other players, objects) and assembles the context map for the system prompt. Called by the Task just before building the Anthropic request, so the snapshot reflects the room state at LLM-call time (not at conversation-start time — FR-007).

**Behavior**:

1. Resolve player's current room via `Queries.current_room_of/1`.
2. Fetch the room view via `Queries.look_room/1`.
3. Fetch the player's display name via `Accounts.get_player!/1`.
4. Map `npc_clone.name` → `npc_name`, `npc_clone.lore` → `lore`.
5. Map `room_view.other_players` to display names (strip any debug identity), filtering by `Presence.online?/1` (already the contract from feature 003b).
6. Map `room_view.objects` to `%{name, short_description}` (truncate short_description if needed).

**Note on the NPC's own presence**: the NPC IS in the room but is NOT included in `other_players` — they don't refer to themselves in third person. The NPC's own identity comes from `npc_name` / `lore`.

### `build_request(snapshot, turns, current_message)`

```elixir
@spec build_request(snapshot_map(), [turn()], String.t()) :: map()
def build_request(snapshot, turns, current_message)
```

Builds the JSON-shape Anthropic Messages API request body (the same shape `Anthropic.create_message/1` consumes).

```elixir
%{
  "max_tokens" => 256,
  "system" => [%{
    "type" => "text",
    "text" => SystemPrompt.text(snapshot),
    "cache_control" => %{"type" => "ephemeral"}    # marker for cache hits (best-effort)
  }],
  "tools" => Tools.list(),
  "tool_choice" => %{"type" => "any"},
  "messages" => message_history(turns) ++ [
    %{"role" => "user", "content" => current_message}
  ]
}
```

Where `message_history/1` maps the Conversation's `turns` to alternating `user` / `assistant` messages:

```elixir
defp message_history(turns) do
  Enum.map(turns, fn
    %{role: :player, text: text} ->
      %{"role" => "user", "content" => text}

    %{role: :npc, text: text, mode: :speech} ->
      %{"role" => "assistant", "content" => ~s(Garrick says, "#{text}")}
      # Actually: we represent the assistant's prior turns as PLAIN TEXT in
      # whichever mode they used. This avoids the LLM thinking previous turns
      # were tool calls. See test surface.

    %{role: :npc, text: text, mode: :emote} ->
      %{"role" => "assistant", "content" => "#{npc_name} #{text}"}
  end)
end
```

(Refine: the function takes `npc_name` from the snapshot to avoid passing it through every level.)

### Budget enforcement

If the rendered prompt exceeds the configured total-token budget (default 8000 tokens for Haiku 4.5; well under the 200k context window), `build_request/3` MUST evict the oldest turn-pair from the messages array and retry the size check, until either the prompt fits or `turns` is empty. Logged at debug level when eviction fires.

## Behavior contracts

- `snapshot/2` is impure (reads the database). All other functions are pure.
- The function does NOT include the chatting player in `other_players`.
- The function does NOT include any NPCs other than the participating NPC in the LLM-visible scene description (we're not modeling crowded-room awareness in this feature; the scene is just the room + other players + objects).
- The LLM-visible player display name is the `Accounts.Player.username` — not any debug id.

## Test surface

- `ContextTest`:
  - `snapshot/2` returns a map with all required keys.
  - `snapshot/2` does NOT include the chatting player in `other_players`.
  - `snapshot/2` does NOT include the NPC's debug identity anywhere.
  - `build_request/3` produces a request map with `max_tokens`, `system`, `tools`, `tool_choice`, `messages`.
  - With empty `turns`: messages array has exactly one entry (the current user message).
  - With one player + one NPC turn pair: messages array has 3 entries (user, assistant, user).
  - With > 20 turn pairs: oldest pairs are dropped from the array.
  - The `cache_control` marker is on the system block, NOT on individual messages.
