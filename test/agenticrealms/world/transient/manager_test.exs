defmodule AgenticRealms.World.Transient.ManagerTest do
  @moduledoc """
  Feature 017 — the reaper's due-ness logic and presence reconciliation, driven
  synchronously via `Manager.sweep_now/0` against directly-inserted region rows.
  """
  use AgenticRealms.DataCase, async: false

  @moduletag :commanded

  alias AgenticRealms.Repo
  alias AgenticRealms.World.Transient.{Manager, EventStoreStub}
  alias AgenticRealms.World.Schemas.Region
  alias AgenticRealmsWeb.Presence

  setup do
    EventStoreStub.reset()
    :ok
  end

  test "reaps a transient region whose owner has been offline past the grace" do
    owner = unique_owner()
    rid = insert_transient(owner, owner_offline_since: minutes_ago(10))

    # owner offline (not tracked in presence)
    assert rid in Manager.sweep_now()
    assert Repo.get(Region, rid) == nil
  end

  test "does not reap while the owner is online — and clears a stale offline stamp" do
    owner = unique_owner()
    {:ok, _} = Presence.track_player(self(), owner, "owner-#{owner}")
    rid = insert_transient(owner, owner_offline_since: minutes_ago(10))

    refute rid in Manager.sweep_now()
    region = Repo.get(Region, rid)
    assert region
    assert region.owner_offline_since == nil
  end

  test "does not reap a fresh logoff that is still within the grace window" do
    owner = unique_owner()
    rid = insert_transient(owner, owner_offline_since: nil)

    # owner offline; the sweep stamps owner_offline_since=now but must not reap.
    refute rid in Manager.sweep_now()
    region = Repo.get(Region, rid)
    assert region
    assert region.owner_offline_since != nil
  end

  # Feature 017 US4 — the 60-minute absolute cap.
  test "reaps once the lifetime cap has elapsed even if the owner is online" do
    owner = unique_owner()
    {:ok, _} = Presence.track_player(self(), owner, "owner-#{owner}")
    # Provisioned two hours ago — well past the 60-minute cap.
    rid = insert_transient(owner, provisioned_at: minutes_ago(120), owner_offline_since: nil)

    assert rid in Manager.sweep_now()
    assert Repo.get(Region, rid) == nil
  end

  # --- helpers ------------------------------------------------------------

  defp unique_owner, do: System.unique_integer([:positive])

  defp minutes_ago(m), do: DateTime.utc_now() |> DateTime.add(-m * 60, :second)

  defp insert_transient(owner, opts) do
    id = Ecto.UUID.generate()

    Repo.insert!(%Region{
      id: id,
      name: "T-#{System.unique_integer([:positive])}",
      kind: "transient",
      provision_owner_id: owner,
      provisioned_at: Keyword.get(opts, :provisioned_at, DateTime.utc_now()),
      owner_offline_since: Keyword.get(opts, :owner_offline_since)
    })

    id
  end
end
