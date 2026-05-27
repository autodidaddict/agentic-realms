defmodule AgenticRealms.World.UIEventBroadcaster do
  @moduledoc """
  Single Commanded event handler that translates persisted domain events into
  transient UI events broadcast on `Phoenix.PubSub` topics.

  Subscribed-to topics:
    * `"room:<room_uuid>"` — RoomObjectTaken / RoomObjectDropped /
      RoomPlayerArrived / RoomPlayerLeft
    * `"player:<player_id>"` — PlayerCurrentRoomChanged /
      PlayerInventoryChanged

  Subscribers (`GameLive.handle_info/2`) are responsible for actor-exclusion
  per FR-029 — the broadcaster fans out to all subscribers in the relevant
  room or player scope.

  Handler clauses added so far:
    * Phase 4 (US1): PlayerSpawned → RoomPlayerArrived(from_direction: nil)
                                     + PlayerCurrentRoomChanged(from: nil)
    * Phase 5 (US2): PlayerMoved   → RoomPlayerLeft + RoomPlayerArrived
                                     + PlayerCurrentRoomChanged
    * Phase 6 (US3): ObjectTakenFromRoom → RoomObjectTaken
                                           + PlayerInventoryChanged(:added)
                     ObjectDroppedInRoom → RoomObjectDropped
                                           + PlayerInventoryChanged(:removed)
  """

  # `:strong` so dispatches with `consistency: :strong` (move, take, drop)
  # block until the broadcast has been published. Without this, witness
  # GameLives can race the publish: the test (or a fast user) sees a
  # stale render between the projector commit and the PubSub fan-out.
  use Commanded.Event.Handler,
    application: AgenticRealms.World.Application,
    name: __MODULE__,
    consistency: :strong

  alias AgenticRealms.Accounts
  alias AgenticRealms.Repo
  alias AgenticRealms.World.Direction

  alias AgenticRealms.World.Events.{
    PlayerSpawned,
    PlayerMoved,
    ObjectTakenFromRoom,
    ObjectDroppedInRoom,
    NPCSpawnedInRoom,
    NPCClonedFromBlueprint
  }

  alias AgenticRealms.World.Schemas.Object

  alias AgenticRealms.World.UIEvents.{
    RoomPlayerArrived,
    RoomPlayerLeft,
    RoomObjectTaken,
    RoomObjectDropped,
    RoomNPCArrived,
    PlayerCurrentRoomChanged,
    PlayerInventoryChanged
  }

  alias AgenticRealmsWeb.Topics

  @pubsub AgenticRealms.PubSub

  def handle(%PlayerSpawned{player_id: pid, room_id: room_id}, _meta) do
    actor_username = lookup_username(pid)
    carried_ids = lookup_carried_object_ids(pid)

    Phoenix.PubSub.broadcast(@pubsub, Topics.room_topic(room_id), %RoomPlayerArrived{
      room_id: room_id,
      actor_id: pid,
      actor_username: actor_username,
      from_direction: nil,
      carried_object_ids: carried_ids
    })

    Phoenix.PubSub.broadcast(
      @pubsub,
      Topics.player_topic(pid),
      %PlayerCurrentRoomChanged{
        player_id: pid,
        from_room_id: nil,
        to_room_id: room_id
      }
    )

    :ok
  end

  def handle(
        %PlayerMoved{
          player_id: pid,
          from_room_id: from,
          to_room_id: to,
          direction: direction
        },
        _meta
      ) do
    actor_username = lookup_username(pid)
    {:ok, direction_atom} = Direction.parse(direction)
    carried_ids = lookup_carried_object_ids(pid)

    from_topic = Topics.room_topic(from)

    Phoenix.PubSub.broadcast(@pubsub, from_topic, %RoomPlayerLeft{
      room_id: from,
      actor_id: pid,
      actor_username: actor_username,
      to_direction: direction_atom,
      carried_object_ids: carried_ids
    })

    Phoenix.PubSub.broadcast(@pubsub, Topics.room_topic(to), %RoomPlayerArrived{
      room_id: to,
      actor_id: pid,
      actor_username: actor_username,
      from_direction: Direction.opposite(direction_atom),
      carried_object_ids: carried_ids
    })

    Phoenix.PubSub.broadcast(
      @pubsub,
      Topics.player_topic(pid),
      %PlayerCurrentRoomChanged{
        player_id: pid,
        from_room_id: from,
        to_room_id: to
      }
    )

    :ok
  end

  def handle(%ObjectTakenFromRoom{room_id: rid, player_id: pid, object_id: oid}, _meta) do
    actor_username = lookup_username(pid)
    {name, short} = lookup_object(oid)

    Phoenix.PubSub.broadcast(@pubsub, Topics.room_topic(rid), %RoomObjectTaken{
      room_id: rid,
      actor_id: pid,
      actor_username: actor_username,
      object_id: oid,
      object_name: name
    })

    Phoenix.PubSub.broadcast(
      @pubsub,
      Topics.player_topic(pid),
      %PlayerInventoryChanged{
        player_id: pid,
        change: :added,
        object_id: oid,
        object_name: name,
        object_short_description: short
      }
    )

    :ok
  end

  def handle(%ObjectDroppedInRoom{room_id: rid, player_id: pid, object_id: oid}, _meta) do
    actor_username = lookup_username(pid)
    {name, short} = lookup_object(oid)

    Phoenix.PubSub.broadcast(@pubsub, Topics.room_topic(rid), %RoomObjectDropped{
      room_id: rid,
      actor_id: pid,
      actor_username: actor_username,
      object_id: oid,
      object_name: name
    })

    Phoenix.PubSub.broadcast(
      @pubsub,
      Topics.player_topic(pid),
      %PlayerInventoryChanged{
        player_id: pid,
        change: :removed,
        object_id: oid,
        object_name: name,
        object_short_description: short
      }
    )

    :ok
  end

  def handle(%NPCSpawnedInRoom{room_id: rid, npc_id: nid, name: name}, _meta) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      Topics.room_topic(rid),
      %RoomNPCArrived{room_id: rid, npc_id: nid, npc_name: name}
    )

    :ok
  end

  # Feature 008: new event type emitted by the NPCBlueprint aggregate. Same
  # downstream UI event as the legacy NPCSpawnedInRoom path so GameLive's
  # handler is one clause covering both.
  def handle(
        %NPCClonedFromBlueprint{room_id: rid, clone_id: cid, name: name},
        _meta
      ) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      Topics.room_topic(rid),
      %RoomNPCArrived{room_id: rid, npc_id: cid, npc_name: name}
    )

    :ok
  end

  defp lookup_username(player_id) do
    case Accounts.get_player(player_id) do
      nil -> "unknown player"
      %{username: u} -> u
    end
  end

  defp lookup_object(object_id) do
    case Repo.get(Object, object_id) do
      nil -> {"something", ""}
      %{name: name, short_description: short} -> {name, short}
    end
  end

  # Feature 011 — population helper for the new `carried_object_ids` field
  # on RoomPlayerArrived / RoomPlayerLeft. Returns the ids of every object
  # currently in the player's inventory. Bounded by inventory size.
  defp lookup_carried_object_ids(player_id) do
    import Ecto.Query

    from(o in Object, where: o.player_id == ^player_id, select: o.id)
    |> Repo.all()
  end
end
