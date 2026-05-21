# Phase 1 Data Model: Examine Objects and Players

This feature introduces no persisted entities, no migrations, and no event types. Every "model" below is an in-process struct / map shape, used to carry information between resolution, dispatch, and render. The persisted `world_objects.long_description` field (feature 003) is the only piece of stored state the feature reads — its shape is unchanged.

## 1. `Examine.Match`

The public success type returned by `World.Examine.examine/2`.

```elixir
defmodule AgenticRealms.World.Examine.Match do
  @moduledoc """
  Successful examine resolution. `target_kind` discriminates the two
  payload shapes:

    * `:object` — `name` is the object's stored name (`world_objects.name`
      preserved casing), `long_description` is `world_objects.long_description`
      verbatim.
    * `:player` — `name` is the matched player's display username
      (`account_players.username` preserved casing). `long_description` is
      `nil` — the player render branch hard-codes the placeholder body.
  """
  @enforce_keys [:target_kind, :name]
  defstruct [:target_kind, :name, :long_description]

  @type t :: %__MODULE__{
          target_kind: :object | :player,
          name: String.t(),
          long_description: String.t() | nil
        }
end
```

### Why these fields

- `target_kind` drives both the render-branch selection (object vs. player) and the telemetry tag.
- `name` is the canonical stored name, NOT the player's input — this is what gets shown in the log entry so the player can confirm which target was matched (FR-008's "object's name SHOULD be shown alongside").
- `long_description` is present only for objects. Player examinations carry no body data in this feature; future features (appearance, equipment, status) will add it without changing the struct's shape — they can extend by adding new fields with default `nil`.

## 2. `Examine.examine/2` result types

```elixir
@type result ::
        {:ok, Match.t()}
        | {:error, :no_current_room}
        | {:error, :no_such_target}
        | {:error, :ambiguous_in_room}
        | {:error, :ambiguous_in_inventory}
        | {:error, :ambiguous_mixed_kind}
        | {:error, :ambiguous_player}
        | {:error, :ambiguous_partial}
```

### Error variant mapping to player-facing messages

The variants are deliberately specific so the GameLive handler can map them to different player-facing messages (and so the test suite can assert which path was taken, not just "an error happened"). The `:ambiguous_*` cases all collapse to the same user-facing copy (`"Which one do you mean?"`) — the granularity exists for debugging and telemetry only.

| Variant                       | Player-facing message              | When                                                                                   |
|-------------------------------|-----------------------------------|-----------------------------------------------------------------------------------------|
| `:no_current_room`            | "You are nowhere."                | Acting player has no `PlayerState` row or `current_room_id` is nil (pathological).      |
| `:no_such_target`             | "You don't see that here."        | No exact and no partial match in any visible scope. Eligible for LLM fallback.          |
| `:ambiguous_in_room`          | "Which one do you mean?"          | >1 exact-match objects, none in inventory.                                              |
| `:ambiguous_in_inventory`     | "Which one do you mean?"          | >1 exact-match objects in inventory.                                                    |
| `:ambiguous_mixed_kind`       | "Which one do you mean?"          | Exact-match object AND exact-match player (FR-006a — never tie kinds).                  |
| `:ambiguous_player`           | "Which one do you mean?"          | >1 exact-match player usernames (pathological; possible under case-variant collisions). |
| `:ambiguous_partial`          | "Which one do you mean?"          | 0 exact matches, >1 partial-match targets across any scope.                             |

## 3. Target-resolution decision tree

The single algorithm `Examine.resolve_target/2` implements FR-006a. It takes `(player_id, target_string)` and is invoked from `examine/2` after the visible scope is gathered.

```
INPUT:
  - target_string: normalized lowercased noun phrase (the parser already
    lowercased and whitespace-collapsed; "__self__" is the parser-injected
    self-alias sentinel).
  - player_id: acting player.

PRE-RESOLUTION:
  - If target_string == "__self__":
      RETURN {:ok, Match{target_kind: :player, name: acting player's username}}.
      No further lookups needed.
  - Otherwise gather VISIBLE SCOPE:
      room_objects   = Queries.look_room(player_id).objects
                       (list of %{id, name, short_description})
      inventory      = Queries.list_inventory(player_id)
                       (list of %{id, name, short_description})
      same_room_pls  = Queries.other_occupants_of(current_room_id, player_id)
                       (list of %{id, username})  — already presence-filtered
      self_pl        = %{id: player_id, username: acting username}
      players        = same_room_pls ++ [self_pl]

STAGE 1 — EXACT MATCHING:
  exact_obj_room  = filter room_objects   where lower(name) == target_string
  exact_obj_inv   = filter inventory      where lower(name) == target_string
  exact_player    = filter players        where lower(username) == target_string

  total = length(exact_obj_room) + length(exact_obj_inv) + length(exact_player)

  CASE total OF
    0 → GOTO STAGE 3 (partial)
    1 → return the lone match wrapped in a Match struct
    >1 →
      IF exact_player != [] AND (exact_obj_room ++ exact_obj_inv) != []:
        RETURN {:error, :ambiguous_mixed_kind}     -- FR-006a "never tie"
      IF exact_player != [] AND length(exact_player) > 1:
        RETURN {:error, :ambiguous_player}
      -- otherwise: all remaining matches are objects → STAGE 2

STAGE 2 — INVENTORY > ROOM TIEBREAK (objects only):
  IF length(exact_obj_inv) == 1 AND exact_obj_inv != []:
    RETURN that single inventory object as a Match
  IF length(exact_obj_inv) > 1:
    RETURN {:error, :ambiguous_in_inventory}
  IF length(exact_obj_inv) == 0 AND length(exact_obj_room) > 1:
    RETURN {:error, :ambiguous_in_room}
  -- unreachable: covered above

STAGE 3 — PARTIAL / SUBSTRING (only when Stage 1 found 0 exact matches):
  partial_obj_room = filter room_objects where lower(name) CONTAINS target_string
  partial_obj_inv  = filter inventory    where lower(name) CONTAINS target_string
  partial_player   = filter players      where lower(username) CONTAINS target_string

  total = length(partial_obj_room) + length(partial_obj_inv) + length(partial_player)
  CASE total OF
    0 → RETURN {:error, :no_such_target}
    1 → return the lone partial match wrapped in a Match struct
    >1 → RETURN {:error, :ambiguous_partial}
```

### Worked examples

| Scope                                                                                       | Input               | Outcome                                                  |
|---------------------------------------------------------------------------------------------|---------------------|----------------------------------------------------------|
| Room: `[brass lantern]`, Inv: `[]`, Players: `[]`                                            | `brass lantern`     | `{:ok, Match{:object, "brass lantern", long_desc}}`     |
| Room: `[brass lantern]`, Inv: `[]`, Players: `[]`                                            | `lantern`           | `{:ok, Match{:object, "brass lantern", long_desc}}` (partial) |
| Room: `[brass lantern]`, Inv: `[brass lantern]`, Players: `[]`                               | `brass lantern`     | `{:ok, Match{:object, "brass lantern", inv-copy}}` (Stage 2 — inventory wins) |
| Room: `[brass lantern]`, Inv: `[]`, Players: `[lantern]` (player named "Lantern")            | `lantern`           | `{:error, :ambiguous_mixed_kind}`                       |
| Room: `[brass lantern, iron lantern]`, Inv: `[]`, Players: `[]`                              | `lantern`           | `{:error, :ambiguous_partial}` (0 exact, 2 partial)     |
| Room: `[brass lantern]`, Inv: `[]`, Players: `[Alice, Alicia]`                               | `alic`              | `{:error, :ambiguous_partial}`                          |
| Room: `[]`, Inv: `[]`, Players: `[Alice]` + self                                              | `me` (parser →`__self__`) | `{:ok, Match{:player, "<self-username>"}}`           |
| Room: `[]`, Inv: `[]`, Players: `[Alice]` + self                                              | `alice`             | `{:ok, Match{:player, "Alice"}}`                        |
| Room: `[]`, Inv: `[]`, Players: `[]` (Alice offline)                                         | `alice`             | `{:error, :no_such_target}`  (Presence filter)          |

## 4. `:detail` log-entry shape

Two flavors based on `target_kind`:

```elixir
# Object
%{
  kind: :detail,
  target_kind: :object,
  name: "brass lantern",
  long_description: "An old hand-lantern of dented brass. Its glass is smoked but unbroken, and a stub of candle still rests within."
}

# Player
%{
  kind: :detail,
  target_kind: :player,
  name: "Alice"
}
```

### Render branches (HEEx)

```heex
# in lib/agenticrealms_web/components/game_components.ex
def log_entry(%{entry: %{kind: :detail, target_kind: :object}} = assigns) do
  ~H"""
  <div class="log-entry detail detail-object">
    <div class="detail-head"><span class="detail-name">{@entry.name}</span></div>
    <div class="detail-body">{@entry.long_description}</div>
  </div>
  """
end

def log_entry(%{entry: %{kind: :detail, target_kind: :player}} = assigns) do
  ~H"""
  <div class="log-entry detail detail-player">
    <span class="detail-name">{@entry.name}</span> is a player.
  </div>
  """
end
```

Both clauses use HEEx interpolation (auto-escapes player-controlled strings — `name` for player examination comes from `account_players.username` which is itself constrained at registration; `long_description` for objects is seed-controlled but the auto-escape still applies as a defensive measure).

## 5. Parser sentinel extension

```elixir
@type result ::
        ...existing variants...
        | {:look}                    # unchanged — no-target room view
        | {:look, String.t()}        # NEW — target string, lowercased and whitespace-collapsed
                                     #       or the literal "__self__" sentinel
```

The parser maps:
- `look` / `l` (no rest) → `{:look}`
- `look me` / `look self` / `l me` / `l self` → `{:look, "__self__"}`
- `look <anything else>` → `{:look, normalize(rest_lc)}`

`normalize/1` and the lowercasing are already in the parser (used by `take` / `drop`); no new helpers required.

## 6. IntentResolver action_tuple extension

The `IntentResolver.action_tuple` type union (in `lib/agenticrealms/world/intent_resolver.ex:34-43`) gains the new shape:

```elixir
@type action_tuple ::
        ...existing variants...
        | {:look}                    # unchanged
        | {:look, String.t()}        # NEW — when the model passes a `target` argument
```

`IntentResolver.to_action/2` already has the clause `to_action("look", _), do: {:ok, {:look}}`. We extend it:

```elixir
defp to_action("look", %{"target" => t}) when is_binary(t) and t != "",
  do: {:ok, {:look, t}}

defp to_action("look", _), do: {:ok, {:look}}
```

Order matters — the more-specific pattern wins. The `is_binary(t) and t != ""` guard handles the schema-conformant-but-empty case (model sends `target: ""` for some reason) by collapsing to the no-target form rather than refusing — most charitable interpretation.

## 7. State diagram (none)

No state machine. Every examine call is a stateless, idempotent read against current world state. There is no transition, no event, no persisted side-effect.

## 8. Cross-feature contracts referenced

The data shapes above depend on (and do NOT alter):

- `Object` schema's `long_description` field (003).
- `account_players.username` uniqueness (002 / unchanged).
- `Queries.look_room/1`, `Queries.list_inventory/1`, `Queries.other_occupants_of/2` (003, with 003a's Presence filter applied inside `other_occupants_of/2`).
- `IntentResolver.action_tuple` shape (005).
- `CommandParser.result` shape (003 + 004).
