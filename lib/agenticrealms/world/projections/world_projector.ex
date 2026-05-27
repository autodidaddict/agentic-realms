defmodule AgenticRealms.World.Projections.WorldProjector do
  @moduledoc """
  Projects every room / exit / object / NPC domain event into the
  `world_rooms`, `world_exits`, `world_objects`, `npc_blueprints`, and
  `npc_clones` Ecto-backed read models.

  Event handler clauses added so far:
    * Phase 3 (US5): RoomCreated, ExitAdded, ObjectPlacedInRoom
    * Phase 6 (US3): ObjectTakenFromRoom, ObjectDroppedInRoom
    * Feature 007: NPCSpawnedInRoom (REWRITTEN in 008 — see below)
    * Feature 008: NPCBlueprintCreated, NPCClonedFromBlueprint

  Every insert uses `on_conflict: :nothing` so the projector is safe to
  replay against a partially-populated read model.

  **Feature 008 — legacy NPCSpawnedInRoom handling**: the feature 007 event
  type is preserved in the event store; this projector handles it by
  deriving a deterministic synthetic blueprint id, upserting a blueprint
  row with `is_synthetic: true`, then inserting the clone with a serial
  computed via a MAX query against the existing clones for that blueprint.
  See `specs/008-npc-blueprints/contracts/projector.md`.
  """

  use Commanded.Event.Handler,
    application: AgenticRealms.World.Application,
    name: __MODULE__,
    consistency: :strong

  import Ecto.Query

  alias AgenticRealms.Repo
  alias AgenticRealms.World.Direction
  alias AgenticRealms.World.Projections.SyntheticBlueprintId

  alias AgenticRealms.World.Events.{
    RoomCreated,
    ExitAdded,
    ObjectPlacedInRoom,
    ObjectTakenFromRoom,
    ObjectDroppedInRoom,
    NPCSpawnedInRoom,
    NPCBlueprintCreated,
    NPCClonedFromBlueprint,
    RegionCreated,
    QuestAccepted
  }

  alias AgenticRealms.World.Events.PlayerDiscoveredRoom, as: PlayerDiscoveredRoomEvent
  alias AgenticRealms.World.Application, as: WorldApp
  alias AgenticRealms.World.Commands.PlaceObject

  alias AgenticRealms.World.Schemas.{
    Room,
    Exit,
    Object,
    NPCBlueprint,
    NPCClone,
    Region,
    QuestInstance
  }

  alias AgenticRealms.World.Schemas.PlayerDiscoveredRoom, as: PlayerDiscoveredRoomRow

  # Feature 012: regions are first-class. RegionCreated lands here before
  # any RoomCreated event that references the region (Commanded ordering
  # within an aggregate; cross-aggregate ordering preserved via the
  # consistency: :strong dispatch in Commands.create_region/2).
  def handle(%RegionCreated{region_id: id, name: name}, _meta) do
    Repo.insert!(
      %Region{id: id, name: name},
      on_conflict: :nothing,
      conflict_target: :id
    )

    :ok
  end

  def handle(
        %RoomCreated{
          room_id: id,
          name: name,
          description: description,
          behaviors: behaviors
        } = event,
        _meta
      ) do
    # Feature 012: RoomCreated now carries region_id + map fields. Older
    # events (pre-feature-012, replayed from the event store) lack these
    # keys — pattern-match defensively via Map.get so historical replay
    # still projects correctly.
    Repo.insert!(
      %Room{
        id: id,
        name: name,
        description: description,
        behaviors: behaviors,
        region_id: Map.get(event, :region_id),
        map_visible: Map.get(event, :map_visible, true),
        elevation: Map.get(event, :elevation, 0),
        map_x: Map.get(event, :map_x),
        map_y: Map.get(event, :map_y)
      },
      on_conflict: :nothing,
      conflict_target: :id
    )

    :ok
  end

  def handle(
        %ExitAdded{room_id: source, direction: direction, target_room_id: target},
        _meta
      ) do
    Repo.insert!(
      %Exit{
        source_room_id: source,
        direction: Direction.to_string(direction),
        target_room_id: target
      },
      on_conflict: :nothing,
      conflict_target: [:source_room_id, :direction]
    )

    :ok
  end

  def handle(
        %ObjectPlacedInRoom{
          room_id: room_id,
          object_id: oid,
          name: name,
          short_description: short,
          long_description: long,
          fixed: fixed,
          behaviors: behaviors
        } = event,
        _meta
      ) do
    Repo.insert!(
      %Object{
        id: oid,
        name: name,
        short_description: short,
        long_description: long,
        fixed: fixed,
        room_id: room_id,
        player_id: nil,
        behaviors: behaviors || [],
        # Feature 013 — both nil for non-quest placements and for legacy
        # events that pre-date this feature. Map.get/3 with default nil
        # makes replay safe.
        quest_player_id: Map.get(event, :quest_player_id),
        quest_instance_id: Map.get(event, :quest_instance_id)
      },
      on_conflict: :nothing,
      conflict_target: :id
    )

    :ok
  end

  def handle(%ObjectTakenFromRoom{player_id: pid, object_id: oid}, _meta) do
    {1, _} =
      Repo.update_all(
        from(o in Object, where: o.id == ^oid),
        set: [room_id: nil, player_id: pid, updated_at: utc_now()]
      )

    :ok
  end

  def handle(%ObjectDroppedInRoom{room_id: rid, object_id: oid}, _meta) do
    {1, _} =
      Repo.update_all(
        from(o in Object, where: o.id == ^oid),
        set: [room_id: rid, player_id: nil, updated_at: utc_now()]
      )

    :ok
  end

  # Feature 008: authored blueprints (from CreateNPCBlueprint command).
  # Feature 009: extended with :behaviors field (defaults to [] for pre-009
  # events via the event struct's default).
  def handle(
        %NPCBlueprintCreated{
          blueprint_id: bp_id,
          name: name,
          short_description: short,
          long_description: long,
          behaviors: behaviors,
          lore: lore
        } = event,
        _meta
      ) do
    Repo.insert!(
      %NPCBlueprint{
        id: bp_id,
        name: name,
        short_description: short,
        long_description: long,
        is_synthetic: false,
        behaviors: behaviors,
        lore: lore || "",
        # Feature 013 — legacy events without :quests default to [].
        quests: Map.get(event, :quests, []) || []
      },
      on_conflict: :nothing,
      conflict_target: :id
    )

    :ok
  end

  # Feature 008: clone insertion from the event's denormalized payload.
  # The blueprint table is NOT consulted here — the event already contains
  # the full-copy snapshot of the blueprint's data as of clone time.
  def handle(
        %NPCClonedFromBlueprint{
          blueprint_id: bp_id,
          clone_id: cid,
          room_id: rid,
          serial: serial,
          name: name,
          short_description: short,
          long_description: long,
          behaviors: behaviors,
          lore: lore
        },
        _meta
      ) do
    Repo.insert!(
      %NPCClone{
        id: cid,
        blueprint_id: bp_id,
        serial: serial,
        name: name,
        short_description: short,
        long_description: long,
        room_id: rid,
        behaviors: behaviors,
        lore: lore || ""
      },
      on_conflict: :nothing,
      conflict_target: :id
    )

    :ok
  end

  # Feature 008 — legacy event from feature 007. Synthesizes a blueprint
  # id from the payload, upserts it, computes the next serial via MAX,
  # then inserts the clone. Deterministic + idempotent under replay.
  def handle(
        %NPCSpawnedInRoom{
          room_id: rid,
          npc_id: nid,
          name: name,
          short_description: short,
          long_description: long
        },
        _meta
      ) do
    bp_id = SyntheticBlueprintId.derive(name, short, long)

    Repo.insert!(
      %NPCBlueprint{
        id: bp_id,
        name: name,
        short_description: short,
        long_description: long,
        is_synthetic: true
      },
      on_conflict: :nothing,
      conflict_target: :id
    )

    serial = next_serial_for_blueprint(bp_id)

    Repo.insert!(
      %NPCClone{
        id: nid,
        blueprint_id: bp_id,
        serial: serial,
        name: name,
        short_description: short,
        long_description: long,
        room_id: rid
      },
      on_conflict: :nothing,
      conflict_target: :id
    )

    :ok
  end

  # Feature 012 — Maps. Per-player room discovery projection. Inserts with
  # `on_conflict: :nothing` so the composite-PK guarantee is leaned on for
  # idempotency under replay. (The aggregate ALSO short-circuits duplicate
  # emissions, but defense-in-depth is cheap here.)
  def handle(
        %PlayerDiscoveredRoomEvent{
          player_id: pid,
          room_id: rid,
          discovered_at: ts
        },
        _meta
      ) do
    Repo.insert!(
      %PlayerDiscoveredRoomRow{
        player_id: pid,
        room_id: rid,
        discovered_at: ensure_datetime(ts)
      },
      on_conflict: :nothing,
      conflict_target: [:player_id, :room_id]
    )

    :ok
  end

  # Feature 013 — Quests. On QuestAccepted: (1) insert the quest_instances
  # row with state="active", (2) for each criterion, for each spawn_room_id,
  # dispatch a PlaceObject command stamped with quest_player_id +
  # quest_instance_id. The PlaceObject flow lands the item via the normal
  # Room aggregate + ObjectPlacedInRoom event path — the only special
  # thing is the visibility fields it carries.
  def handle(
        %QuestAccepted{
          quest_id: qid,
          player_id: pid,
          npc_blueprint_id: bp_id,
          slug: slug,
          definition_snapshot: snapshot,
          accepted_at: at
        },
        _meta
      ) do
    Repo.insert!(
      %QuestInstance{
        id: qid,
        player_id: pid,
        npc_blueprint_id: bp_id,
        slug: slug,
        state: "active",
        accepted_at: ensure_datetime(at),
        definition_snapshot: snapshot
      },
      on_conflict: :nothing,
      conflict_target: :id
    )

    # Spawn one quest-scoped item per (criterion, spawn_room_id) pair.
    # The contract guarantees `length(spawn_room_ids) == target_count`
    # so each room gets exactly one item.
    criteria = snapshot_list(snapshot, "criteria")

    for criterion <- criteria,
        room_id <- snapshot_list(criterion, "spawn_room_ids") do
      spawn_quest_object(criterion, room_id, pid, qid)
    end

    :ok
  end

  defp spawn_quest_object(criterion, room_id, player_id, quest_instance_id) do
    item_name = snapshot_get(criterion, "item_name") || "quest item"
    item_short = snapshot_get(criterion, "item_short_description") || "a quest item"
    item_long = snapshot_get(criterion, "item_long_description") || item_short
    tag = snapshot_get(criterion, "quest_tag")

    # Idempotency under replay: PlaceObject's aggregate guard rejects a
    # duplicate object_id with :object_already_in_room, but since we
    # generate a fresh UUID each replay we would actually re-spawn. To
    # make replay safe, derive a deterministic object id from
    # (quest_instance_id, room_id, criterion tag) so the same triple
    # never produces a new id on a re-run of the same event.
    deterministic_oid =
      :crypto.hash(:sha, "#{quest_instance_id}|#{room_id}|#{tag}")
      |> Base.encode16(case: :lower)
      |> binary_part(0, 32)
      |> uuid_format()

    WorldApp.dispatch(%PlaceObject{
      room_id: room_id,
      object_id: deterministic_oid,
      name: item_name,
      short_description: item_short,
      long_description: item_long,
      fixed: false,
      behaviors: [%{"type" => "quest_tag", "tag" => tag}],
      quest_player_id: player_id,
      quest_instance_id: quest_instance_id
    })

    :ok
  rescue
    _ -> :ok
  end

  defp uuid_format(hex32) when byte_size(hex32) == 32 do
    <<a::binary-size(8), b::binary-size(4), c::binary-size(4), d::binary-size(4),
      e::binary-size(12)>> = hex32

    "#{a}-#{b}-#{c}-#{d}-#{e}"
  end

  # Helpers for reading jsonb maps that may have string or atom keys.
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

  # EventStore round-trips `%DateTime{}` through JSON as an ISO 8601 string.
  # The projector accepts either shape so live-dispatched events (struct in
  # memory) and replayed events (string after JSON deserialize) both work.
  defp ensure_datetime(%DateTime{} = dt), do: dt

  defp ensure_datetime(s) when is_binary(s) do
    {:ok, dt, _offset} = DateTime.from_iso8601(s)
    DateTime.truncate(dt, :second)
  end

  defp next_serial_for_blueprint(bp_id) do
    from(c in NPCClone, where: c.blueprint_id == ^bp_id, select: max(c.serial))
    |> Repo.one()
    |> case do
      nil -> 1
      n -> n + 1
    end
  end

  defp utc_now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
