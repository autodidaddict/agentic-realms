defmodule AgenticRealms.World.Transient.ProvisionIntegrationTest do
  @moduledoc """
  Feature 017 US1 — provision a transient region, land the owner inside it,
  navigate the generated rooms, and enforce the owner-only `:rift` entry exit.
  """
  use AgenticRealms.DataCase, async: false

  @moduletag :commanded

  import Ecto.Query

  alias AgenticRealms.Accounts
  alias AgenticRealms.Repo
  alias AgenticRealms.World.{Commands, Queries, Transient}
  alias AgenticRealms.World.Schemas.{Region, Room}

  setup do
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

    %{owner: owner, source: source, suffix: suffix, tregion: tregion, region: region}
  end

  test "provisions a transient region of a few off-map rooms and lands the owner in the origin",
       %{owner: owner, tregion: tregion, region: region} do
    assert region.kind == "transient"
    assert region.provision_owner_id == owner.id

    rooms = Repo.all(from(r in Room, where: r.region_id == ^tregion))
    assert length(rooms) == 3
    assert Enum.all?(rooms, &(&1.map_visible == false))

    assert {:ok, region.origin_room_id} == Queries.current_room_of(owner.id)
  end

  test "the owner can navigate the generated rooms and return via the rift", %{
    owner: owner,
    source: source,
    region: region
  } do
    origin = region.origin_room_id

    assert {:ok, hollow} = Commands.move(owner.id, :north)
    assert hollow != origin
    assert {:ok, ^origin} = Commands.move(owner.id, :south)

    assert {:ok, ^source} = Commands.move(owner.id, :rift)
    assert {:ok, ^source} = Queries.current_room_of(owner.id)
  end

  test "the rift entry exit is visible to and traversable by the owner only", %{
    owner: owner,
    source: source,
    region: region,
    suffix: suffix
  } do
    origin = region.origin_room_id

    assert {:ok, ^source} = Commands.move(owner.id, :rift)

    {:ok, owner_view} = Queries.look_room(owner.id)
    assert "rift" in Enum.map(owner_view.exits, & &1.direction)

    {:ok, other} = Accounts.register_player(%{username: "oth_#{suffix}", password: "pw12345678"})
    {:ok, _} = Commands.spawn(other.id, source)

    {:ok, other_view} = Queries.look_room(other.id)
    refute "rift" in Enum.map(other_view.exits, & &1.direction)
    assert {:error, :no_exit_in_direction} = Commands.move(other.id, :rift)

    refute origin == source
  end

  test "a second provisioning for the same owner is rejected (one per owner)", %{owner: owner} do
    {:ok, current} = Queries.current_room_of(owner.id)
    assert {:error, :already_provisioned} = Transient.provision(owner.id, current)
  end
end
