defmodule AgenticRealms.World.QueriesGlobalExitsTest do
  @moduledoc "List_global_exits/1 returns only global exits with target_room_id."
  use AgenticRealms.DataCase, async: true

  alias AgenticRealms.World.Queries
  alias AgenticRealms.World.Schemas.{Room, Exit}

  defp insert_room(region) do
    Repo.insert!(%Room{
      id: Ecto.UUID.generate(),
      name: "R#{System.unique_integer([:positive])}",
      description: "d",
      region_id: region
    }).id
  end

  test "returns global exits (visible_to_user_id IS NULL) as %{direction, target_room_id}" do
    region = insert_test_region()
    src = insert_room(region)
    north = insert_room(region)
    rift = insert_room(region)

    Repo.insert!(%Exit{direction: "north", source_room_id: src, target_room_id: north})

    Repo.insert!(%Exit{
      direction: "rift",
      source_room_id: src,
      target_room_id: rift,
      visible_to_user_id: 42
    })

    assert [%{direction: "north", target_room_id: ^north}] = Queries.list_global_exits(src)
  end

  test "returns [] for a room with no global exits" do
    region = insert_test_region()
    assert [] == Queries.list_global_exits(insert_room(region))
  end
end
