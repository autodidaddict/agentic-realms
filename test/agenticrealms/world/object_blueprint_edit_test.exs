defmodule AgenticRealms.World.ObjectBlueprintEditTest do
  use ExUnit.Case, async: true

  alias AgenticRealms.World.ObjectBlueprint
  alias AgenticRealms.World.Commands.{CreateObjectBlueprint, EditObjectBlueprint}
  alias AgenticRealms.World.Events.{ObjectBlueprintCreated, ObjectBlueprintEdited}

  defp created_state do
    event = %ObjectBlueprintCreated{
      blueprint_id: "test_chest",
      kind: "object",
      name: "test chest",
      short_description: "a small chest",
      long_description: "A small wooden chest.",
      fixed: false,
      revision: 1
    }

    ObjectBlueprint.apply(%ObjectBlueprint{}, event)
  end

  describe "execute/2 — EditObjectBlueprint" do
    test "matching revision + field-changing diff emits ObjectBlueprintEdited at N+1" do
      state = created_state()

      cmd = %EditObjectBlueprint{
        blueprint_id: "test_chest",
        wizard_id: 1,
        expected_revision: 1,
        fields_changed: %{short_description: "a brass-bound chest"}
      }

      assert %ObjectBlueprintEdited{
               blueprint_id: "test_chest",
               revision: 2,
               fields_changed: %{short_description: "a brass-bound chest"}
             } = ObjectBlueprint.execute(state, cmd)
    end

    test "matching revision + no-op diff returns :ok with no event (FR-008)" do
      state = created_state()

      cmd = %EditObjectBlueprint{
        blueprint_id: "test_chest",
        wizard_id: 1,
        expected_revision: 1,
        fields_changed: %{name: state.name, short_description: state.short_description}
      }

      assert :ok = ObjectBlueprint.execute(state, cmd)
    end

    test "stale revision returns :stale_revision (FR-020a; wrapper attaches current revision)" do
      state = created_state()

      cmd = %EditObjectBlueprint{
        blueprint_id: "test_chest",
        wizard_id: 1,
        expected_revision: 99,
        fields_changed: %{name: "renamed chest"}
      }

      # Aggregate returns a 2-tuple because Commanded only allows
      # {:error, term} out of execute/2. The Commands wrapper re-reads
      # the blueprint's current revision and attaches it as a
      # `current_revision:` opt for the LiveView.
      assert {:error, :stale_revision} = ObjectBlueprint.execute(state, cmd)
    end

    test "edit against uninitialized aggregate returns :blueprint_not_found" do
      cmd = %EditObjectBlueprint{
        blueprint_id: "x",
        wizard_id: 1,
        expected_revision: 1,
        fields_changed: %{name: "x"}
      }

      assert {:error, :blueprint_not_found} = ObjectBlueprint.execute(%ObjectBlueprint{}, cmd)
    end

    test "invalid field key returns :invalid_field" do
      state = created_state()

      cmd = %EditObjectBlueprint{
        blueprint_id: "test_chest",
        wizard_id: 1,
        expected_revision: 1,
        fields_changed: %{name: "ok", behaviors: []}
      }

      assert {:error, :invalid_field} = ObjectBlueprint.execute(state, cmd)
    end

    test "fields_changed in emitted event drops fields that already equal current state" do
      state = created_state()

      cmd = %EditObjectBlueprint{
        blueprint_id: "test_chest",
        wizard_id: 1,
        expected_revision: 1,
        fields_changed: %{
          name: state.name,
          short_description: "a brass-bound chest"
        }
      }

      event = ObjectBlueprint.execute(state, cmd)
      assert Map.keys(event.fields_changed) == [:short_description]
    end
  end

  describe "apply/2 — ObjectBlueprintEdited" do
    test "applies the diff and bumps revision" do
      state = created_state()

      event = %ObjectBlueprintEdited{
        blueprint_id: "test_chest",
        fields_changed: %{short_description: "a brass-bound chest"},
        revision: 2
      }

      new_state = ObjectBlueprint.apply(state, event)
      assert new_state.revision == 2
      assert new_state.short_description == "a brass-bound chest"
      assert new_state.name == state.name
    end

    test "execute → apply round-trip leaves the aggregate ready for the next edit" do
      state = created_state()

      event =
        ObjectBlueprint.execute(state, %EditObjectBlueprint{
          blueprint_id: "test_chest",
          wizard_id: 1,
          expected_revision: 1,
          fields_changed: %{short_description: "a brass-bound chest"}
        })

      next = ObjectBlueprint.apply(state, event)

      # Re-edit against the updated state passes (expected_revision: 2).
      assert %ObjectBlueprintEdited{revision: 3} =
               ObjectBlueprint.execute(next, %EditObjectBlueprint{
                 blueprint_id: "test_chest",
                 wizard_id: 1,
                 expected_revision: 2,
                 fields_changed: %{long_description: "Heavier than it looks."}
               })
    end
  end

  describe "create vs edit interaction" do
    test "Create against an already-created aggregate refuses" do
      state = created_state()

      cmd = %CreateObjectBlueprint{
        blueprint_id: "test_chest",
        wizard_id: 1,
        name: "x",
        short_description: "y",
        long_description: "z"
      }

      assert {:error, :blueprint_already_exists} = ObjectBlueprint.execute(state, cmd)
    end
  end
end
