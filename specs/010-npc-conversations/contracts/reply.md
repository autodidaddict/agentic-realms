# Contract: `AgenticRealms.World.NPCChat.Reply`

Parses an Anthropic Messages API response body into a structured chat reply outcome. Pure — no I/O.

## Function

```elixir
@spec parse(map()) :: {:speech, String.t()} | {:emote, String.t()} | {:error, :malformed}
def parse(response_body)
```

## Behavior

1. Pluck `response_body["content"]`. If not a list → `{:error, :malformed}`.
2. Filter to entries with `"type" => "tool_use"`.
3. Match on the filtered list:
   - **Exactly one** `tool_use` block:
     - `block["name"] == "say"`, `block["input"]["text"]` is a non-empty string → `{:speech, trimmed_text}`.
     - `block["name"] == "emote"`, `block["input"]["text"]` is a non-empty string → `{:emote, trimmed_text}`.
     - Any other name, or missing/empty text → `{:error, :malformed}`.
   - Zero blocks → `{:error, :malformed}`.
   - More than one block → `{:error, :malformed}`.

Text is `String.trim/1`-ed before return.

## Behavior contracts

- Pure: same input → same output.
- Tolerates extra keys in the response body (only inspects `content`).
- Does not raise on any malformed input — every error path collapses to `{:error, :malformed}`.

## Test surface

- `ReplyTest`:
  - One `tool_use` block with `name: "say"`, `input.text: "Hello there."` → `{:speech, "Hello there."}`.
  - One `tool_use` block with `name: "emote"`, `input.text: "raises an eyebrow"` → `{:emote, "raises an eyebrow"}`.
  - One `tool_use` block with unknown name → `{:error, :malformed}`.
  - One `tool_use` block with `input.text == ""` → `{:error, :malformed}`.
  - One `tool_use` block with no `input.text` key → `{:error, :malformed}`.
  - Two `tool_use` blocks (one say + one emote) → `{:error, :malformed}` (FR-021 forbids mixing).
  - Zero `tool_use` blocks (e.g., only `text` blocks) → `{:error, :malformed}`.
  - Missing `content` key → `{:error, :malformed}`.
  - `content` not a list → `{:error, :malformed}`.
  - Leading/trailing whitespace in `input.text` is trimmed in the returned text.
