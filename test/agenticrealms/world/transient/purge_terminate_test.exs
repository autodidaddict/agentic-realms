defmodule AgenticRealms.World.Transient.PurgeTerminateTest do
  @moduledoc "Feature 018 — the transient-region purge terminates the minds of NPCs it removes."
  use AgenticRealms.DataCase, async: false

  alias AgenticRealms.World.Transient.Purge
  alias AgenticRealms.World.Schemas.{Room, NPCClone}

  @client AgenticRealms.NpcMinds.TemporalClient

  test "purge terminates each removed NPC's mind and deletes the row" do
    parent = self()

    Req.Test.stub(@client, fn conn ->
      send(parent, {:terminate, conn.request_path})
      Req.Test.json(conn, %{})
    end)

    region = insert_test_region()

    room =
      Repo.insert!(%Room{
        id: Ecto.UUID.generate(),
        name: "Transient",
        description: "d",
        region_id: region
      }).id

    npc =
      Repo.insert!(%NPCClone{
        id: Ecto.UUID.generate(),
        name: "Grik",
        short_description: "s",
        long_description: "l",
        room_id: room
      }).id

    assert :ok = Purge.run(region)

    assert_received {:terminate, path}
    assert path == "/api/v1/namespaces/default/workflows/npc-#{npc}/terminate"
    refute Repo.get(NPCClone, npc)
  end

  test "purge with no NPCs completes and calls Temporal 0 times" do
    Req.Test.stub(@client, fn _conn ->
      flunk("Temporal must not be called when no NPCs are purged")
    end)

    region = insert_test_region()

    Repo.insert!(%Room{
      id: Ecto.UUID.generate(),
      name: "Empty",
      description: "d",
      region_id: region
    })

    assert :ok = Purge.run(region)
  end
end
