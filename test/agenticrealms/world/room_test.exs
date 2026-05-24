defmodule AgenticRealms.World.RoomTest do
  use ExUnit.Case, async: true

  alias AgenticRealms.World.Room

  alias AgenticRealms.World.Commands.{
    CreateRoom,
    AddExit,
    PlaceObject,
    TakeObject,
    DropObject
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
  @legacy_npc_id "00000000-0000-0000-0000-000000000200"

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

  # Feature 008 — legacy NPCSpawnedInRoom apply/2 must remain a no-op so
  # Room aggregates with historical NPC events can rehydrate without
  # crashing. NPC state is no longer tracked on the Room aggregate; per-
  # room display name uniqueness moved to the read-model layer.
  describe "apply/2 — legacy NPCSpawnedInRoom replay compatibility (feature 008)" do
    test "applying NPCSpawnedInRoom leaves Room aggregate state unchanged" do
      before = created_room()

      after_apply =
        Room.apply(before, %NPCSpawnedInRoom{
          room_id: @room_id,
          npc_id: @legacy_npc_id,
          name: "Garrick the Innkeeper",
          short_description: "a wiry innkeeper",
          long_description: "A wiry man in a stained apron."
        })

      assert after_apply == before
    end
  end

  describe "behaviors (feature 009)" do
    @behaviors_payload [
      %{
        "trigger" => "player_entered",
        "actions" => [%{"type" => "say", "text" => "Hello."}]
      }
    ]

    test "CreateRoom carries :behaviors through to the emitted event" do
      assert %RoomCreated{behaviors: @behaviors_payload} =
               Room.execute(%Room{}, %CreateRoom{
                 room_id: @room_id,
                 name: "Test Room",
                 description: "A room.",
                 behaviors: @behaviors_payload
               })
    end

    test "apply/2 of RoomCreated with behaviors sets state.behaviors" do
      state =
        Room.apply(%Room{}, %RoomCreated{
          room_id: @room_id,
          name: "Test Room",
          description: "A room.",
          behaviors: @behaviors_payload
        })

      assert state.behaviors == @behaviors_payload
    end

    test "CreateRoom without :behaviors defaults to []" do
      assert %RoomCreated{behaviors: []} =
               Room.execute(%Room{}, %CreateRoom{
                 room_id: @room_id,
                 name: "Test Room",
                 description: "A room."
               })
    end
  end
end
