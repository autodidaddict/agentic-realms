defmodule AgenticRealms.World.RegionTest do
  use ExUnit.Case, async: true

  alias AgenticRealms.World.Region
  alias AgenticRealms.World.Commands.CreateRegion
  alias AgenticRealms.World.Events.RegionCreated

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
end
