defmodule AgenticRealms.World.Transient.PurgeTest do
  @moduledoc """
  Feature 017 — `Transient.Purge` targets the right streams/rows and is
  idempotent. Uses direct read-model inserts + the recording event-store stub
  (the in-memory Commanded adapter has no `delete_stream`), so no Commanded
  chain is needed.
  """
  use AgenticRealms.DataCase, async: false

  import Ecto.Query

  alias AgenticRealms.Repo
  alias AgenticRealms.World.Transient.{Purge, EventStoreStub}
  alias AgenticRealms.World.Schemas.{Region, Room, Exit}

  setup do
    EventStoreStub.reset()
    :ok
  end

  test "hard-deletes the region/room streams and removes every read-model row, leaving permanent data intact" do
    perm = insert_region("permanent")
    source = insert_room(perm, "Source")

    tregion = insert_region("transient")
    origin = insert_room(tregion, "Origin")
    hollow = insert_room(tregion, "Hollow")

    # owner-only entry exit (permanent source -> transient origin)
    insert_exit(source, "rift", origin, 7)
    # intra-region exit (transient -> transient)
    insert_exit(origin, "north", hollow, nil)

    assert :ok = Purge.run(tregion)

    streams = EventStoreStub.deleted_streams()
    assert ("region-" <> tregion) in streams
    assert ("room-" <> origin) in streams
    assert ("room-" <> hollow) in streams

    # Read model fully gone for the transient region.
    assert Repo.get(Region, tregion) == nil
    assert Repo.all(from(r in Room, where: r.region_id == ^tregion)) == []

    assert Repo.all(
             from(e in Exit,
               where:
                 e.source_room_id in ^[source, origin, hollow] or
                   e.target_room_id in ^[source, origin, hollow]
             )
           ) == []

    # Permanent region + source room untouched.
    assert Repo.get(Region, perm)
    assert Repo.get(Room, source)
  end

  test "is idempotent — a second run is a clean no-op" do
    tregion = insert_region("transient")
    _origin = insert_room(tregion, "Origin")

    assert :ok = Purge.run(tregion)
    assert :ok = Purge.run(tregion)
    assert Repo.get(Region, tregion) == nil
  end

  # --- helpers ------------------------------------------------------------

  defp insert_region(kind) do
    id = Ecto.UUID.generate()

    Repo.insert!(%Region{
      id: id,
      name: "#{kind}-#{System.unique_integer([:positive])}",
      kind: kind
    })

    id
  end

  defp insert_room(region_id, name) do
    id = Ecto.UUID.generate()

    Repo.insert!(%Room{
      id: id,
      name: name,
      description: "d",
      region_id: region_id,
      map_visible: false
    })

    id
  end

  defp insert_exit(source, dir, target, visible) do
    Repo.insert!(%Exit{
      source_room_id: source,
      direction: dir,
      target_room_id: target,
      visible_to_user_id: visible
    })
  end
end
