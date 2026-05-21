# Contract: IntentResolver tool definitions diff

The only tool affected by this feature is `look`. Every other tool (`take`, `drop`, `move`, `inventory`, `say`, `emote`, `tell`, `whisper`, `refuse`) is unchanged.

## `look` — before (005)

```json
{
  "name": "look",
  "description": "Render the player's current room — its name, description, exits, objects visible, and other players present. Use this ONLY when the player wants to see their surroundings as a whole. DO NOT use this when the player wants to examine, inspect, study, or read a specific object — there is no examine tool yet; use `refuse` with a hint instead.",
  "input_schema": {
    "type": "object",
    "properties": {},
    "required": []
  }
}
```

## `look` — after (006)

```json
{
  "name": "look",
  "description": "Render the player's current room (no target) OR examine a specific object or player (target). Use no target to show the room as a whole — its name, description, exits, objects visible, and other players present. Pass a `target` to show the detail (long description) of a single object or player. Examine, inspect, study, read, look-at, take-a-closer-look-at — all of these map to this tool with a `target`.",
  "input_schema": {
    "type": "object",
    "properties": {
      "target": {
        "type": "string",
        "description": "Optional. The name of a specific object or player to examine, as the player referred to it (e.g. 'brass lantern', 'lantern', 'alice', 'me'). Omit this property entirely to render the whole room. Case-insensitive — the game performs its own resolution against actual room/inventory/player contents. For self-examination ('look at me', 'examine myself'), pass the literal string 'me'."
      }
    },
    "required": []
  }
}
```

## Diff summary

1. **Description rewritten**: dual-purpose now ("Render the room OR examine a target"). The "DO NOT use this for examining specific objects" guidance is REMOVED — that prohibition was the entire point of feature 006 to reverse.
2. **`target` property added**, optional. The description tells the model: (a) the property maps to examine/inspect/study/read/look-at, (b) lowercase doesn't matter (the game does case-insensitive lookup), (c) self-examination uses the literal `"me"`.
3. **`required` stays empty** — calling `look` with no `target` (the room-view path) remains valid.

## Parsing-side change in `IntentResolver`

`IntentResolver.to_action/2` adds one new clause BEFORE the existing fallback clause:

```elixir
defp to_action("look", %{"target" => t}) when is_binary(t) and t != "",
  do: {:ok, {:look, t}}

defp to_action("look", _), do: {:ok, {:look}}    # existing — kept as fallback
```

The action_tuple union in the module's `@type action_tuple` gains `{:look, String.t()}`.

## `Tools.names/0`

Unchanged. The set of tool NAMES is identical; only one tool's INPUT SCHEMA changed.

## Cache-marker impact

The `cache_control: {type: ephemeral}` marker remains on the system block. The first request after deploy will be a cache miss (the tool schema content changed → cache prefix differs → no hit). Subsequent requests warm normally. Same one-deploy-cost pattern feature 005 documented in its plan.

## Test surface

`test/agenticrealms/world/intent_resolver/tools_test.exs` extends to assert:

- `Tools.list/0` returns exactly 10 tools (unchanged count).
- The `look` tool's `input_schema.properties` contains a `target` property with `type: "string"`.
- The `look` tool's `input_schema.required` is `[]` (still optional).
- Every other tool's schema is byte-identical to the 005 baseline (regression guard — a contract test catching an inadvertent edit to take/drop/move/etc.).
