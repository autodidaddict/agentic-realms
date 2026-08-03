defmodule AgenticRealms.World.Transient.CapIntegrationTest do
  @moduledoc """
  The 60-minute absolute lifetime cap, and crash-recovery of
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

    {:ok, _} = Presence.track_player(self(), owner.id, "owner")
    Phoenix.PubSub.subscribe(AgenticRealms.PubSub, AgenticRealmsWeb.Topics.player_topic(owner.id))
    set_provisioned_at(tregion, minutes_ago(120))

    Manager.sweep_now()

    assert Repo.get(Region, tregion) == nil
    assert Repo.all(from(r in Room, where: r.region_id == ^tregion)) == []
    assert {:ok, ^source} = Queries.current_room_of(owner.id)
    assert_receive :transient_region_ended, 2_000
  end

  test "an already-overdue region is reaped on the first sweep (no in-memory state to lose)" do
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
