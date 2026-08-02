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

  import Ecto.Query

  alias AgenticRealms.World.EventData
  alias AgenticRealms.Repo
  alias AgenticRealms.World.Direction

  alias AgenticRealms.World.Events.{
    RoomCreated,
    ExitAdded,
    RegionCreated,
    TransientRegionProvisioned,
    TransientEntryExitOpened,
    RegionDestroyed,
    QuestAccepted
  }

  alias AgenticRealms.World.Events.PlayerDiscoveredRoom, as: PlayerDiscoveredRoomEvent
  alias AgenticRealms.World.Application, as: WorldApp
  alias AgenticRealms.World.ContainerRef
  alias AgenticRealms.World.Commands.{CloneEntity, MoveEntity}

  alias AgenticRealms.World.Schemas.{
    Room,
    Exit,
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

  # Feature 017 — Transient Regions. The provisioning event carries the
  # `kind: "transient"` discriminator plus owner + lifetime anchor + the
  # permanent source room and the generated origin room (used for owner
  # relocation on teardown).
  def handle(
        %TransientRegionProvisioned{
          region_id: id,
          name: name,
          provision_owner_id: owner,
          provisioned_at: at,
          source_room_id: src,
          origin_room_id: origin
        },
        _meta
      ) do
    Repo.insert!(
      %Region{
        id: id,
        name: name,
        kind: "transient",
        provision_owner_id: owner,
        provisioned_at: ensure_datetime_usec(at),
        source_room_id: src,
        origin_room_id: origin
      },
      on_conflict: :nothing,
      conflict_target: :id
    )

    :ok
  end

  # Feature 017 — the owner-only `:rift` entry exit. Inserted with
  # `visible_to_user_id` set, so it resolves only for the provision-owner; the
  # conflict target is the partial owned-exit unique index.
  def handle(
        %TransientEntryExitOpened{
          source_room_id: src,
          direction: dir,
          target_room_id: target,
          visible_to_user_id: owner
        },
        _meta
      ) do
    Repo.insert!(
      %Exit{
        source_room_id: src,
        direction: Direction.to_string(dir),
        target_room_id: target,
        visible_to_user_id: owner
      },
      on_conflict: :nothing,
      conflict_target:
        {:unsafe_fragment,
         "(source_room_id, direction, visible_to_user_id) WHERE visible_to_user_id IS NOT NULL"}
    )

    :ok
  end

  # Feature 017 — teardown tombstone. The actual rows are removed by
  # `Transient.Purge` (which owns the crash-safe deletion order); this handler
  # only stamps `destroyed_at` so a crash between teardown and purge leaves a
  # marker the reaper re-detects.
  def handle(%RegionDestroyed{region_id: id}, _meta) do
    from(r in Region, where: r.id == ^id)
    |> Repo.update_all(set: [destroyed_at: DateTime.utc_now()])

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
    # Feature 017 — exits added via the Room aggregate are global
    # (visible_to_user_id IS NULL); the conflict target is the partial global
    # unique index introduced when owner-scoped exits became possible.
    Repo.insert!(
      %Exit{
        source_room_id: source,
        direction: Direction.to_string(direction),
        target_room_id: target
      },
      on_conflict: :nothing,
      conflict_target:
        {:unsafe_fragment, "(source_room_id, direction) WHERE visible_to_user_id IS NULL"}
    )

    :ok
  end

  # Feature 016 — object spawn / place / take / drop / edit moved to the
  # entity lifecycle (`EntityProjector` handles EntityCloned/Moved/Edited).
  # The Room aggregate no longer emits object events.

  # Feature 015 — authored NPC blueprints now land in the unified
  # `blueprints` table via `BlueprintProjector` (BlueprintCreated). The
  # old `NPCBlueprintCreated` → `npc_blueprints` insert is removed here.

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
    criteria = EventData.list(snapshot, "criteria")

    for criterion <- criteria,
        room_id <- EventData.list(criterion, "spawn_room_ids") do
      spawn_quest_object(criterion, room_id, pid, qid)
    end

    :ok
  end

  defp spawn_quest_object(criterion, room_id, player_id, quest_instance_id) do
    item_name = EventData.get(criterion, "item_name") || "quest item"
    item_short = EventData.get(criterion, "item_short_description") || "a quest item"
    item_long = EventData.get(criterion, "item_long_description") || item_short
    tag = EventData.get(criterion, "quest_tag")

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

  # EventStore round-trips `%DateTime{}` through JSON as an ISO 8601 string.
  # The projector accepts either shape so live-dispatched events (struct in
  # memory) and replayed events (string after JSON deserialize) both work.
  defp ensure_datetime(%DateTime{} = dt), do: dt

  defp ensure_datetime(s) when is_binary(s) do
    {:ok, dt, _offset} = DateTime.from_iso8601(s)
    DateTime.truncate(dt, :second)
  end

  # Feature 017 — `regions.provisioned_at` is a `:utc_datetime_usec` column, so
  # the projected value must carry microsecond precision (precision 6). The
  # event round-trips through the JSON serializer, so this also accepts the
  # ISO 8601 string form.
  defp ensure_datetime_usec(%DateTime{} = dt), do: with_usec(dt)

  defp ensure_datetime_usec(s) when is_binary(s) do
    {:ok, dt, _offset} = DateTime.from_iso8601(s)
    with_usec(dt)
  end

  defp with_usec(%DateTime{microsecond: {v, _}} = dt), do: %{dt | microsecond: {v, 6}}
end
