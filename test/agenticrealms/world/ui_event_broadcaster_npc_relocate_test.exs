defmodule AgenticRealms.World.UIEventBroadcasterNpcRelocateTest do
  @moduledoc "A room→room NPC move is witnessed as NPC-left + NPC-arrived."
  use AgenticRealms.DataCase, async: false

  @moduletag :commanded

  alias AgenticRealms.World.{Commands, ContainerRef}
  alias AgenticRealms.World.UIEvents.{RoomNPCLeft, RoomNPCArrived}
  alias AgenticRealmsWeb.Topics

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

  test "relocating an NPC broadcasts RoomNPCLeft (origin) and RoomNPCArrived (destination)" do
    region = insert_test_region()
    a = Ecto.UUID.generate()
    b = Ecto.UUID.generate()
    :ok = Commands.create_room(a, "A", "d", region)
    :ok = Commands.create_room(b, "B", "d", region)
    {:ok, npc} = Commands.clone_into(:npc, npc_fields("Grik"), ContainerRef.room(a), :spawned)

    Phoenix.PubSub.subscribe(AgenticRealms.PubSub, Topics.room_topic(a))
    Phoenix.PubSub.subscribe(AgenticRealms.PubSub, Topics.room_topic(b))

    :ok = Commands.move_entity(npc, ContainerRef.room(a), ContainerRef.room(b), :relocated)

    assert_receive %RoomNPCLeft{npc_id: ^npc, npc_name: "Grik", room_id: ^a}, 2000
    assert_receive %RoomNPCArrived{npc_id: ^npc, npc_name: "Grik", room_id: ^b}, 2000
  end
end
