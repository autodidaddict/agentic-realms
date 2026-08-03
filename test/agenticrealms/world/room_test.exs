defmodule AgenticRealms.World.RoomTest do
  use ExUnit.Case, async: true

  alias AgenticRealms.World.Room
  alias AgenticRealms.World.Commands.{CreateRoom, AddExit}
  alias AgenticRealms.World.Events.{RoomCreated, ExitAdded}

  @room_id "00000000-0000-0000-0000-000000000001"
  @target_id "00000000-0000-0000-0000-000000000002"
  @region_id "00000000-0000-0000-0000-000000000900"

  defp created_room do
    Room.apply(%Room{}, %RoomCreated{
      room_id: @room_id,
      name: "Test Room",
      description: "A room.",
      region_id: @region_id
    })
  end

  describe "CreateRoom" do
    test "creates a fresh room" do
      assert %RoomCreated{room_id: @room_id, name: "Test Room"} =
               Room.execute(%Room{}, %CreateRoom{
                 room_id: @room_id,
                 name: "Test Room",
                 description: "A room.",
                 region_id: @region_id
               })
    end

    test "rejects creating an already-created room" do
      assert {:error, :room_already_exists} =
               Room.execute(created_room(), %CreateRoom{
                 room_id: @room_id,
                 name: "Test Room",
                 description: "A room.",
                 region_id: @region_id
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
  end

  describe "behaviors" do
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
                 region_id: @region_id,
                 behaviors: @behaviors_payload
               })
    end

    test "apply/2 of RoomCreated with behaviors sets state.behaviors" do
      state =
        Room.apply(%Room{}, %RoomCreated{
          room_id: @room_id,
          name: "Test Room",
          description: "A room.",
          region_id: @region_id,
          behaviors: @behaviors_payload
        })

      assert state.behaviors == @behaviors_payload
    end

    test "CreateRoom without :behaviors defaults to []" do
      assert %RoomCreated{behaviors: []} =
               Room.execute(%Room{}, %CreateRoom{
                 room_id: @room_id,
                 name: "Test Room",
                 description: "A room.",
                 region_id: @region_id
               })
    end
  end
end
