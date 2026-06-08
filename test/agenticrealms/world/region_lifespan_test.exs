defmodule AgenticRealms.World.RegionLifespanTest do
  use ExUnit.Case, async: true

  alias AgenticRealms.World.RegionLifespan
  alias AgenticRealms.World.Events.{RegionDestroyed, RegionCreated, TransientRegionProvisioned}

  test "stops the aggregate process on RegionDestroyed" do
    assert :stop == RegionLifespan.after_event(%RegionDestroyed{region_id: "r"})
  end

  test "keeps the aggregate resident on other events" do
    assert :infinity ==
             RegionLifespan.after_event(%RegionCreated{region_id: "r", name: "Blackmire"})

    assert :infinity ==
             RegionLifespan.after_event(%TransientRegionProvisioned{
               region_id: "r",
               name: "Pocket",
               provision_owner_id: 1,
               provisioned_at: ~U[2026-06-08 00:00:00Z],
               source_room_id: "s",
               origin_room_id: "o"
             })
  end

  test "stops on error" do
    assert :stop == RegionLifespan.after_error(:boom)
  end
end
