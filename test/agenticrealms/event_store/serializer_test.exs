defmodule AgenticRealms.EventStore.SerializerTest do
  @moduledoc """
  Tests for the snapshot serializer wired up in issue #6.

  The serializer is exercised at two layers:

    * `AgenticRealms.EventStore.Serializer` — used in dev/prod against the
      Postgres-backed `eventstore` adapter.
    * `Commanded.Serialization.JsonSerializer` — used in test via the
      in-memory Commanded adapter.

  Both must roundtrip the `MapSet` fields on `World.Room` (`object_ids`) and
  `World.Player` (`discovered_room_ids`) so aggregate state survives the
  snapshot path that issue #6 turns on.
  """

  use ExUnit.Case, async: true

  alias AgenticRealms.EventStore.Serializer
  alias AgenticRealms.World.{Player, Room}

  describe "Room snapshot roundtrip" do
    setup do
      room = %Room{
        id: "room-1",
        name: "Atrium",
        description: "A bright atrium.",
        exits: %{"north" => "room-2"},
        object_ids: MapSet.new(["obj-a", "obj-b", "obj-c"]),
        behaviors: [],
        region_id: "region-1",
        map_visible: true,
        elevation: 0,
        map_x: 1,
        map_y: 2
      }

      %{room: room}
    end

    test "AgenticRealms.EventStore.Serializer preserves MapSet and string-keyed exits",
         %{room: room} do
      binary = Serializer.serialize(room)
      decoded = Serializer.deserialize(binary, type: "Elixir.AgenticRealms.World.Room")

      assert %Room{} = decoded
      assert decoded.object_ids == room.object_ids
      assert decoded.exits == room.exits
      assert Map.has_key?(decoded.exits, "north")
      assert decoded.name == room.name
      assert decoded.region_id == room.region_id
    end

    test "Commanded.Serialization.JsonSerializer preserves the MapSet", %{room: room} do
      binary = Commanded.Serialization.JsonSerializer.serialize(room)

      decoded =
        Commanded.Serialization.JsonSerializer.deserialize(binary,
          type: "Elixir.AgenticRealms.World.Room"
        )

      assert %Room{} = decoded
      assert decoded.object_ids == room.object_ids
    end

    test "empty MapSet roundtrips" do
      room = %Room{id: "room-empty", name: "Empty", description: "."}

      decoded =
        room
        |> Serializer.serialize()
        |> Serializer.deserialize(type: "Elixir.AgenticRealms.World.Room")

      assert decoded.object_ids == MapSet.new()
      assert MapSet.size(decoded.object_ids) == 0
    end
  end

  describe "Player snapshot roundtrip" do
    setup do
      player = %Player{
        id: 42,
        current_room_id: "room-1",
        discovered_room_ids: MapSet.new(["room-1", "room-2", "room-3"])
      }

      %{player: player}
    end

    test "AgenticRealms.EventStore.Serializer preserves the MapSet", %{player: player} do
      decoded =
        player
        |> Serializer.serialize()
        |> Serializer.deserialize(type: "Elixir.AgenticRealms.World.Player")

      assert %Player{} = decoded
      assert decoded.discovered_room_ids == player.discovered_room_ids
      assert decoded.current_room_id == player.current_room_id
      assert decoded.id == player.id
    end

    test "Commanded.Serialization.JsonSerializer preserves the MapSet", %{player: player} do
      decoded =
        player
        |> Commanded.Serialization.JsonSerializer.serialize()
        |> Commanded.Serialization.JsonSerializer.deserialize(
          type: "Elixir.AgenticRealms.World.Player"
        )

      assert decoded.discovered_room_ids == player.discovered_room_ids
    end

    test "empty MapSet roundtrips" do
      player = %Player{id: 1, current_room_id: "room-1"}

      decoded =
        player
        |> Serializer.serialize()
        |> Serializer.deserialize(type: "Elixir.AgenticRealms.World.Player")

      assert decoded.discovered_room_ids == MapSet.new()
    end
  end

  describe "event passthrough (no JsonDecoder impl)" do
    test "existing events deserialize unchanged" do
      event = %AgenticRealms.World.Events.PlayerSpawned{
        player_id: 7,
        room_id: "room-1"
      }

      decoded =
        event
        |> Serializer.serialize()
        |> Serializer.deserialize(type: "Elixir.AgenticRealms.World.Events.PlayerSpawned")

      assert decoded == event
    end
  end

  describe "deserialize without type" do
    test "returns raw decoded JSON" do
      assert Serializer.deserialize(~s({"a":1}), []) == %{"a" => 1}
    end
  end
end
