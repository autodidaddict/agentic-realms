defmodule AgenticRealms.World.SnapshotTest do
  @moduledoc """
  Integration test for the aggregate snapshot path enabled in issue #6.

  Records and reads aggregate snapshots through the live `World.Application`
  event store adapter (in-memory in tests) — same code path Commanded uses
  when `snapshotting:` is configured. Bypasses the projector pipeline, so
  we don't need DB/sandbox state for this to be a useful end-to-end check.
  The assertion that matters is that the `MapSet` and string-keyed map
  fields survive the JSON snapshot roundtrip; if the `JsonDecoder` impls
  regressed they'd come back as plain lists / atom-keyed maps.
  """

  use ExUnit.Case, async: true

  alias AgenticRealms.World.Application, as: WorldApp
  alias AgenticRealms.World.{Player, Room}
  alias Commanded.EventStore
  alias Commanded.EventStore.{SnapshotData, TypeProvider}

  defp record_and_read(%mod{} = state) do
    source_uuid = "snapshot-test-" <> Ecto.UUID.generate()

    snapshot = %SnapshotData{
      source_uuid: source_uuid,
      source_version: 1,
      source_type: TypeProvider.to_string(state),
      data: state,
      metadata: %{}
    }

    :ok = EventStore.record_snapshot(WorldApp, snapshot)

    {:ok, %SnapshotData{data: data, source_type: type}} =
      EventStore.read_snapshot(WorldApp, source_uuid)

    assert type == TypeProvider.to_string(state)
    assert %^mod{} = data
    data
  end

  describe "Room snapshot" do
    test "object_ids roundtrips as a MapSet" do
      object_ids = MapSet.new(["obj-a", "obj-b", "obj-c"])

      room = %Room{
        id: "room-1",
        name: "Snapshot Room",
        description: "A room snapshotted for issue #6.",
        exits: %{},
        object_ids: object_ids,
        behaviors: []
      }

      reloaded = record_and_read(room)
      assert reloaded.object_ids == object_ids
      assert MapSet.size(reloaded.object_ids) == 3
    end

    test "exits string keys survive (do not get atomized)" do
      room = %Room{
        id: "room-1",
        name: "Snapshot Room",
        description: "A room with exits.",
        exits: %{"north" => "room-2", "east" => "room-3"},
        object_ids: MapSet.new(),
        behaviors: []
      }

      reloaded = record_and_read(room)

      assert reloaded.exits == %{"north" => "room-2", "east" => "room-3"}

      assert Map.has_key?(reloaded.exits, "north"),
             "exits map must keep string keys so Map.has_key?(exits, direction) still works after rehydrate"
    end

    test "empty MapSet roundtrips" do
      room = %Room{id: "room-empty", name: "Empty", description: "."}
      reloaded = record_and_read(room)
      assert reloaded.object_ids == MapSet.new()
    end
  end

  describe "Player snapshot" do
    test "discovered_room_ids roundtrips as a MapSet" do
      discovered = MapSet.new(["room-a", "room-b", "room-c"])

      player = %Player{
        id: 42,
        current_room_id: "room-a",
        discovered_room_ids: discovered
      }

      reloaded = record_and_read(player)
      assert reloaded.discovered_room_ids == discovered
      assert reloaded.current_room_id == "room-a"
      assert reloaded.id == 42
    end

    test "empty MapSet roundtrips" do
      player = %Player{id: 1, current_room_id: "room-1"}
      reloaded = record_and_read(player)
      assert reloaded.discovered_room_ids == MapSet.new()
    end
  end
end
