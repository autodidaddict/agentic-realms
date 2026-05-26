defmodule AgenticRealms.World.Projections.WorldProjectorNpcReplayTest do
  @moduledoc """
  Tests for the legacy-event replay path in `WorldProjector` (feature 008
  FR-019 / FR-020 / FR-021). Exercises the projector's `handle/2` directly
  with synthesized event structs, bypassing the Commanded subscription
  layer — this isolates the projection logic from event-store + sandbox
  interactions.
  """

  use AgenticRealms.DataCase, async: false

  alias AgenticRealms.World.Events.{NPCSpawnedInRoom, NPCClonedFromBlueprint}
  alias AgenticRealms.World.Projections.{WorldProjector, SyntheticBlueprintId}
  alias AgenticRealms.World.Schemas.{Room, NPCBlueprint, NPCClone, Region}

  defp insert_region(name \\ "TestRegion") do
    Repo.insert!(%Region{
      id: Ecto.UUID.generate(),
      name: "#{name}-#{System.unique_integer([:positive])}"
    })
  end

  defp insert_room(name \\ "Test Room") do
    region = insert_region()

    Repo.insert!(%Room{
      id: Ecto.UUID.generate(),
      name: name,
      description: "A room.",
      region_id: region.id
    })
  end

  describe "legacy NPCSpawnedInRoom projection (FR-019)" do
    setup do
      room = insert_room()
      %{room: room}
    end

    test "produces a synthetic blueprint + clone with serial 1", %{room: room} do
      npc_id = Ecto.UUID.generate()

      event = %NPCSpawnedInRoom{
        room_id: room.id,
        npc_id: npc_id,
        name: "Legacy NPC",
        short_description: "a legacy npc",
        long_description: "A legacy long description."
      }

      :ok = WorldProjector.handle(event, %{})

      expected_bp_id =
        SyntheticBlueprintId.derive(
          "Legacy NPC",
          "a legacy npc",
          "A legacy long description."
        )

      bp = Repo.get(NPCBlueprint, expected_bp_id)
      assert bp.name == "Legacy NPC"
      assert bp.is_synthetic == true

      clone = Repo.get(NPCClone, npc_id)
      assert clone.blueprint_id == expected_bp_id
      assert clone.serial == 1
      assert clone.name == "Legacy NPC"
      assert clone.long_description == "A legacy long description."
      assert clone.room_id == room.id
    end

    test "two legacy events with the same payload share a synthetic blueprint and get serials 1, 2",
         %{room: room} do
      other_room = insert_room("Other Room")
      clone_id_1 = Ecto.UUID.generate()
      clone_id_2 = Ecto.UUID.generate()

      event_1 = %NPCSpawnedInRoom{
        room_id: room.id,
        npc_id: clone_id_1,
        name: "Duplicate NPC",
        short_description: "a duplicate",
        long_description: "Same long description."
      }

      event_2 = %NPCSpawnedInRoom{
        room_id: other_room.id,
        npc_id: clone_id_2,
        name: "Duplicate NPC",
        short_description: "a duplicate",
        long_description: "Same long description."
      }

      :ok = WorldProjector.handle(event_1, %{})
      :ok = WorldProjector.handle(event_2, %{})

      # Same payload → same synthetic blueprint id.
      bp_id =
        SyntheticBlueprintId.derive(
          "Duplicate NPC",
          "a duplicate",
          "Same long description."
        )

      assert Repo.get(NPCBlueprint, bp_id)
      # Both clones reference the same synthetic blueprint, with consecutive serials.
      assert Repo.get(NPCClone, clone_id_1).serial == 1
      assert Repo.get(NPCClone, clone_id_2).serial == 2
    end

    test "two legacy events with DIFFERENT payloads produce distinct synthetic blueprints",
         %{room: room} do
      event_1 = %NPCSpawnedInRoom{
        room_id: room.id,
        npc_id: Ecto.UUID.generate(),
        name: "NPC A",
        short_description: "short",
        long_description: "long"
      }

      event_2 = %NPCSpawnedInRoom{
        room_id: room.id,
        # different name → different synthetic blueprint
        npc_id: Ecto.UUID.generate(),
        name: "NPC B",
        short_description: "short",
        long_description: "long"
      }

      :ok = WorldProjector.handle(event_1, %{})
      :ok = WorldProjector.handle(event_2, %{})

      assert length(Repo.all(NPCBlueprint)) == 2
    end

    test "replaying the same legacy event twice is idempotent (FR-020)", %{room: room} do
      event = %NPCSpawnedInRoom{
        room_id: room.id,
        npc_id: Ecto.UUID.generate(),
        name: "Idempotent NPC",
        short_description: "short",
        long_description: "long"
      }

      :ok = WorldProjector.handle(event, %{})
      :ok = WorldProjector.handle(event, %{})

      assert length(Repo.all(NPCBlueprint)) == 1
      assert length(Repo.all(NPCClone)) == 1
    end
  end

  describe "new NPCClonedFromBlueprint projection" do
    setup do
      room = insert_room()

      bp_id = "test_authored_bp"

      Repo.insert!(%NPCBlueprint{
        id: bp_id,
        name: "Authored NPC",
        short_description: "short",
        long_description: "long",
        is_synthetic: false
      })

      %{room: room, blueprint_id: bp_id}
    end

    test "inserts the clone from the event's payload only (no blueprint lookup)",
         %{room: room, blueprint_id: bp_id} do
      clone_id = Ecto.UUID.generate()

      event = %NPCClonedFromBlueprint{
        blueprint_id: bp_id,
        clone_id: clone_id,
        room_id: room.id,
        serial: 1,
        name: "Authored NPC",
        short_description: "short",
        long_description: "long"
      }

      :ok = WorldProjector.handle(event, %{})

      assert clone = Repo.get(NPCClone, clone_id)
      assert clone.blueprint_id == bp_id
      assert clone.serial == 1
      assert clone.name == "Authored NPC"
    end

    test "is idempotent under double-application", %{room: room, blueprint_id: bp_id} do
      clone_id = Ecto.UUID.generate()

      event = %NPCClonedFromBlueprint{
        blueprint_id: bp_id,
        clone_id: clone_id,
        room_id: room.id,
        serial: 1,
        name: "Authored NPC",
        short_description: "short",
        long_description: "long"
      }

      :ok = WorldProjector.handle(event, %{})
      :ok = WorldProjector.handle(event, %{})

      assert length(Repo.all(NPCClone)) == 1
    end
  end

  describe "behaviors projection (feature 009)" do
    setup do
      room = insert_room("Behaviors Test Room")
      %{room: room}
    end

    @behaviors_payload [
      %{
        "trigger" => "player_entered",
        "actions" => [%{"type" => "say", "text" => "Hi."}]
      }
    ]

    test "RoomCreated projection carries behaviors onto the world_rooms row" do
      alias AgenticRealms.World.Events.RoomCreated
      alias AgenticRealms.World.Schemas.Room

      region = insert_region()
      room_id = Ecto.UUID.generate()

      :ok =
        WorldProjector.handle(
          %RoomCreated{
            room_id: room_id,
            name: "Test",
            description: "Desc",
            region_id: region.id,
            behaviors: @behaviors_payload
          },
          %{}
        )

      assert %Room{behaviors: behaviors} = Repo.get(Room, room_id)
      assert behaviors == @behaviors_payload
    end

    test "RoomCreated with default empty behaviors projects as []" do
      alias AgenticRealms.World.Events.RoomCreated
      alias AgenticRealms.World.Schemas.Room

      region = insert_region()
      room_id = Ecto.UUID.generate()

      :ok =
        WorldProjector.handle(
          %RoomCreated{
            room_id: room_id,
            name: "Test",
            description: "Desc",
            region_id: region.id
          },
          %{}
        )

      assert %Room{behaviors: []} = Repo.get(Room, room_id)
    end

    test "NPCBlueprintCreated carries behaviors onto the npc_blueprints row" do
      alias AgenticRealms.World.Events.NPCBlueprintCreated

      bp_id = "test_behaviors_bp_#{System.unique_integer([:positive])}"

      :ok =
        WorldProjector.handle(
          %NPCBlueprintCreated{
            blueprint_id: bp_id,
            name: "Test NPC",
            short_description: "short",
            long_description: "long",
            behaviors: @behaviors_payload
          },
          %{}
        )

      assert %NPCBlueprint{behaviors: behaviors, is_synthetic: false} =
               Repo.get(NPCBlueprint, bp_id)

      assert behaviors == @behaviors_payload
    end

    test "NPCClonedFromBlueprint carries behaviors onto the npc_clones row", %{room: room} do
      bp_id = "test_clone_behaviors_bp_#{System.unique_integer([:positive])}"

      Repo.insert!(%NPCBlueprint{
        id: bp_id,
        name: "Test NPC",
        short_description: "short",
        long_description: "long"
      })

      clone_id = Ecto.UUID.generate()

      :ok =
        WorldProjector.handle(
          %NPCClonedFromBlueprint{
            blueprint_id: bp_id,
            clone_id: clone_id,
            room_id: room.id,
            serial: 1,
            name: "Test NPC",
            short_description: "short",
            long_description: "long",
            behaviors: @behaviors_payload
          },
          %{}
        )

      assert %NPCClone{behaviors: behaviors} = Repo.get(NPCClone, clone_id)
      assert behaviors == @behaviors_payload
    end

    test "legacy NPCSpawnedInRoom defaults clone behaviors to []", %{room: room} do
      alias AgenticRealms.World.Events.NPCSpawnedInRoom

      npc_id = Ecto.UUID.generate()

      :ok =
        WorldProjector.handle(
          %NPCSpawnedInRoom{
            room_id: room.id,
            npc_id: npc_id,
            name: "Legacy NPC",
            short_description: "short",
            long_description: "long"
          },
          %{}
        )

      assert %NPCClone{behaviors: []} = Repo.get(NPCClone, npc_id)
    end
  end

  # Feature 010 — backward compat for `lore`. Old events serialized before
  # the `lore` field was added must still project cleanly: the projector
  # must default `lore` to "" rather than crashing on a missing key.
  describe "lore backward-compat (feature 010)" do
    setup do
      %{room: insert_room()}
    end

    test "NPCBlueprintCreated without lore projects with lore = \"\"" do
      alias AgenticRealms.World.Events.NPCBlueprintCreated

      bp_id = "lore_compat_bp_#{System.unique_integer([:positive])}"

      # Build the struct WITHOUT a `:lore` key by funneling through the
      # struct's defstruct default (the field exists in the source but
      # the default of "" simulates an old payload).
      event = %NPCBlueprintCreated{
        blueprint_id: bp_id,
        name: "Old Blueprint",
        short_description: "short",
        long_description: "long"
      }

      :ok = WorldProjector.handle(event, %{})

      assert %NPCBlueprint{lore: ""} = Repo.get(NPCBlueprint, bp_id)
    end

    test "NPCClonedFromBlueprint without lore projects with lore = \"\"", %{room: room} do
      alias AgenticRealms.World.Events.{NPCBlueprintCreated, NPCClonedFromBlueprint}

      bp_id = "lore_compat_clone_bp_#{System.unique_integer([:positive])}"
      clone_id = Ecto.UUID.generate()

      :ok =
        WorldProjector.handle(
          %NPCBlueprintCreated{
            blueprint_id: bp_id,
            name: "BP",
            short_description: "s",
            long_description: "l"
          },
          %{}
        )

      :ok =
        WorldProjector.handle(
          %NPCClonedFromBlueprint{
            blueprint_id: bp_id,
            clone_id: clone_id,
            room_id: room.id,
            serial: 1,
            name: "Clone",
            short_description: "s",
            long_description: "l"
          },
          %{}
        )

      assert %NPCClone{lore: ""} = Repo.get(NPCClone, clone_id)
    end
  end
end
