# Contract: `AgenticRealms.World.Examine`

Public read-side facade for the look-at-target action. Pure functions over the Repo — no Commanded dispatch, no events, no broadcasts.

## `examine/2`

```elixir
@spec examine(player_id :: integer(), target :: String.t()) ::
        {:ok, AgenticRealms.World.Examine.Match.t()}
        | {:error, :no_current_room
                  | :no_such_target
                  | :ambiguous_in_room
                  | :ambiguous_in_inventory
                  | :ambiguous_mixed_kind
                  | :ambiguous_player
                  | :ambiguous_partial}
def examine(player_id, target) when is_integer(player_id) and is_binary(target)
```

### Contract

- **Input**: `player_id` MUST be an integer matching an existing `account_players.id`. `target` MUST be a non-empty string. Callers are responsible for trimming and lowercasing — the parser does this. `target == "__self__"` is the reserved sentinel for self-examination (parser maps `me` / `self` to this).
- **Output**: exactly one of the success or error variants in `data-model.md` §3.
- **Side effects**: emits `[:agenticrealms, :examine, :resolve]` telemetry once per call with metadata `%{player_id, outcome, target_kind: :object | :player | nil}`. No DB writes, no PubSub publishes, no log entries.
- **Failure modes**: NEVER raises. A pathological state (Repo down, sandbox checkout missing) propagates the underlying Ecto error — callers MUST be prepared for that, but the LiveView's `handle_event` already exits cleanly on uncaught exceptions and Phoenix.LiveView restarts the socket.

### Examples

```elixir
# Object in room
{:ok, %Match{target_kind: :object, name: "brass lantern", long_description: "An old hand-lantern..."}} =
  Examine.examine(player_id, "brass lantern")

# Object in inventory (carried, room has no copy)
{:ok, %Match{target_kind: :object, name: "leather-bound journal", long_description: "A slim journal..."}} =
  Examine.examine(player_id, "journal")

# Other player in same room
{:ok, %Match{target_kind: :player, name: "Alice", long_description: nil}} =
  Examine.examine(player_id, "alice")

# Self via the parser-mapped sentinel
{:ok, %Match{target_kind: :player, name: "<acting username>", long_description: nil}} =
  Examine.examine(player_id, "__self__")

# Target not visible (in another room, or offline player)
{:error, :no_such_target} = Examine.examine(player_id, "dragon")

# Ambiguous partial match
{:error, :ambiguous_partial} =
  Examine.examine(player_id, "lantern") # when 2+ objects contain "lantern"
```

## `AgenticRealms.World.Examine.Match`

Struct returned on success.

```elixir
@type t :: %__MODULE__{
        target_kind: :object | :player,
        name: String.t(),
        long_description: String.t() | nil
      }
```

- `target_kind: :object` → `long_description` is non-nil (the persisted `world_objects.long_description`).
- `target_kind: :player` → `long_description` is `nil` (the placeholder text is hard-coded in the render branch).

## Test surface

The module is tested directly via `test/agenticrealms/world/examine_test.exs` against a seeded fixture. The test file MUST cover:

- Successful resolution: object in room, object in inventory, player in room, self.
- Stage 2 tiebreak: same name in room AND inventory → inventory wins.
- Stage 1 mixed-kind tie: object and player with the same exact name → `:ambiguous_mixed_kind`.
- Partial matching: unique substring match → success.
- Partial multi-match: 2+ substrings match → `:ambiguous_partial`.
- No match: `:no_such_target`.
- Offline-player filter: a player who has logged out is not examinable from their last-seen room.
- Self-alias: `"__self__"` resolves to the acting player without DB scope-gathering.
