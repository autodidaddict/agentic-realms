defmodule AgenticRealms.World.Projections.WorldProjector do
  @moduledoc """
  Projects room / exit / region / NPC-blueprint / quest domain events into
  the `world_rooms`, `world_exits`, `npc_blueprints`, `regions`, and
  `quest_instances` read models.

  Current handlers: `RoomCreated`, `ExitAdded`, `RegionCreated`,
  `NPCBlueprintCreated`, `PlayerDiscoveredRoom`, and `QuestAccepted` (which
  also dispatches quest-item creation via the entity lifecycle).

  **Feature 016 note**: object and NPC-clone row writes moved to
  `EntityProjector` (from `EntityCloned`/`EntityMoved`/`EntityEdited`) when
  spawning was unified onto clone/move. The object placement/take/drop and
  NPC clone/legacy-replay handlers were removed from this projector.

  Every insert uses `on_conflict: :nothing` so the projector is safe to
  replay against a partially-populated read model.
  """

  use Commanded.Event.Handler,
    application: AgenticRealms.World.Application,
    name: __MODULE__,
    consistency: :strong

  alias AgenticRealms.Repo
  alias AgenticRealms.World.Direction

  alias AgenticRealms.World.Events.{
    RoomCreated,
    ExitAdded,
    NPCBlueprintCreated,
    RegionCreated,
    QuestAccepted
  }

  alias AgenticRealms.World.Events.PlayerDiscoveredRoom, as: PlayerDiscoveredRoomEvent
  alias AgenticRealms.World.Application, as: WorldApp
  alias AgenticRealms.World.ContainerRef
  alias AgenticRealms.World.Commands.{CloneEntity, MoveEntity}

  alias AgenticRealms.World.Schemas.{
    Room,
    Exit,
    NPCBlueprint,
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

  # Feature 016 — object spawn / place / take / drop / edit moved to the
  # entity lifecycle (`EntityProjector` handles EntityCloned/Moved/Edited).
  # The Room aggregate no longer emits object events.

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
        quests: Map.get(event, :quests, []) || [],
        # Feature 015 — authoring fields; Map.get defends replay of pre-015 events.
        kind: Map.get(event, :kind) || "npc",
        fixed: Map.get(event, :fixed, false),
        toolsets: Map.get(event, :toolsets, []) || [],
        revision: Map.get(event, :revision, 1)
      },
      on_conflict: :nothing,
      conflict_target: :id
    )

    :ok
  end

  # Feature 016 — NPC clone spawning moved to the entity lifecycle
  # (`EntityProjector` handles `EntityCloned`/`EntityMoved` for `:npc`). The
  # legacy feature-007 `NPCSpawnedInRoom` replay path + synthetic blueprints
  # are dropped (destroyable log; reseed produces clean clone/move streams).

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
  # clone a quest-scoped item into the spawn room via the entity lifecycle
  # (feature 016), carrying the quest_player_id + quest_instance_id visibility
  # fields in the cloned payload.
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

    # Idempotency under replay: derive a deterministic entity id from
    # (quest_instance_id, room_id, criterion tag) so a re-run of the same
    # event re-clones the same id (→ :already_exists) and re-moves into the
    # same room (→ no-op) rather than spawning a duplicate.
    deterministic_oid =
      :crypto.hash(:sha, "#{quest_instance_id}|#{room_id}|#{tag}")
      |> Base.encode16(case: :lower)
      |> binary_part(0, 32)
      |> uuid_format()

    # Feature 016 — quest items are cloned into existence (with quest scope
    # frozen into the fields) then moved into the spawn room, so they are
    # real entities the player can take. The deterministic id keeps this
    # replay-safe (re-clone → :already_exists, re-move → no-op).
    WorldApp.dispatch(%CloneEntity{
      entity_id: deterministic_oid,
      kind: :object,
      fields: %{
        name: item_name,
        short_description: item_short,
        long_description: item_long,
        fixed: false,
        behaviors: [%{"type" => "quest_tag", "tag" => tag}],
        quest_player_id: player_id,
        quest_instance_id: quest_instance_id
      }
    })

    WorldApp.dispatch(%MoveEntity{
      entity_id: deterministic_oid,
      expected_from: ContainerRef.void(),
      to: ContainerRef.room(room_id),
      cause: :placed
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
end
