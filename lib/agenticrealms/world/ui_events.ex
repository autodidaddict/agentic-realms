defmodule AgenticRealms.World.UIEvents do
  @moduledoc """
  Transient UI event structs broadcast on `Phoenix.PubSub` topics so that
  `GameLive` can passively update logs and HUDs in response to world events.

  These are NOT persisted — domain events live in
  `AgenticRealms.World.Events.*` and are appended to the event store.

  See `specs/003-persisted-world/contracts/ui_events.md`.
  """

  defmodule RoomObjectTaken do
    @enforce_keys [:room_id, :actor_id, :actor_username, :object_id, :object_name]
    defstruct [:room_id, :actor_id, :actor_username, :object_id, :object_name]
  end

  defmodule RoomObjectDropped do
    @enforce_keys [:room_id, :actor_id, :actor_username, :object_id, :object_name]
    defstruct [:room_id, :actor_id, :actor_username, :object_id, :object_name]
  end

  defmodule RoomPlayerArrived do
    @enforce_keys [:room_id, :actor_id, :actor_username]
    defstruct [:room_id, :actor_id, :actor_username, :from_direction]
  end

  defmodule RoomPlayerLeft do
    @enforce_keys [:room_id, :actor_id, :actor_username, :to_direction]
    defstruct [:room_id, :actor_id, :actor_username, :to_direction]
  end

  defmodule RoomNPCArrived do
    @moduledoc """
    Transient NPC-arrival event. Broadcast on `room:<destination>` when an
    `NPCSpawnedInRoom` domain event fires while live sessions are present
    in the destination room. Feature 007 FR-011 / FR-012.

    Always directionless — NPCs in feature 007 do not move and have no
    source room (FR-012).
    """
    @enforce_keys [:room_id, :npc_id, :npc_name]
    defstruct [:room_id, :npc_id, :npc_name]
  end

  defmodule BehaviorUtterance do
    @moduledoc """
    Transient utterance produced by a behavior's :say action (feature 009).
    Broadcast on `player:<player_id>` topic, NEVER persisted, NEVER on the
    room topic — see `specs/009-npc-behaviors/research.md` R2 for the
    delivery-topic rationale.

    `kind` is `:npc_speech` (NPC clone speaker, attributed) or `:room_speech`
    (room source, unattributed ambient narration). `actor_name` is the
    clone's display name for `:npc_speech` and `nil` for `:room_speech`.
    """
    @enforce_keys [:kind, :text, :room_id, :triggering_player_id]
    defstruct [:kind, :actor_name, :text, :room_id, :triggering_player_id]
  end

  defmodule PlayerCurrentRoomChanged do
    @enforce_keys [:player_id, :to_room_id]
    defstruct [:player_id, :from_room_id, :to_room_id]
  end

  defmodule PlayerInventoryChanged do
    @enforce_keys [:player_id, :change, :object_id, :object_name, :object_short_description]
    defstruct [:player_id, :change, :object_id, :object_name, :object_short_description]
  end

  defmodule RoomUtterance do
    @moduledoc """
    Transient room-scoped utterance — `:say`, `:emote`, or `:whisper`.

    Broadcast on `room:<sender_room_id>` directly by `World.Communication` (no
    Commanded event handler involved — communication is non-event-sourced).

    For `:whisper`, every same-room subscriber receives the struct; non-recipient
    subscribers MUST drop it based on `recipient_id`. See
    `specs/004-player-communication/contracts/ui_events.md`.
    """
    @enforce_keys [:room_id, :actor_id, :actor_username, :actor_session_id, :kind, :text]
    defstruct [
      :room_id,
      :actor_id,
      :actor_username,
      :actor_session_id,
      :kind,
      :text,
      :recipient_id
    ]
  end

  defmodule PrivateUtterance do
    @moduledoc """
    Transient private utterance — `:tell`. Broadcast on `player:<recipient_id>`.

    Sender's other sessions do NOT subscribe to the recipient's player topic, so
    no actor-side filter is needed. See
    `specs/004-player-communication/contracts/ui_events.md`.
    """
    @enforce_keys [:actor_id, :actor_username, :recipient_id, :kind, :text]
    defstruct [:actor_id, :actor_username, :recipient_id, :kind, :text]
  end
end
