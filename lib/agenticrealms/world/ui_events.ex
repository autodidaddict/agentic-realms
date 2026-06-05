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
    defstruct [:room_id, :actor_id, :actor_username, :from_direction, carried_object_ids: []]
  end

  defmodule RoomPlayerLeft do
    @enforce_keys [:room_id, :actor_id, :actor_username, :to_direction]
    defstruct [:room_id, :actor_id, :actor_username, :to_direction, carried_object_ids: []]
  end

  defmodule RoomNPCLeft do
    @moduledoc """
    Transient NPC-departure event (feature 011). Mirror of `RoomNPCArrived`
    from feature 007. Broadcast on `room:<source>` when an NPC clone is
    despawned or removed.

    Consumed by `AgenticRealms.World.Ticks.Scheduler` to drop the NPC's
    tick behaviors from its in-scope set. Production emission path is
    forward-compatible: the event is defined here; production emission
    lands whenever NPC despawn ships as a feature.
    """
    @enforce_keys [:room_id, :npc_id, :npc_name]
    defstruct [:room_id, :npc_id, :npc_name]
  end

  defmodule WizardBlueprintRegistryChanged do
    @moduledoc """
    Feature 014 US6 — broadcast on the global `blueprints` topic when an
    `ObjectBlueprintCreated` or `ObjectBlueprintEdited` domain event
    fires. Wizard LiveView sessions patch their `:object_blueprints`
    assign in place — insert on `:created`, update-row on `:edited` —
    so every open registry stays live without a manual reload.

    For `:created`, `payload` carries the full row (name +
    short_description). For `:edited`, `payload` carries the sparse
    `fields_changed` diff; subscribers merge into the existing row.
    """
    @enforce_keys [:event, :blueprint_id, :revision, :payload]
    defstruct [:event, :blueprint_id, :revision, :payload]
  end

  defmodule RoomObjectEdited do
    @moduledoc """
    Feature 014 US5 — transient object-edit notice. Broadcast on
    `room:<room_id>` when an `ObjectEdited` event fires. Quiet (no
    narrative log entry by default — wizard edits don't generate an
    in-fiction "the chest was modified" entry). Subscribers refresh
    their room-view caches so a subsequent `look <object>` reflects
    the new values.
    """
    @enforce_keys [:room_id, :object_id, :fields_changed]
    defstruct [:room_id, :object_id, :fields_changed]
  end

  defmodule RoomObjectArrived do
    @moduledoc """
    Feature 014 US2 — transient object-arrival entry. Broadcast on
    `room:<destination>` when an `ObjectSpawned` domain event fires
    while live sessions are present. Mirror of `RoomNPCArrived` from
    feature 007. Co-located players' narrative logs gain a system entry
    `<object short description> appears.`

    No actor exclusion — wizards see the entry too (it's the same
    confirmation that the spawn landed; they don't need a separate
    self-only confirmation given the registry/world view will reflect
    the new object on the next look).
    """
    @enforce_keys [:room_id, :object_id, :name, :short_description]
    defstruct [:room_id, :object_id, :name, :short_description]
  end

  defmodule RoomObjectDeparted do
    @moduledoc """
    Feature 016 — transient object-departure entry. Broadcast on
    `room:<source>` when an object is moved out of a room into another room
    (`:relocated`). NOT emitted for `:taken` (which has `RoomObjectTaken`) or
    for moves into the void. Mirror of the dormant `RoomNPCLeft`.
    """
    @enforce_keys [:room_id, :object_id, :name]
    defstruct [:room_id, :object_id, :name]
  end

  defmodule RoomTranceEntered do
    @moduledoc """
    Feature 014 — transient trance-entry log entry. Broadcast on
    `room:<wizard's current room>` when a wizard flips their
    `authoring_mode` to `:blueprints`. Renders as a `system` narrative-log
    entry on every co-present player's view per FR-002.

    The wizard themselves self-filters (FR-002 wording — "every other
    player session") via their own `handle_info` clause checking
    `wizard_id == current_player.id`.

    Not persisted — there is no domain event behind it. Trance is a UI
    signal, not world state. See
    `specs/014-item-blueprints/research.md` R3.
    """
    @enforce_keys [:room_id, :wizard_id, :wizard_username]
    defstruct [:room_id, :wizard_id, :wizard_username]
  end

  defmodule RoomTranceExited do
    @moduledoc """
    Feature 014 — transient trance-exit log entry. Broadcast on
    `room:<wizard's current room>` when a wizard flips their
    `authoring_mode` back to `:world` (FR-003). Suppressed on disconnect
    per FR-005 by virtue of the LiveView's terminate callback NOT firing
    this event (only an explicit toggle does).
    """
    @enforce_keys [:room_id, :wizard_id, :wizard_username]
    defstruct [:room_id, :wizard_id, :wizard_username]
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

  defmodule ChatUtterance do
    @moduledoc """
    Transient NPC chat reply (feature 010). Broadcast on
    `player:<triggering_player_id>` ONLY — NEVER on `room:<...>` or any
    other player's topic. Distinct from `BehaviorUtterance` (which is
    public) by virtue of being on the private player surface and having
    its own struct + kind atoms.

    `kind` is `:chat_speech` (rendered with quoted attribution like a
    `says`) or `:chat_emote` (rendered as freeform third-person narration
    attributed to the NPC by name).

    See `specs/010-npc-conversations/contracts/ui_events.md`.
    """
    @enforce_keys [:kind, :npc_clone_id, :npc_name, :text, :triggering_player_id]
    defstruct [:kind, :npc_clone_id, :npc_name, :text, :triggering_player_id]
  end

  # ── Feature 013 — Quest UI broadcasts ──────────────────────────────────
  #
  # All three structs are broadcast on `player:<player_id>` ONLY. The
  # `UIEventBroadcaster` emits them in response to QuestAccepted (→
  # PlayerQuestAccepted), inventory changes touching a tagged item (→
  # PlayerQuestProgress), and QuestCompleted (→ PlayerQuestFinalized).
  # See `specs/013-quest-system/contracts/ui-broadcast-events.md`.

  defmodule PlayerQuestAccepted do
    @moduledoc """
    Transient event signaling a quest has just been accepted. Broadcast
    on `player:<player_id>` so `GameLive` can append the quest to the
    visible log without re-querying.

    `criteria` is the per-criterion progress at accept time — every
    `count` is 0 in v1.
    """
    @enforce_keys [:quest_id, :title, :narrative, :criteria]
    defstruct [:quest_id, :title, :narrative, :criteria]
  end

  defmodule PlayerQuestProgress do
    @moduledoc """
    Transient event signaling that progress on an active quest has
    changed. Carries the recomputed per-criterion counts.
    """
    @enforce_keys [:quest_id, :criteria]
    defstruct [:quest_id, :criteria]
  end

  defmodule PlayerQuestFinalized do
    @moduledoc """
    Transient event signaling that a quest has been completed. The UI
    moves the entry out of the active list and into the completed view.
    """
    @enforce_keys [:quest_id, :title, :reward_name, :completed_at]
    defstruct [:quest_id, :title, :reward_name, :completed_at]
  end

  defmodule ChatSystemMessage do
    @moduledoc """
    Transient chat-frame system message (feature 010). Broadcast on
    `player:<player_id>` ONLY. Covers the new-vs-continuing indicator
    (FR-003), the in-flight rejection (FR-020), and the LLM-failure
    fallback line (FR-011).

    `kind`:
      * `:chat_new` — first turn in a fresh conversation
      * `:chat_continuing` — subsequent turn within the 60s window
      * `:chat_in_flight_rejection` — concurrent send while a prior call is in flight
      * `:chat_fallback` — LLM call failed; in-theme fallback line for the player

    See `specs/010-npc-conversations/contracts/ui_events.md`.
    """
    @enforce_keys [:kind, :npc_name, :text, :player_id]
    defstruct [:kind, :npc_name, :text, :player_id]
  end
end
