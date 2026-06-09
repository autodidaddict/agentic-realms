defmodule AgenticRealms.World.Transient.EdgeCasesTest do
  @moduledoc """
  Feature 017 — edge cases: clean provisioning refusals (FR-020 — no orphan
  region) and no entry into a region once it has been torn down (FR-011).
  """
  use AgenticRealms.DataCase, async: false

  @moduletag :commanded

  import Ecto.Query

  alias AgenticRealms.Accounts
  alias AgenticRealms.Repo
  alias AgenticRealms.World.{Commands, Queries, Transient}
  alias AgenticRealms.World.Transient.{Manager, EventStoreStub}
  alias AgenticRealms.World.Schemas.Region

  setup do
    EventStoreStub.reset()
    suffix = System.unique_integer([:positive])
    region_id = Ecto.UUID.generate()
    :ok = Commands.create_region(region_id, "Home #{suffix}")
    room_a = Ecto.UUID.generate()
    room_b = Ecto.UUID.generate()
    :ok = Commands.create_room(room_a, "Room A", "a", region_id, map_visible: true)
    :ok = Commands.create_room(room_b, "Room B", "b", region_id, map_visible: true)
    {:ok, owner} = Accounts.register_player(%{username: "own_#{suffix}", password: "pw12345678"})
    %{owner: owner, room_a: room_a, room_b: room_b}
  end

  test "provisioning for an unspawned owner is refused and creates no region", %{
    owner: owner,
    room_a: room_a
  } do
    assert {:error, :owner_not_spawned} = Transient.provision(owner.id, room_a)
    assert transient_count(owner.id) == 0
  end

  test "provisioning from a room the owner is not in is refused and creates no region", %{
    owner: owner,
    room_a: room_a,
    room_b: room_b
  } do
    {:ok, _} = Commands.spawn(owner.id, room_a)
    assert {:error, :owner_not_in_source_room} = Transient.provision(owner.id, room_b)
    assert transient_count(owner.id) == 0
  end

  test "once a region is torn down, its entry rift can no longer be entered", %{
    owner: owner,
    room_a: source
  } do
    {:ok, _} = Commands.spawn(owner.id, source)
    {:ok, tregion} = Transient.provision(owner.id, source)

    # Tear it down (owner offline past grace).
    from(r in Region, where: r.id == ^tregion)
    |> Repo.update_all(
      set: [owner_offline_since: DateTime.add(DateTime.utc_now(), -600, :second)]
    )

    Manager.sweep_now()

    # Owner is back in the source room; the entry rift is gone.
    assert {:ok, ^source} = Queries.current_room_of(owner.id)
    assert {:error, :no_exit_in_direction} = Commands.move(owner.id, :rift)
  end

  defp transient_count(owner_id) do
    Repo.aggregate(
      from(r in Region, where: r.kind == "transient" and r.provision_owner_id == ^owner_id),
      :count
    )
  end
end
