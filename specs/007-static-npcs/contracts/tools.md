# Contract: IntentResolver `look` Tool + Context Snapshot Updates

Two narrow changes to the LLM resolver path so natural-language references to NPCs route correctly:

1. The `look` tool's description (in `lib/agenticrealms/world/intent_resolver/tools.ex`) gains a single phrase noting NPCs are valid examination targets.
2. The per-request `ContextSnapshot.render/3` adds an `NPCs here:` line so the model knows which NPC names and short descriptions are currently in scope.

The `take` tool is **unchanged** — see `contracts/take_refusal.md` for why.

## Change 1: `look` tool description

In `tools.ex`, the existing `look` tool description ends with:

> Examine, inspect, study, read, look-at, take-a-closer-look-at — all of these map to this tool with a `target`.

Replace the description's "examine a specific object or player" phrasing with "examine a specific object, player, or NPC currently in the room." The relevant phrasing change:

| Before                                                                                                                                                            | After                                                                                                                                                                                                  |
|-------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| "Render the player's current room (no target) OR examine a specific object or player (target)."                                                                   | "Render the player's current room (no target) OR examine a specific object, player, or NPC currently in the room (target)."                                                                            |
| "Pass a `target` to show the detail (long description) of a single object or player."                                                                              | "Pass a `target` to show the detail (long description) of a single object, player, or NPC."                                                                                                            |
| The `target` parameter description: "the name of a specific object or player to examine, as the player referred to it (e.g. 'brass lantern', 'lantern', 'alice', 'me')." | "the name of a specific object, player, or NPC to examine, as the player referred to it (e.g. 'brass lantern', 'lantern', 'alice', 'me', 'garrick', 'the innkeeper', 'the old man')."                  |

The tool's `input_schema` itself does NOT change — `target` remains an optional string. No new enum, no new property. The resolver path on the server side (`Examine.examine/2`) already handles whatever string the model passes, including descriptive paraphrases.

## Change 2: `ContextSnapshot` adds an `NPCs here:` line

In `lib/agenticrealms/world/intent_resolver/context_snapshot.ex`, the `render/3` function's template gains one new line and the `build/2` and `render/3` functions pull NPCs from the room view:

```elixir
def build(player_id, raw_input) when is_integer(player_id) and is_binary(raw_input) do
  case Queries.look_room(player_id) do
    {:ok, room} ->
      inventory = Queries.list_inventory(player_id)
      {:ok, render(room, inventory, raw_input)}

    {:error, _} ->
      {:error, :no_current_room}
  end
end

def render(room, inventory, raw_input) do
  """
  Current room: #{room.name}
  Description: #{truncate(room.description)}
  Exits: #{format_exits(room.exits)}
  Objects here: #{format_names(room.objects)}
  NPCs here: #{format_npcs(room.npcs)}                  # NEW
  Other players present: #{format_usernames(room.other_players)}
  Your inventory: #{format_inventory(inventory)}

  Player typed: #{raw_input}
  """
  |> String.trim_trailing()
end

defp format_npcs([]), do: "(none)"
defp format_npcs(npcs) do
  Enum.map_join(npcs, ", ", fn n ->
    case n.short_description do
      s when is_binary(s) and s != "" -> "#{n.name} (#{s})"
      _ -> n.name
    end
  end)
end
```

The NPC format includes both the display name AND the short description (in parentheses) so the model can resolve descriptive paraphrases like "the innkeeper" or "the old man" against the right NPC. Empty / nil short_description falls back to just the name (defensive — the schema forbids empty short descriptions but the helper is safe).

## Change 3: `look_room/1` already returns `npcs`

Per `contracts/queries.md`, `Queries.look_room/1` is extended to populate `RoomView.npcs`. The `ContextSnapshot.render/3` change above just reads from that new field.

## Change 4: System prompt addendum

In `priv/intent_resolver/system_prompt.md`, the section on the `look` tool gains one short paragraph:

> NPCs are non-player characters that appear in some rooms. They are valid examination targets — when the player asks to look at, examine, inspect, or study an NPC (by name like "garrick" or by descriptive paraphrase like "the innkeeper", "the old man", "the woman behind the bar"), use the `look` tool with `target` set to a noun phrase the server can resolve against the listed NPCs. The server normalizes case and accepts substring matches; pass the model's best guess of the NPC the player meant.

This addendum invalidates the 5-minute ephemeral prompt cache on first deploy after this feature ships — the first request pays one uncached invocation, subsequent requests warm normally. Same posture as feature 005's prompt changes and feature 006's tool-schema change.

## Acceptance: resolver routing

| Player input                              | Expected resolver output                             |
|-------------------------------------------|------------------------------------------------------|
| `look garrick`                            | Fast parser: `{:look, "garrick"}` (no LLM call).     |
| `examine garrick`                         | LLM fallback: `{:look, "garrick"}`.                  |
| `examine the innkeeper`                   | LLM fallback: `{:look, "innkeeper"}` or `{:look, "garrick"}` — both resolve correctly server-side. |
| `look at the old man behind the bar`      | LLM fallback: `{:look, "garrick"}` (the model uses the NPC's short description to disambiguate). |
| `pick up garrick`                         | Fast parser: `{:take, "garrick"}` → server returns `{:error, :object_is_fixed}` → "You can't take that." |
| `grab the innkeeper`                      | LLM fallback: `{:take, "innkeeper"}` → same refusal.  |

## Test coverage

`test/agenticrealms/world/intent_resolver/context_snapshot_test.exs` is extended to assert:
- The rendered snapshot includes the `NPCs here:` line.
- An empty NPC list renders as `(none)`.
- A populated NPC list renders as `Name 1 (short desc 1), Name 2 (short desc 2)`.

`test/agenticrealms_web/live/game_live_intent_parser_test.exs` is extended to cover the natural-language phrasings in the acceptance table above, mocking the resolver response (consistent with how 005/006 cover LLM-fallback paths).
