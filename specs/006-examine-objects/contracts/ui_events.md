# Contract: UI events (log-entry kind `:detail`)

## What's new

One new in-process log-entry kind: `:detail`. The LiveView appends it to the player's `:log` assign after a successful `Examine.examine/2` call. No event-store entry, no PubSub broadcast, no UIEvent struct.

## Shape

Object examination:

```elixir
%{
  kind: :detail,
  target_kind: :object,
  name: "brass lantern",
  long_description: "An old hand-lantern of dented brass. Its glass is smoked but unbroken, and a stub of candle still rests within."
}
```

Player examination:

```elixir
%{
  kind: :detail,
  target_kind: :player,
  name: "Alice"
}
```

`name` and `long_description` are pulled from the `Examine.Match` struct verbatim. The render layer is responsible for the placeholder text on the player branch (the body is hard-coded as `<name> is a player.`).

## Why no broadcast

SC-005 mandates zero witness entries for room peers. A player examining anything (object in room, object in inventory, another player in the room) is observably private — no broadcast, no PubSub publish, no log line on any other session.

Compare with the existing world events that DO broadcast:

| Event                        | Broadcasts? | Witness entry shape                       |
|------------------------------|-------------|-------------------------------------------|
| `take` (003)                 | Yes         | `Alice takes the brass lantern.`          |
| `drop` (003)                 | Yes         | `Alice drops the brass lantern.`          |
| `move` arrival (003)         | Yes         | `Alice arrives from the south.`           |
| `move` departure (003)       | Yes         | `Alice leaves to the north.`              |
| `say` / `emote` (004)        | Yes         | speech / emote line on every room peer    |
| `tell` (004)                 | Yes (to recipient only) | private inbound line              |
| `whisper` (004)              | Yes (room peers; rendered only to recipient) | private inbound line |
| **`examine` (006)**          | **No**      | **N/A — purely local read**                |

The decision is binding: the test suite asserts no broadcast (no message on `World.room_topic(current_room_id)`, no message on `World.player_topic(other_player_id)`).

## Render contract (HEEx)

In `lib/agenticrealms_web/components/game_components.ex`, two new `log_entry/1` clauses, inserted after the existing `:room` clauses and before `:narrate`:

```elixir
def log_entry(%{entry: %{kind: :detail, target_kind: :object}} = assigns) do
  ~H"""
  <div class="log-entry detail detail-object">
    <div class="detail-head">
      <span class="detail-name">{@entry.name}</span>
    </div>
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

Auto-escaped interpolation is sufficient for both branches. The `name` field is either a persisted object name (seed-controlled) or a persisted username (input-validated at registration). The `long_description` is seed-controlled today; if/when player-authored objects are added in a later feature, the same auto-escape continues to apply.

## CSS

`.log-entry.detail` should visually distinguish itself from `.log-entry.room` (per FR-003). Minimum acceptable styling: a different background tint / left-border accent, parallel to how `.log-entry.private` differs from `.log-entry.system`. No new CSS classes beyond `detail`, `detail-object`, `detail-player`, `detail-head`, `detail-name`, `detail-body`. Reuse existing typography tokens.

## Suggestion chips

The existing `GameData.suggestions/0` list MAY add an entry like `examine <object>` or `look at <object>` to expose the feature in the suggestion bar. Not required for the feature to be complete — players who discover the verb organically (via natural-language input through the AI fallback) will still get the right behavior.
