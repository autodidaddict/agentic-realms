defmodule AgenticRealms.World.Projections.WorldProjectorObjectReplayTest do
  @moduledoc """
  Backward-compatibility test for the Object `behaviors` field (feature 011).

  Old `ObjectPlacedInRoom` events serialized BEFORE the field was added
  must still project cleanly. Mirrors the patterns established in
  feature 009 (`behaviors` on rooms/NPCs) and feature 010 (`lore` on NPCs).
  """

  use AgenticRealms.DataCase, async: false

  alias AgenticRealms.World.Events.ObjectPlacedInRoom
  alias AgenticRealms.World.Projections.WorldProjector
  alias AgenticRealms.World.Schemas.{Object, Room}

  defp insert_room do
    Repo.insert!(%Room{
      id: Ecto.UUID.generate(),
      name: "Test Room",
      description: "A room.",
      region_id: AgenticRealms.DataCase.insert_test_region()
    })
  end

  describe "Object behaviors backward-compat (feature 011)" do
    setup do
      %{room: insert_room()}
    end

    test "ObjectPlacedInRoom WITHOUT behaviors projects with behaviors = []", %{room: room} do
      object_id = Ecto.UUID.generate()

      # Construct the event WITHOUT the `behaviors` field by relying on the
      # struct's default (which simulates an old event payload).
      event = %ObjectPlacedInRoom{
        room_id: room.id,
        object_id: object_id,
        name: "Test Object",
        short_description: "a test object",
        long_description: "A test object for backward-compat verification.",
        fixed: false
      }

      :ok = WorldProjector.handle(event, %{})

      assert %Object{behaviors: []} = Repo.get(Object, object_id)
    end

    test "ObjectPlacedInRoom WITH behaviors projects with the supplied list", %{room: room} do
      object_id = Ecto.UUID.generate()

      behaviors = [
        %{
          "trigger" => "tick",
          "interval_ms" => 1_000,
          "actions" => [%{"type" => "say", "text" => "tick"}]
        }
      ]

      event = %ObjectPlacedInRoom{
        room_id: room.id,
        object_id: object_id,
        name: "Ticker",
        short_description: "a ticking object",
        long_description: "An object that ticks.",
        fixed: false,
        behaviors: behaviors
      }

      :ok = WorldProjector.handle(event, %{})

      assert %Object{behaviors: ^behaviors} = Repo.get(Object, object_id)
    end
  end
end
