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

  Handler clauses:
    * `PlayerSpawned` / `PlayerMoved` → RoomPlayerArrived / RoomPlayerLeft
      + PlayerCurrentRoomChanged.
    * `EntityMoved` → one witness mapping keyed on
      `(kind, cause, from→to)` that reproduces every prior convention:
      object spawn → RoomObjectArrived; take → RoomObjectTaken +
      PlayerInventoryChanged(:added); drop → RoomObjectDropped +
      PlayerInventoryChanged(:removed); room→room relocation →
      RoomObjectDeparted + RoomObjectArrived; NPC spawn → RoomNPCArrived;
      seed/quest placement and moves into the void are silent.
    * `EntityEdited` → RoomObjectEdited (quiet).
    * `ObjectBlueprintCreated`/`Edited`, `QuestAccepted`/`Completed` → their
      respective UI broadcasts.
  """

  use Commanded.Event.Handler,
    application: AgenticRealms.World.Application,
    name: __MODULE__,
    consistency: :eventual

  alias AgenticRealms.World.EventData
  alias AgenticRealms.World.PlayerNames
  alias AgenticRealms.Repo
  alias AgenticRealms.World.Direction
  alias AgenticRealms.World.Quests

  alias AgenticRealms.World.Events.{
    PlayerSpawned,
    PlayerMoved,
    PlayerXpAwarded,
    PlayerLeveledUp,
    EntityMoved,
    EntityEdited,
    EntityRemoved,
    BlueprintCreated,
    BlueprintEdited,
    QuestAccepted,
    QuestItemsConsumed,
    QuestRewardMinted,
    QuestCompleted
  }

  alias AgenticRealms.World.ContainerRef
  alias AgenticRealms.World.Schemas.{Object, NPCClone}

  alias AgenticRealms.World.UIEvents.{
    RoomPlayerArrived,
    RoomPlayerLeft,
    RoomObjectTaken,
    RoomObjectDropped,
    RoomObjectArrived,
    RoomObjectDeparted,
    RoomObjectEdited,
    RoomNPCArrived,
    RoomNPCLeft,
    WizardBlueprintRegistryChanged,
    PlayerCurrentRoomChanged,
    PlayerInventoryChanged,
    PlayerQuestAccepted,
    PlayerQuestProgress,
    PlayerQuestFinalized,
    PlayerStatsChanged
  }

  alias AgenticRealmsWeb.Topics

  @pubsub AgenticRealms.PubSub

  def handle(%PlayerSpawned{player_id: pid, room_id: room_id}, _meta) do
    actor_name = lookup_name(pid)
    carried_ids = lookup_carried_object_ids(pid)

    Phoenix.PubSub.broadcast(@pubsub, Topics.room_topic(room_id), %RoomPlayerArrived{
      room_id: room_id,
      actor_id: pid,
      actor_name: actor_name,
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
    actor_name = lookup_name(pid)
    {:ok, direction_atom} = Direction.parse(direction)
    carried_ids = lookup_carried_object_ids(pid)

    from_topic = Topics.room_topic(from)

    Phoenix.PubSub.broadcast(@pubsub, from_topic, %RoomPlayerLeft{
      room_id: from,
      actor_id: pid,
      actor_name: actor_name,
      to_direction: direction_atom,
      carried_object_ids: carried_ids
    })

    Phoenix.PubSub.broadcast(@pubsub, Topics.room_topic(to), %RoomPlayerArrived{
      room_id: to,
      actor_id: pid,
      actor_name: actor_name,
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

  def handle(%PlayerXpAwarded{player_id: pid, amount: amount, new_total: new_total}, _meta) do
    Phoenix.PubSub.broadcast(@pubsub, Topics.player_topic(pid), %PlayerStatsChanged{
      player_id: pid,
      xp_gained: amount,
      new_total: new_total,
      leveled_to: nil
    })

    :ok
  end

  def handle(%PlayerLeveledUp{player_id: pid, to_level: to_level}, _meta) do
    Phoenix.PubSub.broadcast(@pubsub, Topics.player_topic(pid), %PlayerStatsChanged{
      player_id: pid,
      xp_gained: nil,
      new_total: nil,
      leveled_to: to_level
    })

    :ok
  end

  def handle(%EntityMoved{kind: kind, entity_id: oid, from: from, to: to, cause: cause}, _meta) do
    witness_object_move(
      norm_kind(kind),
      cause_atom(cause),
      ContainerRef.from_map(from),
      ContainerRef.from_map(to),
      oid
    )

    :ok
  end

  def handle(%EntityEdited{kind: kind, entity_id: oid, fields_changed: fields_changed}, _meta) do
    with :object <- norm_kind(kind),
         %Object{container_type: "room", container_id: rid} <- Repo.get(Object, oid) do
      Phoenix.PubSub.broadcast(
        @pubsub,
        Topics.room_topic(rid),
        %RoomObjectEdited{room_id: rid, object_id: oid, fields_changed: fields_changed}
      )
    end

    :ok
  end

  def handle(%EntityRemoved{kind: kind, entity_id: id, from: from, name: name}, _meta) do
    with :npc <- norm_kind(kind),
         %ContainerRef{type: :room, id: rid} <- ContainerRef.from_map(from || ContainerRef.void()) do
      Phoenix.PubSub.broadcast(@pubsub, Topics.room_topic(rid), %RoomNPCLeft{
        room_id: rid,
        npc_id: id,
        npc_name: name || "someone"
      })
    end

    :ok
  end

  def handle(%BlueprintCreated{} = e, _meta) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      Topics.blueprints_topic(),
      %WizardBlueprintRegistryChanged{
        event: :created,
        blueprint_id: e.blueprint_id,
        revision: Map.get(e, :revision, 1),
        payload: %{
          name: e.name,
          short_description: e.short_description,
          fixed: Map.get(e, :fixed, false),
          kind: Map.get(e, :kind) || "npc"
        }
      }
    )

    :ok
  end

  def handle(
        %BlueprintEdited{
          blueprint_id: bp_id,
          fields_changed: fields_changed,
          revision: revision
        },
        _meta
      ) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      Topics.blueprints_topic(),
      %WizardBlueprintRegistryChanged{
        event: :edited,
        blueprint_id: bp_id,
        revision: revision,
        payload: fields_changed
      }
    )

    :ok
  end

  def handle(
        %QuestAccepted{
          quest_id: qid,
          player_id: pid,
          definition_snapshot: snapshot
        },
        _meta
      ) do
    title = EventData.get(snapshot, "title")
    narrative = EventData.get(snapshot, "narrative")

    criteria =
      snapshot
      |> EventData.list("criteria")
      |> Enum.map(fn c ->
        %{
          name: EventData.get(c, "name"),
          count: 0,
          target: EventData.get(c, "target_count") || 0
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

  def handle(%QuestItemsConsumed{player_id: pid, consumed_object_ids: ids}, _meta)
      when is_list(ids) do
    for oid <- ids do
      Phoenix.PubSub.broadcast(@pubsub, Topics.player_topic(pid), %PlayerInventoryChanged{
        player_id: pid,
        change: :removed,
        object_id: oid,
        object_name: nil,
        object_short_description: nil
      })
    end

    :ok
  end

  def handle(
        %QuestRewardMinted{
          player_id: pid,
          reward_object_id: oid,
          reward_name: name,
          reward_description: description
        },
        _meta
      ) do
    Phoenix.PubSub.broadcast(@pubsub, Topics.player_topic(pid), %PlayerInventoryChanged{
      player_id: pid,
      change: :added,
      object_id: oid,
      object_name: name,
      object_short_description: description
    })

    :ok
  end

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

  defp witness_object_move(:object, :spawned, _from, %ContainerRef{type: :room, id: rid}, oid) do
    {name, short} = lookup_object(oid)

    Phoenix.PubSub.broadcast(@pubsub, Topics.room_topic(rid), %RoomObjectArrived{
      room_id: rid,
      object_id: oid,
      name: name,
      short_description: short
    })
  end

  defp witness_object_move(
         :object,
         :taken,
         %ContainerRef{type: :room, id: rid},
         %ContainerRef{type: :player, id: pid},
         oid
       ) do
    actor_name = lookup_name(pid)
    {name, short} = lookup_object(oid)

    Phoenix.PubSub.broadcast(@pubsub, Topics.room_topic(rid), %RoomObjectTaken{
      room_id: rid,
      actor_id: pid,
      actor_name: actor_name,
      object_id: oid,
      object_name: name
    })

    Phoenix.PubSub.broadcast(@pubsub, Topics.player_topic(pid), %PlayerInventoryChanged{
      player_id: pid,
      change: :added,
      object_id: oid,
      object_name: name,
      object_short_description: short
    })

    broadcast_quest_progress(pid, oid)
  end

  defp witness_object_move(
         :object,
         :dropped,
         %ContainerRef{type: :player, id: pid},
         %ContainerRef{type: :room, id: rid},
         oid
       ) do
    actor_name = lookup_name(pid)
    {name, short} = lookup_object(oid)

    Phoenix.PubSub.broadcast(@pubsub, Topics.room_topic(rid), %RoomObjectDropped{
      room_id: rid,
      actor_id: pid,
      actor_name: actor_name,
      object_id: oid,
      object_name: name
    })

    Phoenix.PubSub.broadcast(@pubsub, Topics.player_topic(pid), %PlayerInventoryChanged{
      player_id: pid,
      change: :removed,
      object_id: oid,
      object_name: name,
      object_short_description: short
    })

    broadcast_quest_progress(pid, oid)
  end

  defp witness_object_move(
         :object,
         :relocated,
         %ContainerRef{type: :room, id: from_rid},
         %ContainerRef{type: :room, id: to_rid},
         oid
       ) do
    {name, short} = lookup_object(oid)

    Phoenix.PubSub.broadcast(@pubsub, Topics.room_topic(from_rid), %RoomObjectDeparted{
      room_id: from_rid,
      object_id: oid,
      name: name
    })

    Phoenix.PubSub.broadcast(@pubsub, Topics.room_topic(to_rid), %RoomObjectArrived{
      room_id: to_rid,
      object_id: oid,
      name: name,
      short_description: short
    })
  end

  defp witness_object_move(:npc, :spawned, _from, %ContainerRef{type: :room, id: rid}, npc_id) do
    Phoenix.PubSub.broadcast(@pubsub, Topics.room_topic(rid), %RoomNPCArrived{
      room_id: rid,
      npc_id: npc_id,
      npc_name: lookup_npc_name(npc_id)
    })
  end

  defp witness_object_move(
         :npc,
         :relocated,
         %ContainerRef{type: :room, id: from_rid},
         %ContainerRef{type: :room, id: to_rid},
         npc_id
       ) do
    name = lookup_npc_name(npc_id)

    Phoenix.PubSub.broadcast(@pubsub, Topics.room_topic(from_rid), %RoomNPCLeft{
      room_id: from_rid,
      npc_id: npc_id,
      npc_name: name
    })

    Phoenix.PubSub.broadcast(@pubsub, Topics.room_topic(to_rid), %RoomNPCArrived{
      room_id: to_rid,
      npc_id: npc_id,
      npc_name: name
    })
  end

  defp witness_object_move(_kind, _cause, _from, _to, _oid), do: :ok

  defp lookup_npc_name(npc_id) do
    case Repo.get(NPCClone, npc_id) do
      %NPCClone{name: name} -> name
      _ -> "someone"
    end
  end

  defp norm_kind(k) when k in [:object, :npc], do: k
  defp norm_kind("object"), do: :object
  defp norm_kind("npc"), do: :npc
  defp norm_kind(_), do: nil

  defp cause_atom(c) when is_atom(c), do: c
  defp cause_atom(c) when is_binary(c), do: String.to_existing_atom(c)

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

  defp lookup_name(player_id) do
    PlayerNames.get(player_id) || "unknown player"
  end

  defp lookup_object(object_id) do
    case Repo.get(Object, object_id) do
      nil -> {"something", ""}
      %{name: name, short_description: short} -> {name, short}
    end
  end

  defp lookup_carried_object_ids(player_id) do
    import Ecto.Query

    from(o in Object,
      where: o.container_type == "player" and o.container_id == ^Integer.to_string(player_id),
      select: o.id
    )
    |> Repo.all()
  end
end
