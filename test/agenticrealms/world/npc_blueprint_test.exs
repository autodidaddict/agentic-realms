defmodule AgenticRealms.World.NPCBlueprintTest do
  @moduledoc """
  Aggregate unit tests for `AgenticRealms.World.NPCBlueprint` (feature 008).
  Pure aggregate semantics — no Repo, no projector, no Commanded dispatch.
  """

  use ExUnit.Case, async: true

  alias AgenticRealms.World.NPCBlueprint
  alias AgenticRealms.World.Commands.{CreateNPCBlueprint, SpawnNPCClone}
  alias AgenticRealms.World.Events.{NPCBlueprintCreated, NPCClonedFromBlueprint}

  @bp_id "garrick_the_innkeeper"
  @clone_id "00000000-0000-0000-0000-000000000100"
  @other_clone_id "00000000-0000-0000-0000-000000000101"
  @room_id "00000000-0000-4000-8000-000000000001"

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

  describe "SpawnNPCClone" do
    test "rejects spawn against an uninitialized blueprint" do
      assert {:error, :blueprint_not_found} =
               NPCBlueprint.execute(%NPCBlueprint{}, %SpawnNPCClone{
                 blueprint_id: @bp_id,
                 clone_id: @clone_id,
                 room_id: @room_id
               })
    end

    test "happy path emits NPCClonedFromBlueprint with serial 1 and materialized data" do
      assert %NPCClonedFromBlueprint{
               blueprint_id: @bp_id,
               clone_id: @clone_id,
               room_id: @room_id,
               serial: 1,
               name: "Garrick the Innkeeper",
               short_description: "a wiry innkeeper",
               long_description: "A wiry man in a stained apron."
             } =
               NPCBlueprint.execute(created_blueprint(), %SpawnNPCClone{
                 blueprint_id: @bp_id,
                 clone_id: @clone_id,
                 room_id: @room_id
               })
    end

    test "stamps the aggregate's current state into the event (full-copy)" do
      # The aggregate's state has these values; the event MUST carry them
      # verbatim — this is the full-copy materialization moment.
      state =
        NPCBlueprint.apply(%NPCBlueprint{}, %NPCBlueprintCreated{
          blueprint_id: @bp_id,
          name: "Original Garrick",
          short_description: "original short",
          long_description: "original long"
        })

      assert %NPCClonedFromBlueprint{
               name: "Original Garrick",
               short_description: "original short",
               long_description: "original long"
             } =
               NPCBlueprint.execute(state, %SpawnNPCClone{
                 blueprint_id: @bp_id,
                 clone_id: @clone_id,
                 room_id: @room_id
               })
    end

    test "rejects duplicate clone_id" do
      state =
        created_blueprint()
        |> NPCBlueprint.apply(%NPCClonedFromBlueprint{
          blueprint_id: @bp_id,
          clone_id: @clone_id,
          room_id: @room_id,
          serial: 1,
          name: "Garrick the Innkeeper",
          short_description: "a wiry innkeeper",
          long_description: "A wiry man in a stained apron."
        })

      assert {:error, :clone_id_already_used} =
               NPCBlueprint.execute(state, %SpawnNPCClone{
                 blueprint_id: @bp_id,
                 clone_id: @clone_id,
                 room_id: @room_id
               })
    end

    test "serial monotonicity across N spawns" do
      state =
        created_blueprint()
        |> NPCBlueprint.apply(%NPCClonedFromBlueprint{
          blueprint_id: @bp_id,
          clone_id: @clone_id,
          room_id: @room_id,
          serial: 1,
          name: "Garrick the Innkeeper",
          short_description: "a wiry innkeeper",
          long_description: "A wiry man in a stained apron."
        })

      # Second spawn must emit serial: 2.
      assert %NPCClonedFromBlueprint{serial: 2} =
               NPCBlueprint.execute(state, %SpawnNPCClone{
                 blueprint_id: @bp_id,
                 clone_id: @other_clone_id,
                 room_id: @room_id
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
      assert state.next_serial == 1
      assert state.clone_ids == MapSet.new()
    end

    test "NPCClonedFromBlueprint increments next_serial and tracks clone_id" do
      state =
        created_blueprint()
        |> NPCBlueprint.apply(%NPCClonedFromBlueprint{
          blueprint_id: @bp_id,
          clone_id: @clone_id,
          room_id: @room_id,
          serial: 1,
          name: "Garrick the Innkeeper",
          short_description: "a wiry innkeeper",
          long_description: "A wiry man in a stained apron."
        })

      assert state.next_serial == 2
      assert MapSet.member?(state.clone_ids, @clone_id)
    end

    test "applying multiple NPCClonedFromBlueprint events keeps serial monotonic" do
      state =
        created_blueprint()
        |> NPCBlueprint.apply(%NPCClonedFromBlueprint{
          blueprint_id: @bp_id,
          clone_id: @clone_id,
          room_id: @room_id,
          serial: 1,
          name: "Garrick the Innkeeper",
          short_description: "a wiry innkeeper",
          long_description: "A wiry man in a stained apron."
        })
        |> NPCBlueprint.apply(%NPCClonedFromBlueprint{
          blueprint_id: @bp_id,
          clone_id: @other_clone_id,
          room_id: @room_id,
          serial: 2,
          name: "Garrick the Innkeeper",
          short_description: "a wiry innkeeper",
          long_description: "A wiry man in a stained apron."
        })

      assert state.next_serial == 3
      assert MapSet.member?(state.clone_ids, @clone_id)
      assert MapSet.member?(state.clone_ids, @other_clone_id)
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

    test "SpawnNPCClone stamps blueprint behaviors into the emitted event (full-copy)" do
      state =
        NPCBlueprint.apply(%NPCBlueprint{}, %NPCBlueprintCreated{
          blueprint_id: @bp_id,
          name: "Garrick the Innkeeper",
          short_description: "a wiry innkeeper",
          long_description: "A wiry man in a stained apron.",
          behaviors: @behaviors_payload
        })

      assert %NPCClonedFromBlueprint{behaviors: @behaviors_payload} =
               NPCBlueprint.execute(state, %SpawnNPCClone{
                 blueprint_id: @bp_id,
                 clone_id: @clone_id,
                 room_id: @room_id
               })
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
