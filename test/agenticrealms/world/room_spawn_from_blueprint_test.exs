defmodule AgenticRealms.World.RoomSpawnFromBlueprintTest do
  use ExUnit.Case, async: true

  alias AgenticRealms.World.Room
  alias AgenticRealms.World.Commands.SpawnObjectFromBlueprint
  alias AgenticRealms.World.Events.{RoomCreated, ObjectSpawned}

  @room_id "00000000-0000-0000-0000-0000aaaa0001"
  @region_id "00000000-0000-0000-0000-0000aaaa0900"
  @object_id "00000000-0000-0000-0000-0000aaaa0100"

  defp created_room do
    Room.apply(%Room{}, %RoomCreated{
      room_id: @room_id,
      region_id: @region_id,
      name: "Test Chamber",
      description: "A bare test chamber."
    })
  end

  defp valid_cmd do
    %SpawnObjectFromBlueprint{
      room_id: @room_id,
      object_id: @object_id,
      blueprint_id: "brass_chest",
      wizard_id: 1,
      name: "brass chest",
      short_description: "a brass-bound chest",
      long_description: "A weather-beaten brass-bound chest.",
      fixed: true
    }
  end

  describe "execute/2 — SpawnObjectFromBlueprint" do
    test "emits ObjectSpawned with the denormalized payload from the wrapper" do
      assert %ObjectSpawned{
               object_id: @object_id,
               room_id: @room_id,
               name: "brass chest",
               short_description: "a brass-bound chest",
               long_description: "A weather-beaten brass-bound chest.",
               fixed: true
             } = Room.execute(created_room(), valid_cmd())
    end

    test "refuses when the room aggregate is not yet created" do
      assert {:error, :room_not_found} = Room.execute(%Room{}, valid_cmd())
    end

    test "refuses when the same object_id is already present in the room" do
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

  describe "apply/2 — ObjectSpawned" do
    test "adds the object_id to the room's presence set" do
      event = Room.execute(created_room(), valid_cmd())
      state = Room.apply(created_room(), event)

      assert MapSet.member?(state.object_ids, @object_id)
    end
  end
end
