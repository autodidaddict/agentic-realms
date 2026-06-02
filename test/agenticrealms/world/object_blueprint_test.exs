defmodule AgenticRealms.World.ObjectBlueprintTest do
  use ExUnit.Case, async: true

  alias AgenticRealms.World.ObjectBlueprint
  alias AgenticRealms.World.Commands.CreateObjectBlueprint
  alias AgenticRealms.World.Events.ObjectBlueprintCreated

  @valid_cmd %CreateObjectBlueprint{
    blueprint_id: "brass_chest",
    wizard_id: 1,
    name: "brass chest",
    short_description: "a brass-bound chest",
    long_description: "A weather-beaten brass-bound chest.",
    fixed: true
  }

  describe "execute/2 — CreateObjectBlueprint" do
    test "fresh aggregate emits ObjectBlueprintCreated at revision 1" do
      assert %ObjectBlueprintCreated{
               blueprint_id: "brass_chest",
               kind: "object",
               name: "brass chest",
               short_description: "a brass-bound chest",
               long_description: "A weather-beaten brass-bound chest.",
               fixed: true,
               revision: 1
             } = ObjectBlueprint.execute(%ObjectBlueprint{}, @valid_cmd)
    end

    test "already-created aggregate refuses with :blueprint_already_exists" do
      state = %ObjectBlueprint{id: "brass_chest", revision: 1}
      assert {:error, :blueprint_already_exists} = ObjectBlueprint.execute(state, @valid_cmd)
    end

    test "rejects blank name" do
      assert {:error, :name_required} =
               ObjectBlueprint.execute(%ObjectBlueprint{}, %{@valid_cmd | name: ""})
    end

    test "rejects blank short description" do
      assert {:error, :short_description_required} =
               ObjectBlueprint.execute(%ObjectBlueprint{}, %{@valid_cmd | short_description: nil})
    end

    test "rejects blank long description" do
      assert {:error, :long_description_required} =
               ObjectBlueprint.execute(%ObjectBlueprint{}, %{@valid_cmd | long_description: ""})
    end
  end

  describe "apply/2 — ObjectBlueprintCreated" do
    test "populates all fields and sets revision to 1" do
      event = ObjectBlueprint.execute(%ObjectBlueprint{}, @valid_cmd)
      state = ObjectBlueprint.apply(%ObjectBlueprint{}, event)

      assert %ObjectBlueprint{
               id: "brass_chest",
               kind: "object",
               name: "brass chest",
               short_description: "a brass-bound chest",
               long_description: "A weather-beaten brass-bound chest.",
               fixed: true,
               revision: 1
             } = state
    end

    test "execute → apply rehydration sets the aggregate into the post-create state" do
      event = ObjectBlueprint.execute(%ObjectBlueprint{}, @valid_cmd)
      state = ObjectBlueprint.apply(%ObjectBlueprint{}, event)

      assert {:error, :blueprint_already_exists} = ObjectBlueprint.execute(state, @valid_cmd)
    end
  end
end
