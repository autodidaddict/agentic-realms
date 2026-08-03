defmodule AgenticRealms.World.EntityTest do
  use ExUnit.Case, async: true

  alias AgenticRealms.World.{Entity, ContainerRef}
  alias AgenticRealms.World.Commands.{CloneEntity, MoveEntity, EditEntity}
  alias AgenticRealms.World.Events.{EntityCloned, EntityMoved, EntityEdited}

  defp in_room(id \\ "e1", room \\ "r1") do
    %Entity{}
    |> Entity.apply(%EntityCloned{entity_id: id, kind: :object, fields: %{}})
    |> Entity.apply(%EntityMoved{
      entity_id: id,
      from: ContainerRef.void(),
      to: ContainerRef.room(room)
    })
  end

  describe "execute/2 — CloneEntity" do
    test "fresh aggregate emits EntityCloned with normalized kind" do
      cmd = %CloneEntity{entity_id: "e1", kind: :object, fields: %{"name" => "lantern"}}

      assert %EntityCloned{entity_id: "e1", kind: :object, fields: %{"name" => "lantern"}} =
               Entity.execute(%Entity{}, cmd)
    end

    test "accepts string kind and normalizes to atom" do
      cmd = %CloneEntity{entity_id: "n1", kind: "npc", fields: %{}}
      assert %EntityCloned{kind: :npc} = Entity.execute(%Entity{}, cmd)
    end

    test "rejects an unsupported kind" do
      cmd = %CloneEntity{entity_id: "e1", kind: :widget, fields: %{}}
      assert {:error, :unsupported_kind} = Entity.execute(%Entity{}, cmd)
    end

    test "re-clone of an existing entity is refused" do
      cmd = %CloneEntity{entity_id: "e1", kind: :object, fields: %{}}
      assert {:error, :already_exists} = Entity.execute(in_room(), cmd)
    end
  end

  describe "execute/2 — MoveEntity" do
    test "uncreated entity → :not_found" do
      cmd = %MoveEntity{
        entity_id: "e1",
        expected_from: ContainerRef.void(),
        to: ContainerRef.room("r1")
      }

      assert {:error, :not_found} = Entity.execute(%Entity{}, cmd)
    end

    test "real move emits EntityMoved from the current container to the destination" do
      cmd = %MoveEntity{
        entity_id: "e1",
        expected_from: ContainerRef.room("r1"),
        to: ContainerRef.player(7),
        cause: :taken
      }

      assert %EntityMoved{
               entity_id: "e1",
               from: %ContainerRef{type: :room, id: "r1"},
               to: %ContainerRef{type: :player, id: 7},
               cause: :taken
             } = Entity.execute(in_room(), cmd)
    end

    test "no-op move (to == current container) → :ok, no event" do
      cmd = %MoveEntity{
        entity_id: "e1",
        expected_from: ContainerRef.room("r1"),
        to: ContainerRef.room("r1")
      }

      assert :ok = Entity.execute(in_room(), cmd)
    end

    test "stale expected_from → :container_conflict (not silently applied)" do
      cmd = %MoveEntity{
        entity_id: "e1",
        expected_from: ContainerRef.room("r2"),
        to: ContainerRef.player(9),
        cause: :taken
      }

      assert {:error, :container_conflict} = Entity.execute(in_room(), cmd)
    end

    test "unsupported destination container type is refused" do
      cmd = %MoveEntity{
        entity_id: "e1",
        expected_from: ContainerRef.room("r1"),
        to: %ContainerRef{type: :bogus, id: "x"}
      }

      assert {:error, :unsupported_container} = Entity.execute(in_room(), cmd)
    end

    test "container_conflict takes precedence only after type + no-op checks" do
      cmd = %MoveEntity{
        entity_id: "e1",
        expected_from: ContainerRef.void(),
        to: ContainerRef.room("r2"),
        cause: :relocated
      }

      assert {:error, :container_conflict} = Entity.execute(in_room(), cmd)
    end
  end

  describe "execute/2 — EditEntity" do
    test "uncreated entity → :not_found" do
      assert {:error, :not_found} =
               Entity.execute(%Entity{}, %EditEntity{
                 entity_id: "e1",
                 fields_changed: %{name: "x"}
               })
    end

    test "no-op diff → :ok, no event" do
      assert :ok = Entity.execute(in_room(), %EditEntity{entity_id: "e1", fields_changed: %{}})
    end

    test "real diff emits EntityEdited" do
      assert %EntityEdited{entity_id: "e1", fields_changed: %{name: "brass lantern"}} =
               Entity.execute(in_room(), %EditEntity{
                 entity_id: "e1",
                 fields_changed: %{name: "brass lantern"}
               })
    end
  end

  describe "apply/2 — state reconstruction (replay)" do
    test "EntityCloned sets id/kind and puts the entity in the void" do
      state = Entity.apply(%Entity{}, %EntityCloned{entity_id: "e1", kind: :npc, fields: %{}})
      assert %Entity{id: "e1", kind: :npc, container: %ContainerRef{type: :void, id: nil}} = state
    end

    test "EntityMoved updates the current container" do
      assert %Entity{container: %ContainerRef{type: :room, id: "r1"}} = in_room()
    end

    test "EntityMoved normalizes a string-keyed `to` (replayed-from-store form)" do
      state =
        %Entity{}
        |> Entity.apply(%EntityCloned{entity_id: "e1", kind: :object, fields: %{}})
        |> Entity.apply(%EntityMoved{
          entity_id: "e1",
          from: %{"type" => "void", "id" => nil},
          to: %{"type" => "player", "id" => 7}
        })

      assert %Entity{container: %ContainerRef{type: :player, id: 7}} = state
    end

    test "EntityEdited leaves aggregate state unchanged" do
      assert in_room() ==
               Entity.apply(in_room(), %EntityEdited{
                 entity_id: "e1",
                 fields_changed: %{name: "x"}
               })
    end
  end
end
