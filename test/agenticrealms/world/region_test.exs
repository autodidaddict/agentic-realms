defmodule AgenticRealms.World.RegionTest do
  use ExUnit.Case, async: true

  alias AgenticRealms.World.Region

  alias AgenticRealms.World.Commands.{
    CreateRegion,
    ProvisionTransientRegion,
    OpenTransientEntryExit,
    DestroyRegion
  }

  alias AgenticRealms.World.Events.{
    RegionCreated,
    TransientRegionProvisioned,
    TransientEntryExitOpened,
    RegionDestroyed
  }

  @at ~U[2026-06-08 00:00:00Z]

  describe "execute/2 — CreateRegion" do
    test "fresh aggregate emits RegionCreated" do
      cmd = %CreateRegion{region_id: "r-1", name: "Blackmire"}
      assert %RegionCreated{region_id: "r-1", name: "Blackmire"} = Region.execute(%Region{}, cmd)
    end

    test "already-created aggregate rejects with :region_already_exists" do
      state = %Region{id: "r-1", name: "Blackmire"}
      cmd = %CreateRegion{region_id: "r-1", name: "Blackmire"}
      assert {:error, :region_already_exists} = Region.execute(state, cmd)
    end

    test "rejects blank name" do
      cmd = %CreateRegion{region_id: "r-1", name: ""}
      assert {:error, :region_name_blank} = Region.execute(%Region{}, cmd)
    end

    test "rejects whitespace-only name" do
      cmd = %CreateRegion{region_id: "r-1", name: "   "}
      assert {:error, :region_name_blank} = Region.execute(%Region{}, cmd)
    end
  end

  describe "apply/2 — RegionCreated" do
    test "populates id and name" do
      state = Region.apply(%Region{}, %RegionCreated{region_id: "r-1", name: "Blackmire"})
      assert %Region{id: "r-1", name: "Blackmire"} = state
    end

    test "execute → apply round-trip rehydrates state" do
      event = Region.execute(%Region{}, %CreateRegion{region_id: "r-1", name: "Blackmire"})
      state = Region.apply(%Region{}, event)
      assert state.id == "r-1"
      assert state.name == "Blackmire"

      assert {:error, :region_already_exists} =
               Region.execute(state, %CreateRegion{region_id: "r-1", name: "Blackmire"})
    end
  end

  # ── Feature 017 — Transient Regions ──────────────────────────────────

  describe "execute/2 — ProvisionTransientRegion" do
    test "fresh aggregate emits TransientRegionProvisioned" do
      cmd = %ProvisionTransientRegion{
        region_id: "r-2",
        name: "Pocket",
        provision_owner_id: 7,
        provisioned_at: @at,
        source_room_id: "src",
        origin_room_id: "orig"
      }

      assert %TransientRegionProvisioned{
               region_id: "r-2",
               name: "Pocket",
               provision_owner_id: 7,
               source_room_id: "src",
               origin_room_id: "orig"
             } = Region.execute(%Region{}, cmd)
    end

    test "already-created aggregate rejects with :region_already_exists" do
      state = %Region{id: "r-2", name: "Pocket", kind: :transient}

      cmd = %ProvisionTransientRegion{
        region_id: "r-2",
        name: "Pocket",
        provision_owner_id: 7,
        provisioned_at: @at,
        source_room_id: "src",
        origin_room_id: "orig"
      }

      assert {:error, :region_already_exists} = Region.execute(state, cmd)
    end
  end

  describe "execute/2 — OpenTransientEntryExit" do
    test "transient region emits TransientEntryExitOpened scoped to the owner" do
      state = %Region{id: "r-2", name: "Pocket", kind: :transient, provision_owner_id: 7}

      cmd = %OpenTransientEntryExit{
        region_id: "r-2",
        source_room_id: "src",
        direction: :rift,
        origin_room_id: "orig",
        provision_owner_id: 7
      }

      assert %TransientEntryExitOpened{
               source_room_id: "src",
               direction: :rift,
               target_room_id: "orig",
               visible_to_user_id: 7
             } = Region.execute(state, cmd)
    end

    test "missing region rejects with :region_not_found" do
      cmd = %OpenTransientEntryExit{
        region_id: "r-2",
        source_room_id: "src",
        direction: :rift,
        origin_room_id: "orig",
        provision_owner_id: 7
      }

      assert {:error, :region_not_found} = Region.execute(%Region{}, cmd)
    end

    test "permanent region rejects with :not_transient" do
      state = %Region{id: "r-1", name: "Blackmire"}

      cmd = %OpenTransientEntryExit{
        region_id: "r-1",
        source_room_id: "src",
        direction: :rift,
        origin_room_id: "orig",
        provision_owner_id: 7
      }

      assert {:error, :not_transient} = Region.execute(state, cmd)
    end
  end

  describe "apply/2 — transient events" do
    test "TransientRegionProvisioned populates the transient fields" do
      ev = %TransientRegionProvisioned{
        region_id: "r-2",
        name: "Pocket",
        provision_owner_id: 7,
        provisioned_at: @at,
        source_room_id: "src",
        origin_room_id: "orig"
      }

      state = Region.apply(%Region{}, ev)
      assert state.id == "r-2"
      assert state.kind == :transient
      assert state.provision_owner_id == 7
      assert state.source_room_id == "src"
      assert state.origin_room_id == "orig"
    end

    test "TransientEntryExitOpened leaves aggregate state unchanged" do
      state = %Region{id: "r-2", name: "Pocket", kind: :transient, provision_owner_id: 7}

      ev = %TransientEntryExitOpened{
        region_id: "r-2",
        source_room_id: "src",
        direction: :rift,
        target_room_id: "orig",
        visible_to_user_id: 7
      }

      assert ^state = Region.apply(state, ev)
    end

    test "RegionDestroyed marks the aggregate destroyed" do
      state =
        Region.apply(%Region{id: "r-2", kind: :transient}, %RegionDestroyed{region_id: "r-2"})

      assert state.destroyed?
    end
  end

  describe "execute/2 — DestroyRegion (idempotent)" do
    test "a live transient region emits RegionDestroyed" do
      state = %Region{id: "r-2", name: "Pocket", kind: :transient}

      assert %RegionDestroyed{region_id: "r-2"} =
               Region.execute(state, %DestroyRegion{region_id: "r-2"})
    end

    test "an already-destroyed region is a no-op" do
      state = %Region{id: "r-2", kind: :transient, destroyed?: true}
      assert :ok = Region.execute(state, %DestroyRegion{region_id: "r-2"})
    end

    test "an empty/already-purged aggregate is a no-op" do
      assert :ok = Region.execute(%Region{}, %DestroyRegion{region_id: "r-2"})
    end
  end
end
