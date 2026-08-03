defmodule AgenticRealms.World.Transient.Purge do
  @moduledoc """
  Feature 017 — permanently purge a destroyed transient region. Commanded's
  event-store adapter exposes no stream deletion, so this calls the underlying
  event store directly (`delete_stream/3` hard, `delete_snapshot/1`) — which
  requires `enable_hard_deletes: true`. The event-store module is an injectable
  seam (`:transient_event_store`) so tests can record targets against the
  in-memory adapter, which has no `delete_stream`.

  Deletion is idempotent and ordered for crash-safety and FK-safety:

    1. event streams (entity-*, room-*, region-*) + room snapshots
    2. read-model rows, **regions last** — so a crash mid-purge leaves the
       region row (with its `destroyed_at` tombstone) for the reaper to retry.

  FK order within the read model: world_exits (clears the `:restrict` target
  FK) → npc_clones (`:restrict`) → world_objects (denormalized, no FK) →
  player_discovered_rooms (`:delete_all`, explicit anyway) → world_rooms →
  regions. Occupant relocation (clearing `player_state.current_room_id`) is the
  caller's responsibility, done before this runs.
  """

  import Ecto.Query

  alias AgenticRealms.Repo
  alias AgenticRealms.NpcMinds.TemporalClient

  alias AgenticRealms.World.Schemas.{
    Region,
    Room,
    Exit,
    Object,
    NPCClone,
    PlayerDiscoveredRoom
  }

  @event_store Application.compile_env(
                 :agenticrealms,
                 :transient_event_store,
                 AgenticRealms.EventStore
               )

  @spec run(String.t()) :: :ok
  def run(region_id) when is_binary(region_id) do
    room_ids = Repo.all(from(r in Room, where: r.region_id == ^region_id, select: r.id))

    object_ids =
      Repo.all(
        from(o in Object,
          where: o.container_type == "room" and o.container_id in ^room_ids,
          select: o.id
        )
      )

    npc_ids = Repo.all(from(c in NPCClone, where: c.room_id in ^room_ids, select: c.id))

    Enum.each(npc_ids, &TemporalClient.terminate_workflow/1)

    purge_event_streams(region_id, room_ids, object_ids ++ npc_ids)
    purge_read_model(region_id, room_ids)
    :ok
  end

  defp purge_event_streams(region_id, room_ids, entity_ids) do
    Enum.each(entity_ids, fn id -> delete_stream("entity-" <> id) end)

    Enum.each(room_ids, fn id ->
      delete_stream("room-" <> id)
      delete_snapshot("room-" <> id)
    end)

    delete_stream("region-" <> region_id)
    :ok
  end

  defp delete_stream(stream_uuid) do
    safe(fn -> @event_store.delete_stream(stream_uuid, :any_version, :hard) end)
  end

  defp delete_snapshot(source_uuid) do
    safe(fn -> @event_store.delete_snapshot(source_uuid) end)
  end

  defp safe(fun) do
    fun.()
    :ok
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp purge_read_model(region_id, room_ids) do
    Repo.delete_all(
      from(e in Exit, where: e.source_room_id in ^room_ids or e.target_room_id in ^room_ids)
    )

    Repo.delete_all(from(c in NPCClone, where: c.room_id in ^room_ids))

    Repo.delete_all(
      from(o in Object, where: o.container_type == "room" and o.container_id in ^room_ids)
    )

    Repo.delete_all(from(d in PlayerDiscoveredRoom, where: d.room_id in ^room_ids))
    Repo.delete_all(from(r in Room, where: r.region_id == ^region_id))
    Repo.delete_all(from(r in Region, where: r.id == ^region_id))
    :ok
  end
end
