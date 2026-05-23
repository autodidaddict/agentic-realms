# Contract: `RoomNPCArrived` UI Event + `GameLive` Handler

## UI event struct

`AgenticRealms.World.UIEvents.RoomNPCArrived`

```elixir
defmodule AgenticRealms.World.UIEvents.RoomNPCArrived do
  @enforce_keys [:room_id, :npc_id, :npc_name]
  defstruct [:room_id, :npc_id, :npc_name]
end
```

| Field      | Type        | Notes                                                              |
|------------|-------------|--------------------------------------------------------------------|
| `room_id`  | `binary_id` | Destination room — recipients filter by their current room.        |
| `npc_id`   | `binary_id` | Stable identity of the spawned NPC.                                |
| `npc_name` | `string`    | Display name. Used directly in the `<name> arrives.` log entry.    |

Transient PubSub message. Never persisted. Lives only on the `room:<room_uuid>` topic.

## Producer: `UIEventBroadcaster`

New `handle/2` clause in `lib/agenticrealms/world/ui_event_broadcaster.ex`:

```elixir
def handle(%NPCSpawnedInRoom{room_id: rid, npc_id: nid, name: name}, _meta) do
  Phoenix.PubSub.broadcast(
    @pubsub,
    AgenticRealms.World.room_topic(rid),
    %RoomNPCArrived{room_id: rid, npc_id: nid, npc_name: name}
  )

  :ok
end
```

The `NPCSpawnedInRoom` alias is added to the existing `alias AgenticRealms.World.Events.{...}` block. The `RoomNPCArrived` alias is added to the existing `alias AgenticRealms.World.UIEvents.{...}` block.

**No player-topic broadcast**: NPCs are not players, so there is no `PlayerCurrentRoomChanged` companion event (that one is player-specific). The only broadcast is to the room topic.

## Subscriber: `GameLive`

New `handle_info/2` clause in `lib/agenticrealms_web/live/game_live.ex`. Inserted alongside the existing `RoomPlayerArrived` / `RoomPlayerLeft` / `RoomObjectTaken` clauses (around line 720–770):

```elixir
def handle_info(%RoomNPCArrived{room_id: rid, npc_name: name}, socket) do
  current = socket.assigns.current_player.id
  player_room = Queries.current_room_of(current)

  case player_room do
    {:ok, ^rid} ->
      # Player is in the destination room — append the arrival log entry
      # AND refresh the room view so the new NPC appears in the
      # "Also here" section on subsequent renders.
      {:noreply,
       socket
       |> append_log(%{kind: :system, text: "#{name} arrives."})
       |> refresh_room()}

    _ ->
      # Player is not in this room (or has no current room) — the broadcast
      # fan-out reached us by way of the room topic, but we no longer
      # belong on it. Ignore. (Unsubscribe is handled elsewhere by the
      # PlayerCurrentRoomChanged handler.)
      {:noreply, socket}
  end
end
```

The `RoomNPCArrived` alias is added to the existing `alias AgenticRealms.World.UIEvents.{...}` block in `GameLive`.

The `refresh_room/1` helper already exists (or is trivially added if not) — it re-queries `Queries.look_room/1` and updates `socket.assigns.room`. If the existing code uses a different name (`reload_room/1`, `update_room_assigns/1`, etc.) the implementation should call whatever the existing convention is — the test surface verifies behavior, not the helper name.

## Acceptance: actor exclusion (FR-029 inheritance)

NPCs have no "actor" in the player-action sense — spawning is a world event with no acting player. Therefore the existing actor-exclusion pattern (`if actor_id == socket.assigns.current_player.id`) does NOT apply. Every subscribed session — including any session of any player in the destination room — receives the `<name> arrives.` entry.

This matches FR-014: every concurrent session of every player in the destination room receives the entry.

## Acceptance: multi-session delivery (FR-014)

Inherited from `Phoenix.PubSub.broadcast/3` semantics: the broadcast fan-out delivers to every subscriber of the room topic. Each `GameLive` process subscribes on mount and is the basic unit of delivery; multiple tabs for the same player produce multiple `GameLive` processes, each receiving the message independently and appending its own copy of the entry.

## Acceptance: zero broadcast when no live sessions (FR-013)

`Phoenix.PubSub.broadcast/3` is a no-op when no subscribers exist on the topic. The aggregate's event is still persisted and the projector still inserts the `world_npcs` row, so any later-joining `GameLive` will see the NPC via `look_room/1` (Story 1). No replay of missed arrival entries.
