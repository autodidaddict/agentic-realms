defmodule AgenticRealms.World.EntityRemovedProjectorTest do
  @moduledoc "EntityRemoved deletes the read-model row (end-to-end via the command path)."
  use AgenticRealms.DataCase, async: false

  @moduletag :commanded

  alias AgenticRealms.World.{Commands, ContainerRef}
  alias AgenticRealms.World.Schemas.NPCClone

  defp npc_fields(name) do
    %{
      blueprint_id: nil,
      name: name,
      short_description: "s",
      long_description: "l",
      behaviors: [],
      direct_behaviors: [],
      behavior_groups: [],
      lore: "",
      fixed: false
    }
  end

  setup do
    region = insert_test_region()
    room = Ecto.UUID.generate()
    :ok = Commands.create_room(room, "Room", "d", region)
    %{room: room}
  end

  test "removing an NPC deletes its npc_clones row", %{room: room} do
    {:ok, npc} = Commands.clone_into(:npc, npc_fields("Grik"), ContainerRef.room(room), :spawned)
    assert Repo.get(NPCClone, npc)

    assert :ok = Commands.remove_npc(npc)
    refute Repo.get(NPCClone, npc)
  end

  test "removing an already-removed NPC → {:error, :not_found}", %{room: room} do
    {:ok, npc} = Commands.clone_into(:npc, npc_fields("Grok"), ContainerRef.room(room), :spawned)
    assert :ok = Commands.remove_npc(npc)
    assert {:error, :not_found} = Commands.remove_npc(npc)
  end

  test "removing an unknown NPC → {:error, :not_found}" do
    assert {:error, :not_found} = Commands.remove_npc(Ecto.UUID.generate())
  end
end
