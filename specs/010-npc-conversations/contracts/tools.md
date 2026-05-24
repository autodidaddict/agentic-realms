# Contract: `AgenticRealms.World.NPCChat.Tools`

The two tool definitions the chat LLM call uses. Forces structured speech-or-emote output via `tool_choice: any`.

## Function

```elixir
@spec list() :: [map()]
def list()
```

Returns the wire-format tool array for the Anthropic Messages API request.

```elixir
@spec names() :: MapSet.t(String.t())
def names()
```

Returns `MapSet.new(~w(say emote))`. Used by `Reply.parse/1` to validate the response.

## Tool definitions

```elixir
[
  %{
    "name" => "say",
    "description" =>
      "Speak a quoted utterance to the player. Use this when the NPC has " <>
      "something to say in words. The text will be rendered as the NPC speaking " <>
      "the words aloud.",
    "input_schema" => %{
      "type" => "object",
      "properties" => %{
        "text" => %{
          "type" => "string",
          "description" =>
            "The exact words the NPC speaks. One to three short sentences. " <>
            "No quotes — they will be added at render time. No third-person " <>
            "narration about yourself."
        }
      },
      "required" => ["text"]
    }
  },
  %{
    "name" => "emote",
    "description" =>
      "Perform a non-verbal gesture, body-language reaction, or facial " <>
      "expression. Use this for in-theme refusals (raising an eyebrow, " <>
      "looking puzzled), brief reactions, or moments where speech isn't " <>
      "the right response. The text will be rendered as third-person " <>
      "narration attributed to the NPC.",
    "input_schema" => %{
      "type" => "object",
      "properties" => %{
        "text" => %{
          "type" => "string",
          "description" =>
            "A short third-person narration of the NPC's action, written " <>
            "as a complete sentence. For example: 'raises an eyebrow " <>
            "curiously' or 'shrugs noncommittally and looks at the floor'. " <>
            "Do NOT include the NPC's name — it will be prepended at render time."
        }
      },
      "required" => ["text"]
    }
  }
]
```

## Behavior contracts

- The function MUST be pure and idempotent. Tests assert `Tools.list() == Tools.list()`.
- The schemas MUST be valid JSON-Schema (the test runs through `Jason.encode!/1` and back to verify shape).
- `names()` MUST return exactly `MapSet.new(["say", "emote"])` — no extras, no missing.

## Tool call validation (used by Reply.parse/1)

A response is considered well-formed iff:

1. The response `content` array contains exactly ONE `tool_use` block.
2. That block's `name` is in `Tools.names()`.
3. That block's `input.text` is a non-empty string after `String.trim/1`.

Multiple `tool_use` blocks, zero `tool_use` blocks, unknown tool name, or missing/empty `text` field MUST all be treated as malformed.

## Test surface

- `ToolsTest`:
  - `list/0` returns exactly 2 tools.
  - Both tools have `name`, `description`, `input_schema` keys.
  - Each schema requires a `text` property of type `string`.
  - `names/0` returns `MapSet.new(["say", "emote"])`.
  - The entire `list/0` round-trips through `Jason.encode!/1` then `Jason.decode!/1` without loss.
