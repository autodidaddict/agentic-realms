defmodule AgenticRealms.World.BlueprintTest do
  @moduledoc """
  Aggregate unit tests for the unified `AgenticRealms.World.Blueprint`
  (feature 015) — folds the former ObjectBlueprint + NPCBlueprint aggregate
  tests. Covers create (both kinds), the revision'd optimistic-lock edit, and
  the apply/2 round-trip.
  """

  use ExUnit.Case, async: true

  alias AgenticRealms.World.Blueprint
  alias AgenticRealms.World.Commands.{CreateBlueprint, EditBlueprint}
  alias AgenticRealms.World.Events.{BlueprintCreated, BlueprintEdited}

  defp created_state(overrides \\ %{}) do
    event =
      struct(
        %BlueprintCreated{
          blueprint_id: "test_chest",
          kind: "object",
          name: "test chest",
          short_description: "a small chest",
          long_description: "A small wooden chest.",
          fixed: false,
          revision: 1
        },
        overrides
      )

    Blueprint.apply(%Blueprint{}, event)
  end

  describe "execute/2 — CreateBlueprint (object)" do
    test "creates an object blueprint at revision 1" do
      assert %BlueprintCreated{kind: "object", name: "brass chest", fixed: true, revision: 1} =
               Blueprint.execute(%Blueprint{}, %CreateBlueprint{
                 blueprint_id: "brass_chest",
                 kind: "object",
                 name: "brass chest",
                 short_description: "a brass-bound chest",
                 long_description: "A weather-beaten brass-bound chest.",
                 fixed: true
               })
    end

    test "rejects creating an already-created blueprint" do
      assert {:error, :blueprint_already_exists} =
               Blueprint.execute(created_state(), %CreateBlueprint{
                 blueprint_id: "test_chest",
                 kind: "object",
                 name: "x",
                 short_description: "y",
                 long_description: "z"
               })
    end

    for {field, value} <- [
          {:name, ""},
          {:short_description, ""},
          {:long_description, ""}
        ] do
      test "rejects empty #{field}" do
        attrs =
          %{
            blueprint_id: "c",
            kind: "object",
            name: "n",
            short_description: "s",
            long_description: "l"
          }
          |> Map.put(unquote(field), unquote(value))

        assert {:error, _} = Blueprint.execute(%Blueprint{}, struct(CreateBlueprint, attrs))
      end
    end
  end

  describe "execute/2 — CreateBlueprint (npc)" do
    test "creates an npc blueprint carrying lore/behaviors/behavior_groups/quests, revision 1" do
      behaviors = [
        %{"trigger" => "player_entered", "actions" => [%{"type" => "say", "text" => "hi"}]}
      ]

      assert %BlueprintCreated{
               kind: "npc",
               lore: "wary",
               behavior_groups: ["greeter"],
               behaviors: ^behaviors,
               revision: 1
             } =
               Blueprint.execute(%Blueprint{}, %CreateBlueprint{
                 blueprint_id: "garrick",
                 kind: "npc",
                 name: "Garrick",
                 short_description: "a gruff innkeeper",
                 long_description: "A wiry man in a stained apron.",
                 lore: "wary",
                 behaviors: behaviors,
                 behavior_groups: ["greeter"]
               })
    end
  end

  describe "execute/2 — EditBlueprint" do
    test "matching revision + field-changing diff emits BlueprintEdited at N+1" do
      assert %BlueprintEdited{
               blueprint_id: "test_chest",
               revision: 2,
               fields_changed: %{short_description: "a brass-bound chest"}
             } =
               Blueprint.execute(created_state(), %EditBlueprint{
                 blueprint_id: "test_chest",
                 wizard_id: 1,
                 expected_revision: 1,
                 fields_changed: %{short_description: "a brass-bound chest"}
               })
    end

    test "npc-only fields (lore, behavior_groups, behaviors) are editable" do
      state = created_state(%{kind: "npc"})

      assert %BlueprintEdited{revision: 2, fields_changed: %{lore: "now brave"}} =
               Blueprint.execute(state, %EditBlueprint{
                 blueprint_id: "test_chest",
                 wizard_id: 1,
                 expected_revision: 1,
                 fields_changed: %{lore: "now brave"}
               })
    end

    test "matching revision + no-op diff returns :ok with no event" do
      state = created_state()

      assert :ok =
               Blueprint.execute(state, %EditBlueprint{
                 blueprint_id: "test_chest",
                 wizard_id: 1,
                 expected_revision: 1,
                 fields_changed: %{name: state.name, short_description: state.short_description}
               })
    end

    test "stale revision returns :stale_revision" do
      assert {:error, :stale_revision} =
               Blueprint.execute(created_state(), %EditBlueprint{
                 blueprint_id: "test_chest",
                 wizard_id: 1,
                 expected_revision: 99,
                 fields_changed: %{name: "renamed chest"}
               })
    end

    test "an unknown field is rejected (:invalid_field)" do
      assert {:error, :invalid_field} =
               Blueprint.execute(created_state(), %EditBlueprint{
                 blueprint_id: "test_chest",
                 wizard_id: 1,
                 expected_revision: 1,
                 fields_changed: %{bogus: "x"}
               })
    end

    test "editing before creation returns :blueprint_not_found" do
      assert {:error, :blueprint_not_found} =
               Blueprint.execute(%Blueprint{}, %EditBlueprint{
                 blueprint_id: "test_chest",
                 wizard_id: 1,
                 expected_revision: 1,
                 fields_changed: %{name: "x"}
               })
    end
  end

  describe "apply/2 round-trip" do
    test "BlueprintCreated sets id/kind/content fields" do
      state = created_state(%{kind: "npc", lore: "grim", behavior_groups: ["greeter"]})

      assert state.id == "test_chest"
      assert state.kind == "npc"
      assert state.lore == "grim"
      assert state.behavior_groups == ["greeter"]
      assert state.revision == 1
    end

    test "BlueprintEdited merges the sparse diff and bumps revision" do
      state = created_state()

      edited =
        Blueprint.apply(state, %BlueprintEdited{
          blueprint_id: "test_chest",
          fields_changed: %{name: "renamed"},
          revision: 2
        })

      assert edited.name == "renamed"
      assert edited.revision == 2
    end
  end
end
