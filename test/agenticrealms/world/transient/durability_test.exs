defmodule AgenticRealms.World.Transient.DurabilityTest do
  @moduledoc """
  Transient rooms are as durable as permanent rooms.

  Full event-replay crash recovery is a platform guarantee: transient rooms are
  ordinary event-sourced `Room` aggregates whose events live in the Postgres
  event store, so they replay on restart exactly like permanent rooms. That is
  verified against Postgres via the quickstart — the `:test` env uses the
  ephemeral in-memory event-store adapter, where a simulated BEAM restart would
  discard the store entirely, so it cannot be asserted here.

  What this pins down in-memory: the generated rooms are real, durable
  `world_rooms` read-model rows, navigable like any room, and the 60-minute cap
  is anchored to a *persisted* `provisioned_at` (a restart cannot reset it).
  """
  use AgenticRealms.DataCase, async: false

  @moduletag :commanded

  import Ecto.Query

  alias AgenticRealms.Accounts
  alias AgenticRealms.Repo
  alias AgenticRealms.World.{Commands, Transient}
  alias AgenticRealms.World.Schemas.{Region, Room}

  setup do
    suffix = System.unique_integer([:positive])
    region_id = Ecto.UUID.generate()
    :ok = Commands.create_region(region_id, "Home #{suffix}")
    source = Ecto.UUID.generate()

    :ok =
      Commands.create_room(source, "Town Square", "hub", region_id,
        map_visible: true,
        elevation: 0,
        map_x: 0,
        map_y: 0
      )

    {:ok, owner} = Accounts.register_player(%{username: "own_#{suffix}", password: "pw12345678"})
    {:ok, _} = Commands.spawn(owner.id, source)
    {:ok, tregion} = Transient.provision(owner.id, source)

    %{owner: owner, tregion: tregion, region: Repo.get(Region, tregion)}
  end

  test "transient rooms are durable world_rooms rows, navigable like any room", %{
    owner: owner,
    tregion: tregion
  } do
    rooms = Repo.all(from(r in Room, where: r.region_id == ^tregion))
    assert length(rooms) == 3

    assert {:ok, hollow} = Commands.move(owner.id, :north)
    assert Repo.get(Room, hollow)
  end

  test "the lifetime cap is anchored to a persisted provisioned_at column", %{region: region} do
    assert %DateTime{} = region.provisioned_at
  end
end
