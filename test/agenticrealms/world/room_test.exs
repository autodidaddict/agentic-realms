defmodule AgenticRealms.World.RoomTest do
  use ExUnit.Case, async: true

  alias AgenticRealms.World.Room

  alias AgenticRealms.World.Commands.{
    CreateRoom,
    AddExit,
    PlaceObject,
    TakeObject,
    DropObject,
    SpawnNPC
  }

  alias AgenticRealms.World.Events.{
    RoomCreated,
    ExitAdded,
    ObjectPlacedInRoom,
    ObjectTakenFromRoom,
    ObjectDroppedInRoom,
    NPCSpawnedInRoom
  }

  @room_id "00000000-0000-0000-0000-000000000001"
  @target_id "00000000-0000-0000-0000-000000000002"
  @object_id "00000000-0000-0000-0000-000000000100"
  @npc_id "00000000-0000-0000-0000-000000000200"
  @other_npc_id "00000000-0000-0000-0000-000000000201"

  defp created_room do
    Room.apply(%Room{}, %RoomCreated{
      room_id: @room_id,
      name: "Test Room",
      description: "A room."
    })
  end

  describe "CreateRoom" do
    test "creates a fresh room" do
      assert %RoomCreated{room_id: @room_id, name: "Test Room"} =
               Room.execute(%Room{}, %CreateRoom{
                 room_id: @room_id,
                 name: "Test Room",
                 description: "A room."
               })
    end

    test "rejects creating an already-created room" do
      assert {:error, :room_already_exists} =
               Room.execute(created_room(), %CreateRoom{
                 room_id: @room_id,
                 name: "Test Room",
                 description: "A room."
               })
    end
  end

  describe "AddExit" do
    test "adds an exit when none exists" do
      assert %ExitAdded{direction: :north, target_room_id: @target_id} =
               Room.execute(created_room(), %AddExit{
                 room_id: @room_id,
                 direction: :north,
                 target_room_id: @target_id
               })
    end

    test "rejects when an exit in that direction already exists" do
      state =
        created_room()
        |> Room.apply(%ExitAdded{
          room_id: @room_id,
          direction: :north,
          target_room_id: @target_id
        })

      assert {:error, :exit_already_exists} =
               Room.execute(state, %AddExit{
                 room_id: @room_id,
                 direction: :north,
                 target_room_id: @target_id
               })
    end

    test "rejects on uninitialized room" do
      assert {:error, :room_not_found} =
               Room.execute(%Room{}, %AddExit{
                 room_id: @room_id,
                 direction: :north,
                 target_room_id: @target_id
               })
    end
  end

  describe "PlaceObject" do
    test "places an object" do
      assert %ObjectPlacedInRoom{object_id: @object_id} =
               Room.execute(created_room(), %PlaceObject{
                 room_id: @room_id,
                 object_id: @object_id,
                 name: "thing",
                 short_description: "a thing",
                 long_description: "a long thing",
                 fixed: false
               })
    end

    test "rejects when the object is already present" do
      state =
        created_room()
        |> Room.apply(%ObjectPlacedInRoom{
          room_id: @room_id,
          object_id: @object_id,
          name: "thing",
          short_description: "a thing",
          long_description: "a long thing",
          fixed: false
        })

      assert {:error, :object_already_in_room} =
               Room.execute(state, %PlaceObject{
                 room_id: @room_id,
                 object_id: @object_id,
                 name: "thing",
                 short_description: "a thing",
                 long_description: "a long thing",
                 fixed: false
               })
    end
  end

  describe "TakeObject (race resolution)" do
    setup do
      state =
        created_room()
        |> Room.apply(%ObjectPlacedInRoom{
          room_id: @room_id,
          object_id: @object_id,
          name: "thing",
          short_description: "a thing",
          long_description: "a long thing",
          fixed: false
        })

      %{state: state}
    end

    test "first taker succeeds", %{state: state} do
      assert %ObjectTakenFromRoom{object_id: @object_id, player_id: 1} =
               Room.execute(state, %TakeObject{
                 room_id: @room_id,
                 player_id: 1,
                 object_id: @object_id
               })
    end

    test "second taker (after apply) sees :object_not_in_room", %{state: state} do
      after_take =
        Room.apply(state, %ObjectTakenFromRoom{
          room_id: @room_id,
          player_id: 1,
          object_id: @object_id
        })

      assert {:error, :object_not_in_room} =
               Room.execute(after_take, %TakeObject{
                 room_id: @room_id,
                 player_id: 2,
                 object_id: @object_id
               })
    end
  end

  describe "DropObject" do
    test "drops an object" do
      assert %ObjectDroppedInRoom{object_id: @object_id, player_id: 1} =
               Room.execute(created_room(), %DropObject{
                 room_id: @room_id,
                 player_id: 1,
                 object_id: @object_id
               })
    end

    test "rejects when the object is already in this room" do
      state =
        created_room()
        |> Room.apply(%ObjectPlacedInRoom{
          room_id: @room_id,
          object_id: @object_id,
          name: "thing",
          short_description: "a thing",
          long_description: "a long thing",
          fixed: false
        })

      assert {:error, :object_already_in_room} =
               Room.execute(state, %DropObject{
                 room_id: @room_id,
                 player_id: 1,
                 object_id: @object_id
               })
    end
  end

  describe "apply/2 round-trip" do
    test "ExitAdded mutates exits" do
      state =
        created_room()
        |> Room.apply(%ExitAdded{
          room_id: @room_id,
          direction: :north,
          target_room_id: @target_id
        })

      assert %{north: @target_id} = state.exits
    end

    test "ObjectPlacedInRoom + ObjectTakenFromRoom + ObjectDroppedInRoom round-trip" do
      state =
        created_room()
        |> Room.apply(%ObjectPlacedInRoom{
          room_id: @room_id,
          object_id: @object_id,
          name: "thing",
          short_description: "a thing",
          long_description: "a long thing",
          fixed: false
        })

      assert MapSet.member?(state.object_ids, @object_id)

      state =
        Room.apply(state, %ObjectTakenFromRoom{
          room_id: @room_id,
          player_id: 1,
          object_id: @object_id
        })

      refute MapSet.member?(state.object_ids, @object_id)

      state =
        Room.apply(state, %ObjectDroppedInRoom{
          room_id: @room_id,
          player_id: 1,
          object_id: @object_id
        })

      assert MapSet.member?(state.object_ids, @object_id)
    end
  end

  describe "SpawnNPC" do
    test "spawns an NPC into an existing room" do
      assert %NPCSpawnedInRoom{
               room_id: @room_id,
               npc_id: @npc_id,
               name: "Garrick",
               short_description: "a wiry innkeeper",
               long_description: "A wiry man in a stained apron."
             } =
               Room.execute(created_room(), %SpawnNPC{
                 room_id: @room_id,
                 npc_id: @npc_id,
                 name: "Garrick",
                 short_description: "a wiry innkeeper",
                 long_description: "A wiry man in a stained apron."
               })
    end

    test "rejects on uninitialized room" do
      assert {:error, :room_not_found} =
               Room.execute(%Room{}, %SpawnNPC{
                 room_id: @room_id,
                 npc_id: @npc_id,
                 name: "Garrick",
                 short_description: "a wiry innkeeper",
                 long_description: "A wiry man in a stained apron."
               })
    end

    test "rejects duplicate npc_id" do
      state =
        created_room()
        |> Room.apply(%NPCSpawnedInRoom{
          room_id: @room_id,
          npc_id: @npc_id,
          name: "Garrick",
          short_description: "a wiry innkeeper",
          long_description: "A wiry man in a stained apron."
        })

      assert {:error, :npc_already_in_room} =
               Room.execute(state, %SpawnNPC{
                 room_id: @room_id,
                 npc_id: @npc_id,
                 name: "Garrick",
                 short_description: "a wiry innkeeper",
                 long_description: "A wiry man in a stained apron."
               })
    end

    test "rejects duplicate display name (case-insensitive) within the same room" do
      state =
        created_room()
        |> Room.apply(%NPCSpawnedInRoom{
          room_id: @room_id,
          npc_id: @npc_id,
          name: "Garrick",
          short_description: "a wiry innkeeper",
          long_description: "A wiry man in a stained apron."
        })

      assert {:error, :npc_name_taken_in_room} =
               Room.execute(state, %SpawnNPC{
                 room_id: @room_id,
                 npc_id: @other_npc_id,
                 name: "GARRICK",
                 short_description: "a different innkeeper",
                 long_description: "Another man."
               })
    end

    test "rejects empty long_description" do
      assert {:error, :long_description_required} =
               Room.execute(created_room(), %SpawnNPC{
                 room_id: @room_id,
                 npc_id: @npc_id,
                 name: "Garrick",
                 short_description: "a wiry innkeeper",
                 long_description: ""
               })
    end

    test "rejects empty short_description" do
      assert {:error, :short_description_required} =
               Room.execute(created_room(), %SpawnNPC{
                 room_id: @room_id,
                 npc_id: @npc_id,
                 name: "Garrick",
                 short_description: "",
                 long_description: "A wiry man in a stained apron."
               })
    end

    test "apply/2 round-trip: NPCSpawnedInRoom adds id and lowercased name to aggregate state" do
      state =
        created_room()
        |> Room.apply(%NPCSpawnedInRoom{
          room_id: @room_id,
          npc_id: @npc_id,
          name: "Garrick the Innkeeper",
          short_description: "a wiry innkeeper",
          long_description: "A wiry man in a stained apron."
        })

      assert MapSet.member?(state.npc_ids, @npc_id)
      assert MapSet.member?(state.npc_names_lower, "garrick the innkeeper")
    end
  end
end
