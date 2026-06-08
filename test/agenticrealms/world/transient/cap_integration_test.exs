defmodule AgenticRealms.World.Transient.CapIntegrationTest do
  @moduledoc """
  Feature 017 US4 — the 60-minute absolute lifetime cap, and crash-recovery of
  the stateless reaper.
  """
  use AgenticRealms.DataCase, async: false

  @moduletag :commanded

  import Ecto.Query

  alias AgenticRealms.Accounts
  alias AgenticRealms.Repo
  alias AgenticRealms.World.{Commands, Queries, Transient}
  alias AgenticRealms.World.Transient.{Manager, EventStoreStub}
  alias AgenticRealms.World.Schemas.{Region, Room}
  alias AgenticRealmsWeb.Presence

  setup do
    EventStoreStub.reset()
    :ok
  end

  test "a region past its lifetime cap is purged even while the owner stays online" do
    suffix = System.unique_integer([:positive])
    region_id = Ecto.UUID.generate()
    :ok = Commands.create_region(region_id, "Home #{suffix}")
    source = Ecto.UUID.generate()
    :ok = Commands.create_room(source, "Town Square", "hub", region_id, map_visible: true)
    {:ok, owner} = Accounts.register_player(%{username: "own_#{suffix}", password: "pw12345678"})
    {:ok, _} = Commands.spawn(owner.id, source)
    {:ok, tregion} = Transient.provision(owner.id, source)

    # Owner stays logged in, but the region was provisioned long ago.
    {:ok, _} = Presence.track_player(self(), owner.id, "owner")
    set_provisioned_at(tregion, minutes_ago(120))

    Manager.sweep_now()

    assert Repo.get(Region, tregion) == nil
    assert Repo.all(from(r in Room, where: r.region_id == ^tregion)) == []
    # Owner relocated out before purge.
    assert {:ok, ^source} = Queries.current_room_of(owner.id)
  end

  test "an already-overdue region is reaped on the first sweep (no in-memory state to lose)" do
    # Simulates recovery: a region that became abandoned while the manager was
    # absent — owner offline past grace AND cap elapsed — is reaped purely from
    # durable columns on the next sweep (FR-018).
    owner = System.unique_integer([:positive])
    id = Ecto.UUID.generate()

    Repo.insert!(%Region{
      id: id,
      name: "Overdue-#{System.unique_integer([:positive])}",
      kind: "transient",
      provision_owner_id: owner,
      provisioned_at: minutes_ago(120),
      owner_offline_since: minutes_ago(30)
    })

    assert id in Manager.sweep_now()
    assert Repo.get(Region, id) == nil
  end

  defp set_provisioned_at(region_id, dt) do
    from(r in Region, where: r.id == ^region_id)
    |> Repo.update_all(set: [provisioned_at: dt])
  end

  defp minutes_ago(m), do: DateTime.utc_now() |> DateTime.add(-m * 60, :second)
end
