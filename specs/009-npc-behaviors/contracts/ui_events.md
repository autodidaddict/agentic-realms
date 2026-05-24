# Contract: `BehaviorUtterance` UI Event + GameLive Handlers

## UI event struct

`AgenticRealms.World.UIEvents.BehaviorUtterance`

```elixir
defmodule AgenticRealms.World.UIEvents.BehaviorUtterance do
  @moduledoc """
  Transient PubSub message produced by a behavior's :say action. Broadcast
  on `player:<player_id>` topic, NEVER persisted, NEVER on room_topic.

  See `specs/009-npc-behaviors/research.md` R2 for delivery-topic rationale.
  """

  @enforce_keys [:kind, :text, :room_id, :triggering_player_id]
  defstruct [:kind, :actor_name, :text, :room_id, :triggering_player_id]
end
```

| Field                  | Type            | Notes                                                                |
|------------------------|-----------------|----------------------------------------------------------------------|
| `kind`                 | atom            | `:npc_speech` or `:room_speech`.                                     |
| `actor_name`           | string \| nil   | NPC clone's display name for `:npc_speech`; `nil` for `:room_speech`. |
| `text`                 | string          | The line spoken (or narrated).                                        |
| `room_id`              | `binary_id`     | Diagnostic — the room where the behavior fired.                       |
| `triggering_player_id` | `integer`       | Diagnostic — the player whose movement triggered the firing.           |

Transient. Never persisted. Lives only on the `player:<player_id>` topic.

## Producer

`World.Behaviors.ActionExecutor.execute/4`, called by `World.Behaviors.Interpreter` for each `:say` action.

The producer's broadcast logic:

```elixir
def execute(speaker_ctx, %{"type" => "say", "text" => text}, room_id, triggering_player_id) do
  recipients = compute_recipients(speaker_ctx, room_id, triggering_player_id)

  utterance =
    case speaker_ctx do
      {:npc_clone, %{name: name}} ->
        %BehaviorUtterance{
          kind: :npc_speech,
          actor_name: name,
          text: text,
          room_id: room_id,
          triggering_player_id: triggering_player_id
        }

      {:room, _room_id} ->
        %BehaviorUtterance{
          kind: :room_speech,
          actor_name: nil,
          text: text,
          room_id: room_id,
          triggering_player_id: triggering_player_id
        }
    end

  Enum.each(recipients, fn p_id ->
    Phoenix.PubSub.broadcast(
      @pubsub,
      AgenticRealms.World.player_topic(p_id),
      utterance
    )
  end)
end

defp compute_recipients({:room, _}, _room_id, triggering_player_id) do
  # :room_speech is delivered ONLY to the triggering player.
  [triggering_player_id]
end

defp compute_recipients({:npc_clone, _}, room_id, triggering_player_id) do
  # :npc_speech is delivered to the triggering player + every OTHER player
  # in the speaker's room. Use MapSet to deduplicate if the projector hasn't
  # yet moved the triggering player out of the source room.
  other_ids =
    room_id
    |> Queries.other_occupants_of(triggering_player_id)
    |> Enum.map(& &1.id)

  [triggering_player_id | other_ids]
  |> MapSet.new()
  |> MapSet.to_list()
end

# Unknown action types are logged and skipped — never crash the behavior list.
def execute(_speaker_ctx, %{"type" => unknown}, _, _) do
  Logger.warning("Behaviors.ActionExecutor: unknown action type #{inspect(unknown)} — skipping")
  :ok
end

def execute(_speaker_ctx, malformed, _, _) do
  Logger.warning("Behaviors.ActionExecutor: malformed action #{inspect(malformed)} — skipping")
  :ok
end
```

## Subscriber: `GameLive`

`GameLive` subscribes to its own `player_topic(current_player.id)` on mount (existing behavior from feature 003) and never unsubscribes during movement.

Two new `handle_info/2` clauses:

```elixir
def handle_info(%BehaviorUtterance{kind: :npc_speech} = msg, socket) do
  {:noreply,
   append_log(socket, %{
     kind: :npc_speech,
     actor_name: msg.actor_name,
     text: msg.text
   })}
end

def handle_info(%BehaviorUtterance{kind: :room_speech} = msg, socket) do
  {:noreply,
   append_log(socket, %{
     kind: :room_speech,
     text: msg.text
   })}
end
```

Notes:
- The handlers do NOT check `room_id` or `triggering_player_id`. The interpreter has already filtered recipients at broadcast time — every message GameLive receives on its player-topic is for this player.
- The `room_id` and `triggering_player_id` fields on `BehaviorUtterance` are diagnostic only — they're not consumed by GameLive but available for telemetry / debug logging.

## Aliases to update in GameLive

```elixir
alias AgenticRealms.World.UIEvents.{
  RoomPlayerArrived,
  RoomPlayerLeft,
  RoomObjectTaken,
  RoomObjectDropped,
  RoomNPCArrived,
  BehaviorUtterance,     # NEW
  PlayerCurrentRoomChanged,
  PlayerInventoryChanged,
  RoomUtterance,
  PrivateUtterance
}
```

## Delivery guarantees

- **Triggering player always receives behavior-sourced entries** via their always-subscribed player-topic. No subscription-window race condition.
- **Multi-session delivery** (feature 003 FR-035): when a player has multiple concurrent sessions, each session subscribes to the same player-topic. PubSub fans out to all of them. Both sessions append the entry.
- **Bystanders for `:npc_speech`** are reached by enumerating "other occupants of room R" and broadcasting on each of their player-topics. The `Queries.other_occupants_of/2` function (existing in feature 003/008) already filters by Phoenix.Presence for online players, so offline players are correctly excluded.
- **Bystanders for `:room_speech`** are NOT reached — by design (FR-015).

## Acceptance: feature 007 / 008 regression

Feature 007's `RoomNPCArrived` (NPC spawn) and feature 008's room view rendering of NPC clones are unchanged. The new `BehaviorUtterance` is additive — no existing render kind or PubSub topic is repurposed.

## Test surface

- `test/agenticrealms/world/behaviors/interpreter_test.exs` — directly invokes the interpreter; subscribes to player-topics; asserts broadcasts arrive with expected `kind`, `actor_name`, `text`.
- `test/agenticrealms_web/live/game_live_behaviors_test.exs` — integration test that triggers movements via the LiveView and asserts the rendered HTML contains the expected `:npc_speech` / `:room_speech` log entries.
