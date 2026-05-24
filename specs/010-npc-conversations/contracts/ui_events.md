# Contract: `AgenticRealms.World.UIEvents` — chat additions

Adds two new transient UI event structs to the existing `UIEvents` module. Same pattern as feature 009's `BehaviorUtterance`.

## `ChatUtterance`

The NPC's reply, in either speech or emote mode.

```elixir
defmodule AgenticRealms.World.UIEvents.ChatUtterance do
  @moduledoc """
  Transient render-only UI event delivered ONLY to the chatting player's
  player_topic. Distinct from `BehaviorUtterance` from feature 009 — that
  event broadcasts on the public room channel; this one is private.

  See `specs/010-npc-conversations/contracts/ui_events.md`.
  """

  @enforce_keys [:kind, :npc_clone_id, :npc_name, :text, :triggering_player_id]
  defstruct [:kind, :npc_clone_id, :npc_name, :text, :triggering_player_id]

  @type t :: %__MODULE__{
          kind: :chat_speech | :chat_emote,
          npc_clone_id: String.t(),
          npc_name: String.t(),
          text: String.t(),
          triggering_player_id: integer()
        }
end
```

## `ChatSystemMessage`

System frame messages: the "starting new" / "continuing" indicator, the fallback line on LLM failure, and the in-flight rejection.

```elixir
defmodule AgenticRealms.World.UIEvents.ChatSystemMessage do
  @moduledoc """
  Transient render-only UI event for the meta-frame around a chat — the
  new-vs-continuing indicator (FR-003), the in-flight rejection (FR-020),
  and the fallback line on LLM failure (FR-011). Always private to the
  chatting player.
  """

  @enforce_keys [:kind, :npc_name, :text, :player_id]
  defstruct [:kind, :npc_name, :text, :player_id]

  @type t :: %__MODULE__{
          kind:
            :chat_new
            | :chat_continuing
            | :chat_in_flight_rejection
            | :chat_fallback,
          npc_name: String.t(),
          text: String.t(),
          player_id: integer()
        }
end
```

## Delivery surface

Both events are broadcast via:

```elixir
Phoenix.PubSub.broadcast(
  AgenticRealms.PubSub,
  AgenticRealms.World.player_topic(player_id),
  %ChatUtterance{...}  # or %ChatSystemMessage{...}
)
```

The chatting player's `GameLive` (which subscribes to `player_topic(player_id)` on connected mount) receives them via `handle_info/2`.

## Privacy contract

**MUST**: Neither struct may be broadcast on `World.room_topic(_)` or on any other player's `player_topic`. This is verified by SC-007 (the zero-leak audit in the LiveView integration test).

## Per-kind rendered text

| kind                          | Source                                 | Example text                                                    |
|-------------------------------|----------------------------------------|-----------------------------------------------------------------|
| `:chat_new`                   | Conversation, on first send within window | "You begin a conversation with Garrick the Innkeeper."         |
| `:chat_continuing`            | Conversation, on subsequent send within window | "You continue your conversation with Garrick the Innkeeper." |
| `:chat_in_flight_rejection`   | Conversation, on FR-020 lockout         | "Garrick the Innkeeper hasn't finished thinking yet — give them a moment." |
| `:chat_fallback`              | Conversation, on FR-011 LLM failure     | "Garrick the Innkeeper seems lost in thought."                  |
| `:chat_speech` (ChatUtterance)| Conversation, on successful speech reply | (`text` is the NPC's spoken text — rendering adds attribution) |
| `:chat_emote`  (ChatUtterance)| Conversation, on successful emote reply  | (`text` is the third-person narration — rendering prepends the NPC's name) |

## Test surface

- `UIEventsTest`:
  - `ChatUtterance` requires all 5 keys; struct-creation without them raises.
  - `ChatSystemMessage` requires all 4 keys; struct-creation without them raises.
  - Two structs are NOT confusable (different module names; pattern matches discriminate).

- Integration test (`game_live_chat_test.exs`):
  - SC-007 zero-leak: while Alice is chatting with Garrick, Bob's rendered log shows zero occurrences of Garrick's reply text (across both speech and emote modes), zero occurrences of Alice's chat input, and zero occurrences of the chat-system indicator text.
