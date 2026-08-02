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
    * `EntityMoved` (feature 016) → one witness mapping keyed on
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

  # Feature 019 — Real Stats. Progression notices to the earning player only.
  # Two events → one PlayerStatsChanged each (xp gain, then level-up). The
  # payload carries the authoritative deltas so GameLive refreshes the sheet
  # without a DB read (which could race the :strong projector under :eventual).
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

  # Feature 016 — one witness handler for every object relocation. Maps
  # (cause, from→to) to the legacy UI structs so observable behavior is
  # unchanged: wizard spawn announces arrival; seed/quest placement and
  # moves into the void are silent; take/drop keep their room broadcasts plus
  # the inventory + quest-progress side-broadcasts.
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

  # Feature 016 — in-place entity edit; broadcast a quiet RoomObjectEdited to
  # the object's room (if it is in one) so co-located views refresh.
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

  # Feature 018 — an NPC removed from a room departs it, witnessed like any NPC
  # leave. The `from` container is captured on the EntityRemoved event, so no DB
  # read is needed (and the row is being deleted by the projector anyway). Only a
  # removal from a room is visible; removal from the void is silent.
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

  # Feature 015 — live-updating unified Blueprint registry. Broadcast on the
  # global `blueprints` topic so every wizard LiveView session with the
  # registry open patches in place. Both branches read every field they need
  # directly off the domain event — NO DB re-read — because the broadcaster's
  # GenServer doesn't share the calling process's Ecto sandbox connection in
  # tests, and a fresh DB read under :eventual consistency can race the
  # projector anyway. `kind` in the payload drives the registry's kind badge +
  # spawn affordance.
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

  # Feature 016 — NPC arrival is now witnessed via the unified EntityMoved
  # handler (kind :npc, cause :spawned, void → room → RoomNPCArrived); see
  # witness_object_move/5 below.

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

  # Feature 013 — quest finalization inventory deltas. The QuestProjector
  # mutates the read model (deletes consumed objects; clones + moves the
  # reward into inventory), but neither delta surfaces a
  # PlayerInventoryChanged the way take/drop do: consumed items are deleted
  # outright (no EntityMoved), and the reward moves in with cause :spawned,
  # which the EntityMoved witness treats as silent. Without these broadcasts
  # the inventory side panel only catches up on the next manual `inv`. We
  # broadcast straight from the event payloads (no DB reread, like every
  # other witness here) so the GameLive subscriber mutates :inventory in
  # place. :removed only needs the object id; :added carries the reward's
  # name/description from the event, so it's correct even before the async
  # clone is projected into world_objects.
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
  # --- Feature 016 entity-move witness mapping ---------------------------

  # Wizard spawn → arrival announced in the destination room.
  defp witness_object_move(:object, :spawned, _from, %ContainerRef{type: :room, id: rid}, oid) do
    {name, short} = lookup_object(oid)

    Phoenix.PubSub.broadcast(@pubsub, Topics.room_topic(rid), %RoomObjectArrived{
      room_id: rid,
      object_id: oid,
      name: name,
      short_description: short
    })
  end

  # take: room → player inventory.
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

  # drop: player inventory → room.
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

  # Object relocation room → room: departure in the source, arrival in the
  # destination (feature 016, US3). No prior convention existed for this case.
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

  # NPC spawn → arrival announced in the destination room (feature 016).
  defp witness_object_move(:npc, :spawned, _from, %ContainerRef{type: :room, id: rid}, npc_id) do
    Phoenix.PubSub.broadcast(@pubsub, Topics.room_topic(rid), %RoomNPCArrived{
      room_id: rid,
      npc_id: npc_id,
      npc_name: lookup_npc_name(npc_id)
    })
  end

  # Feature 018 — NPC room→room relocation (e.g. an external mind's move) is
  # witnessed exactly like any NPC move: departure in the origin room, arrival in
  # the destination room. The clone row still exists (a move only changes its
  # room), so the name is looked up.
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

  # Seed/quest placement (:placed), moves into the void, NPC-inventory, and
  # any not-yet-wired relocation are silent — no existing witness convention.
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

  # Feature 021 — what a player is called in the world is their character's
  # name. The fallback survives for a state that no longer arises: a player
  # without a character is never spawned, so they are never the actor here.
  defp lookup_name(player_id) do
    PlayerNames.get(player_id) || "unknown player"
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

    from(o in Object,
      where: o.container_type == "player" and o.container_id == ^Integer.to_string(player_id),
      select: o.id
    )
    |> Repo.all()
  end
end
