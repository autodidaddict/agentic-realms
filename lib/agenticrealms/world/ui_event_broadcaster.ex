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

  # `:eventual` (issue #9). The earlier `:strong` declaration was added
  # to fix a test race — `Phoenix.LiveViewTest.render/1` could fire
  # before the broadcast reached the subscriber's inbox — but at the
  # cost of serializing every `move` / `take` / `drop` / `spawn`
  # dispatch on this single handler. On a distributed PubSub backend
  # that means every dispatch waits for fan-out to every subscriber in
  # the broadcasting node's process, which is the wrong place to pay
  # that cost. Witness handlers mutate from the broadcast payload only
  # (no DB reread), so runtime correctness doesn't need synchronous
  # broadcast. Tests poll with `assert_eventually/3` (in
  # `AgenticRealmsWeb.ConnCase`) when they need the witness render to
  # reflect the broadcast.
  use Commanded.Event.Handler,
    application: AgenticRealms.World.Application,
    name: __MODULE__,
    consistency: :eventual

  alias AgenticRealms.Accounts
  alias AgenticRealms.Repo
  alias AgenticRealms.World.Direction
  alias AgenticRealms.World.Quests

  alias AgenticRealms.World.Events.{
    PlayerSpawned,
    PlayerMoved,
    ObjectTakenFromRoom,
    ObjectDroppedInRoom,
    NPCSpawnedInRoom,
    NPCClonedFromBlueprint,
    QuestAccepted,
    QuestCompleted
  }

  alias AgenticRealms.World.Schemas.Object

  alias AgenticRealms.World.UIEvents.{
    RoomPlayerArrived,
    RoomPlayerLeft,
    RoomObjectTaken,
    RoomObjectDropped,
    RoomNPCArrived,
    PlayerCurrentRoomChanged,
    PlayerInventoryChanged,
    PlayerQuestAccepted,
    PlayerQuestProgress,
    PlayerQuestFinalized
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

    # Feature 013 — if the taken object's quest_tag matches any of the
    # player's active quest criteria, recompute progress and broadcast
    # PlayerQuestProgress so the HUD card updates live.
    broadcast_quest_progress(pid, oid)

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

    # Feature 013 — symmetric to take: dropping a tagged quest item
    # decrements the player's progress.
    broadcast_quest_progress(pid, oid)

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

  # Feature 013 — Quests. Broadcast PlayerQuestAccepted on the player's
  # topic so GameLive can append the new active quest to its log without
  # re-querying. Criteria counts are all 0 at accept time (FR-019; no
  # lifetime pickup tracking, and any pre-existing matching inventory
  # only reflects in subsequent PlayerQuestProgress events fired by US2).
  def handle(
        %QuestAccepted{
          quest_id: qid,
          player_id: pid,
          definition_snapshot: snapshot
        },
        _meta
      ) do
    title = snapshot_get(snapshot, "title")
    narrative = snapshot_get(snapshot, "narrative")

    criteria =
      snapshot
      |> snapshot_list("criteria")
      |> Enum.map(fn c ->
        %{
          name: snapshot_get(c, "name"),
          count: 0,
          target: snapshot_get(c, "target_count") || 0
        }
      end)

    Phoenix.PubSub.broadcast(
      @pubsub,
      Topics.player_topic(pid),
      %PlayerQuestAccepted{
        quest_id: qid,
        title: title,
        narrative: narrative,
        criteria: criteria
      }
    )

    :ok
  end

  # Feature 013 — broadcast PlayerQuestFinalized when a Quest aggregate
  # reaches the :completed state. The QuestProjector flips the row's
  # state in its own transaction; this handler reads back the row to
  # pull the title + reward name for the broadcast payload.
  def handle(%QuestCompleted{quest_id: qid, player_id: pid, completed_at: at}, _meta) do
    case Quests.quest_instance(qid) do
      nil ->
        :ok

      inst ->
        title = inst.definition_snapshot["title"]
        reward_name = (inst.definition_snapshot["reward"] || %{})["name"]

        Phoenix.PubSub.broadcast(
          @pubsub,
          Topics.player_topic(pid),
          %PlayerQuestFinalized{
            quest_id: qid,
            title: title,
            reward_name: reward_name,
            completed_at: at
          }
        )

        :ok
    end
  end

  # Feature 013 — recompute progress for each of the player's active
  # quests whose criteria reference the touched object's quest_tag, and
  # broadcast PlayerQuestProgress per quest. Untouched quests trigger no
  # broadcasts. Items without a quest_tag short-circuit to a no-op.
  defp broadcast_quest_progress(player_id, object_id) do
    for quest <- Quests.active_quests_referencing_object(player_id, object_id) do
      criteria = Quests.progress_for(quest)

      Phoenix.PubSub.broadcast(
        @pubsub,
        Topics.player_topic(player_id),
        %PlayerQuestProgress{quest_id: quest.id, criteria: criteria}
      )
    end

    :ok
  end

  defp snapshot_get(map, key) when is_map(map) and is_binary(key) do
    case Map.get(map, key) do
      nil ->
        try do
          Map.get(map, String.to_existing_atom(key))
        rescue
          ArgumentError -> nil
        end

      v ->
        v
    end
  end

  defp snapshot_get(_, _), do: nil

  defp snapshot_list(map, key) do
    case snapshot_get(map, key) do
      list when is_list(list) -> list
      _ -> []
    end
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
