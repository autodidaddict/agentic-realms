# Contract: NPCChat tools — `accept_quest`, `check_progress`, `finalize_quest`

Three new tools are added to `AgenticRealms.World.NPCChat.Tools.list/0` (`lib/agenticrealms/world/npc_chat/tools.ex`), alongside the existing `say` and `emote` tools.

All three tools follow the **uniform return contract from FR-011a** (set during the clarification session):

- Success: `{ok: true, ...}` (additional fields per tool)
- Failure: `{ok: false, reason: <atom>, details: <map>}`

The engine **never speaks directly** to the player from these tools. The NPC LLM is responsible for rendering both success and failure narratively on its next turn.

## Tool 1: `accept_quest`

**Tool schema** (LLM-visible):

```json
{
  "name": "accept_quest",
  "description": "Record that this player has formally accepted a quest from your catalog. Call this when the player expresses clear acceptance intent in natural language. The player will see the quest appear in their quest log and the required items will appear in the designated rooms.",
  "input_schema": {
    "type": "object",
    "properties": {
      "slug": {
        "type": "string",
        "description": "The slug of the quest from your catalog (provided to you in your system prompt under 'offerable quests')."
      }
    },
    "required": ["slug"]
  }
}
```

**Dispatch**: `AgenticRealms.World.NPCChat.Conversation.handle_tool_call/3` for `"accept_quest"` routes to:

```elixir
AgenticRealms.World.Commands.accept_quest(player_id, npc_blueprint_id, slug)
```

`player_id` and `npc_blueprint_id` come from the conversation's runtime context (the conversation is bound to a specific viewer + NPC at construction).

**Tool result**:

| Wrapper return | Tool result envelope |
|---|---|
| `{:ok, quest_id}` | `%{ok: true, quest_id: quest_id, slug: slug}` |
| `{:error, :unknown_slug}` | `%{ok: false, reason: :unknown_slug, details: %{slug: slug}}` |
| `{:error, :already_completed}` | `%{ok: false, reason: :already_completed, details: %{slug: slug}}` |
| `{:error, :already_active}` | `%{ok: false, reason: :already_active, details: %{slug: slug, quest_id: existing_quest_id}}` |

## Tool 2: `check_progress`

**Tool schema**:

```json
{
  "name": "check_progress",
  "description": "Look up the current progress on one of this player's active quests with you. Read-only. Call this when the player asks how they're doing on a quest, or when you need to know whether they're ready to finalize.",
  "input_schema": {
    "type": "object",
    "properties": {
      "quest_id": {
        "type": "string",
        "description": "The quest_id of an active quest instance (provided to you in your system prompt under 'this player's active quests with you')."
      }
    },
    "required": ["quest_id"]
  }
}
```

**Dispatch**:

```elixir
AgenticRealms.World.Commands.check_progress(player_id, quest_id)
```

**Tool result**:

| Wrapper return | Tool result envelope |
|---|---|
| `{:ok, criteria_progress}` | `%{ok: true, quest_id: quest_id, criteria: criteria_progress}` where `criteria_progress = [%{name, count, target}, ...]` |
| `{:error, :unknown_instance}` | `%{ok: false, reason: :unknown_instance, details: %{quest_id: quest_id}}` |

## Tool 3: `finalize_quest`

**Tool schema**:

```json
{
  "name": "finalize_quest",
  "description": "Complete the quest, taking the required items from the player and giving them the reward. Call this when the player expresses clear turn-in intent in natural language. Atomic: if the player is missing any required items, no state changes occur and you receive a structured failure listing what's missing.",
  "input_schema": {
    "type": "object",
    "properties": {
      "quest_id": {
        "type": "string",
        "description": "The quest_id of an active quest instance (provided to you in your system prompt under 'this player's active quests with you')."
      }
    },
    "required": ["quest_id"]
  }
}
```

**Dispatch**:

```elixir
AgenticRealms.World.Commands.finalize_quest(player_id, quest_id)
```

**Tool result**:

| Wrapper return | Tool result envelope |
|---|---|
| `{:ok, %{quest_id, reward_name, reward_description}}` | `%{ok: true, quest_id: quest_id, reward_name: reward_name, reward_description: reward_description}` |
| `{:error, :unknown_instance}` | `%{ok: false, reason: :unknown_instance, details: %{quest_id: quest_id}}` |
| `{:error, :criteria_unmet, missing: missing}` | `%{ok: false, reason: :criteria_unmet, details: %{quest_id: quest_id, missing: missing}}` where `missing = [%{name, count, target}, ...]` |

## Conversation handler integration

`AgenticRealms.World.NPCChat.Conversation.handle_tool_call/3` gains three clauses, e.g.:

```elixir
def handle_tool_call(%{name: "accept_quest", input: %{"slug" => slug}}, %ConvCtx{viewer_player_id: pid, npc_blueprint_id: bid}, _state) do
  case Commands.accept_quest(pid, bid, slug) do
    {:ok, quest_id} ->
      %{ok: true, quest_id: quest_id, slug: slug}

    {:error, reason} when reason in [:unknown_slug, :already_completed] ->
      %{ok: false, reason: reason, details: %{slug: slug}}

    {:error, :already_active, existing_quest_id} ->
      %{ok: false, reason: :already_active, details: %{slug: slug, quest_id: existing_quest_id}}
  end
end
```

The shape passed back to the LLM (via the existing tool-result envelope) is the `%{ok: ...}` map.

## Tests (`test/agenticrealms/world/npc_chat/tools_quest_test.exs`)

- `Tools.list/0` returns five tools total (`say`, `emote`, plus the three new ones).
- Each new tool's `input_schema` matches the doc above.
- `Conversation.handle_tool_call/3` returns the expected envelope shape on each success and each failure branch — exhaustively covered.
