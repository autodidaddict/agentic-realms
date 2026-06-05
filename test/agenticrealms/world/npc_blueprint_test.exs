defmodule AgenticRealms.World.NPCBlueprintTest do
  @moduledoc """
  Aggregate unit tests for `AgenticRealms.World.NPCBlueprint`.

  Feature 016 — clone spawning (`SpawnNPCClone` → `NPCClonedFromBlueprint`)
  and the per-blueprint serial/clone tracking moved to the entity lifecycle
  (`World.Entity`); this aggregate now owns blueprint authoring only. Clone
  spawning behavior is covered by the entity projector + `spawn_npc_clone`
  wrapper / LiveView NPC tests.
  """

  use ExUnit.Case, async: true

  alias AgenticRealms.World.NPCBlueprint
  alias AgenticRealms.World.Commands.CreateNPCBlueprint
  alias AgenticRealms.World.Events.NPCBlueprintCreated

  @bp_id "garrick_the_innkeeper"

  defp created_blueprint(name \\ "Garrick the Innkeeper") do
    NPCBlueprint.apply(%NPCBlueprint{}, %NPCBlueprintCreated{
      blueprint_id: @bp_id,
      name: name,
      short_description: "a wiry innkeeper",
      long_description: "A wiry man in a stained apron."
    })
  end

  describe "CreateNPCBlueprint" do
    test "creates a fresh blueprint" do
      assert %NPCBlueprintCreated{
               blueprint_id: @bp_id,
               name: "Garrick the Innkeeper",
               short_description: "a wiry innkeeper",
               long_description: "A wiry man in a stained apron."
             } =
               NPCBlueprint.execute(%NPCBlueprint{}, %CreateNPCBlueprint{
                 blueprint_id: @bp_id,
                 name: "Garrick the Innkeeper",
                 short_description: "a wiry innkeeper",
                 long_description: "A wiry man in a stained apron."
               })
    end

    test "rejects creating an already-created blueprint" do
      assert {:error, :blueprint_already_exists} =
               NPCBlueprint.execute(created_blueprint(), %CreateNPCBlueprint{
                 blueprint_id: @bp_id,
                 name: "Garrick the Innkeeper",
                 short_description: "a wiry innkeeper",
                 long_description: "A wiry man in a stained apron."
               })
    end

    test "rejects empty name" do
      assert {:error, :name_required} =
               NPCBlueprint.execute(%NPCBlueprint{}, %CreateNPCBlueprint{
                 blueprint_id: @bp_id,
                 name: "",
                 short_description: "a wiry innkeeper",
                 long_description: "A wiry man in a stained apron."
               })
    end

    test "rejects empty short_description" do
      assert {:error, :short_description_required} =
               NPCBlueprint.execute(%NPCBlueprint{}, %CreateNPCBlueprint{
                 blueprint_id: @bp_id,
                 name: "Garrick the Innkeeper",
                 short_description: "",
                 long_description: "A wiry man in a stained apron."
               })
    end

    test "rejects empty long_description (FR-004)" do
      assert {:error, :long_description_required} =
               NPCBlueprint.execute(%NPCBlueprint{}, %CreateNPCBlueprint{
                 blueprint_id: @bp_id,
                 name: "Garrick the Innkeeper",
                 short_description: "a wiry innkeeper",
                 long_description: ""
               })
    end
  end

  describe "apply/2 round-trip" do
    test "NPCBlueprintCreated sets aggregate id + content fields" do
      state = created_blueprint()

      assert state.id == @bp_id
      assert state.name == "Garrick the Innkeeper"
      assert state.short_description == "a wiry innkeeper"
      assert state.long_description == "A wiry man in a stained apron."
    end
  end

  describe "behaviors (feature 009)" do
    @behaviors_payload [
      %{
        "trigger" => "player_entered",
        "actions" => [%{"type" => "say", "text" => "Welcome."}]
      },
      %{
        "trigger" => "player_left",
        "actions" => [%{"type" => "say", "text" => "Goodbye."}]
      }
    ]

    test "CreateNPCBlueprint carries :behaviors through to the emitted event" do
      assert %NPCBlueprintCreated{behaviors: @behaviors_payload} =
               NPCBlueprint.execute(%NPCBlueprint{}, %CreateNPCBlueprint{
                 blueprint_id: @bp_id,
                 name: "Garrick the Innkeeper",
                 short_description: "a wiry innkeeper",
                 long_description: "A wiry man in a stained apron.",
                 behaviors: @behaviors_payload
               })
    end

    test "apply/2 of NPCBlueprintCreated with behaviors sets state.behaviors" do
      state =
        NPCBlueprint.apply(%NPCBlueprint{}, %NPCBlueprintCreated{
          blueprint_id: @bp_id,
          name: "Garrick the Innkeeper",
          short_description: "a wiry innkeeper",
          long_description: "A wiry man in a stained apron.",
          behaviors: @behaviors_payload
        })

      assert state.behaviors == @behaviors_payload
    end

    test "CreateNPCBlueprint without :behaviors defaults to []" do
      assert %NPCBlueprintCreated{behaviors: []} =
               NPCBlueprint.execute(%NPCBlueprint{}, %CreateNPCBlueprint{
                 blueprint_id: @bp_id,
                 name: "Garrick the Innkeeper",
                 short_description: "a wiry innkeeper",
                 long_description: "A wiry man in a stained apron."
               })
    end
  end
end
