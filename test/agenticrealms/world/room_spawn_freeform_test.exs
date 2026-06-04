defmodule AgenticRealms.World.RoomSpawnFreeformTest do
  use ExUnit.Case, async: true

  alias AgenticRealms.World.Room
  alias AgenticRealms.World.Commands.SpawnObjectFreeform
  alias AgenticRealms.World.Events.{RoomCreated, ObjectSpawned}

  @room_id "00000000-0000-0000-0000-0000bbbb0001"
  @region_id "00000000-0000-0000-0000-0000bbbb0900"
  @object_id "00000000-0000-0000-0000-0000bbbb0100"

  defp created_room do
    Room.apply(%Room{}, %RoomCreated{
      room_id: @room_id,
      region_id: @region_id,
      name: "Test Chamber",
      description: "A bare test chamber."
    })
  end

  defp valid_cmd do
    %SpawnObjectFreeform{
      room_id: @room_id,
      object_id: @object_id,
      wizard_id: 1,
      name: "clay pot",
      short_description: "a small clay pot",
      long_description: "A small clay pot, half-empty of dry barley.",
      fixed: false
    }
  end

  describe "execute/2 — SpawnObjectFreeform" do
    test "emits ObjectSpawned with the same shape as the blueprint-spawn path" do
      assert %ObjectSpawned{
               object_id: @object_id,
               room_id: @room_id,
               name: "clay pot",
               short_description: "a small clay pot",
               long_description: "A small clay pot, half-empty of dry barley.",
               fixed: false
             } = Room.execute(created_room(), valid_cmd())
    end

    test "refuses when the room aggregate is not yet created" do
      assert {:error, :room_not_found} = Room.execute(%Room{}, valid_cmd())
    end

    test "refuses when the same object_id is already present" do
      state =
        Room.apply(created_room(), %ObjectSpawned{
          object_id: @object_id,
          room_id: @room_id,
          name: "x",
          short_description: "x",
          long_description: "x",
          fixed: false
        })

      assert {:error, :object_already_in_room} = Room.execute(state, valid_cmd())
    end

    test "emitted event carries NO blueprint_id field (FR-013)" do
      event = Room.execute(created_room(), valid_cmd())
      refute Map.has_key?(Map.from_struct(event), :blueprint_id)
    end
  end
end
