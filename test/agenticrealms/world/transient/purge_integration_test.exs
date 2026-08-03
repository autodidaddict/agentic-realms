defmodule AgenticRealms.World.Transient.PurgeIntegrationTest do
  @moduledoc """
  End-to-end teardown: provision a region, then exercise the
  reaper through logoff/grace/online cases. Asserts full purge, owner
  relocation, and that an empty region with an online owner survives.
  """
  use AgenticRealms.DataCase, async: false

  @moduletag :commanded

  import Ecto.Query

  alias AgenticRealms.Accounts
  alias AgenticRealms.Repo
  alias AgenticRealms.World.{Commands, Queries, Transient}
  alias AgenticRealms.World.Transient.{Manager, EventStoreStub}
  alias AgenticRealms.World.Schemas.{Region, Room, Exit}
  alias AgenticRealmsWeb.Presence

  setup do
    EventStoreStub.reset()
    suffix = System.unique_integer([:positive])
    region_id = Ecto.UUID.generate()
    :ok = Commands.create_region(region_id, "Home #{suffix}")

    source = Ecto.UUID.generate()

    :ok =
      Commands.create_room(source, "Town Square", "The hub.", region_id,
        map_visible: true,
        elevation: 0,
        map_x: 0,
        map_y: 0
      )

    {:ok, owner} = Accounts.register_player(%{username: "own_#{suffix}", password: "pw12345678"})
    {:ok, _} = Commands.spawn(owner.id, source)
    {:ok, tregion} = Transient.provision(owner.id, source)

    region = Repo.get(Region, tregion)
    %{owner: owner, source: source, tregion: tregion, origin: region.origin_room_id}
  end

  test "owner logoff past the grace fully purges the region and relocates the owner", %{
    owner: owner,
    source: source,
    tregion: tregion,
    origin: origin
  } do
    assert {:ok, ^origin} = Queries.current_room_of(owner.id)
    set_offline_since(tregion, minutes_ago(10))

    Manager.sweep_now()

    assert Repo.get(Region, tregion) == nil
    assert Repo.all(from(r in Room, where: r.region_id == ^tregion)) == []
    assert Repo.all(from(e in Exit, where: e.direction == "rift")) == []

    assert {:ok, ^source} = Queries.current_room_of(owner.id)

    streams = EventStoreStub.deleted_streams()
    assert ("region-" <> tregion) in streams
    assert ("room-" <> origin) in streams
  end

  test "an empty region with the owner online elsewhere is NOT purged", %{
    owner: owner,
    source: source,
    tregion: tregion
  } do
    assert {:ok, ^source} = Commands.move(owner.id, :rift)
    {:ok, _} = Presence.track_player(self(), owner.id, "owner")

    Manager.sweep_now()

    assert Repo.get(Region, tregion)
    assert Repo.get(Region, tregion).owner_offline_since == nil
  end

  test "a reconnect within the grace window cancels destruction", %{
    owner: owner,
    tregion: tregion
  } do
    refute tregion in Manager.sweep_now()
    assert Repo.get(Region, tregion).owner_offline_since != nil

    {:ok, _} = Presence.track_player(self(), owner.id, "owner")
    Manager.sweep_now()

    region = Repo.get(Region, tregion)
    assert region
    assert region.owner_offline_since == nil
  end

  defp set_offline_since(region_id, dt) do
    from(r in Region, where: r.id == ^region_id)
    |> Repo.update_all(set: [owner_offline_since: dt])
  end

  defp minutes_ago(m), do: DateTime.utc_now() |> DateTime.add(-m * 60, :second)
end
