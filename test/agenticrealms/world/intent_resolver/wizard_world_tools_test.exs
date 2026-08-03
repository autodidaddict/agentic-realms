defmodule AgenticRealms.World.IntentResolver.WizardWorldToolsTest do
  use ExUnit.Case, async: true

  alias AgenticRealms.World.IntentResolver

  describe "parse_wizard_world_response/1" do
    test "extracts a freeform Object draft from a single manifest_object_freeform tool_use" do
      response = %{
        "content" => [
          %{
            "type" => "tool_use",
            "name" => "manifest_object_freeform",
            "input" => %{
              "name" => "clay pot",
              "short_description" => "a small clay pot",
              "long_description" => "A small clay pot, half-empty of dry barley.",
              "fixed" => false
            }
          }
        ]
      }

      assert {:ok,
              {:freeform_object,
               %{
                 name: "clay pot",
                 short_description: "a small clay pot",
                 long_description: "A small clay pot, half-empty of dry barley.",
                 fixed: false
               }}} = IntentResolver.parse_wizard_world_response(response)
    end

    test "defaults fixed to false when omitted" do
      response = %{
        "content" => [
          %{
            "type" => "tool_use",
            "name" => "manifest_object_freeform",
            "input" => %{
              "name" => "lantern",
              "short_description" => "a brass lantern",
              "long_description" => "A tarnished brass oil lantern, wick blackened."
            }
          }
        ]
      }

      assert {:ok, {:freeform_object, %{fixed: false}}} =
               IntentResolver.parse_wizard_world_response(response)
    end

    test "treats a refuse tool_use as an error with the model's message" do
      response = %{
        "content" => [
          %{
            "type" => "tool_use",
            "name" => "refuse",
            "input" => %{"message" => "That's an archetype, not a one-off."}
          }
        ]
      }

      assert {:error, "That's an archetype, not a one-off."} =
               IntentResolver.parse_wizard_world_response(response)
    end

    test "rejects unknown tool name" do
      response = %{
        "content" => [
          %{
            "type" => "tool_use",
            "name" => "draft_object_blueprint",
            "input" => %{"name" => "x"}
          }
        ]
      }

      assert {:error, _} = IntentResolver.parse_wizard_world_response(response)
    end

    test "rejects draft with missing required field" do
      response = %{
        "content" => [
          %{
            "type" => "tool_use",
            "name" => "manifest_object_freeform",
            "input" => %{"name" => "x", "short_description" => "y"}
          }
        ]
      }

      assert {:error, _} = IntentResolver.parse_wizard_world_response(response)
    end

    test "rejects multi-tool responses" do
      response = %{
        "content" => [
          %{"type" => "tool_use", "name" => "refuse", "input" => %{"message" => "a"}},
          %{"type" => "tool_use", "name" => "refuse", "input" => %{"message" => "b"}}
        ]
      }

      assert {:error, _} = IntentResolver.parse_wizard_world_response(response)
    end

    test "extracts a freeform NPC draft (incl. lore) from manifest_npc_freeform" do
      response = %{
        "content" => [
          %{
            "type" => "tool_use",
            "name" => "manifest_npc_freeform",
            "input" => %{
              "name" => "a nervous courier",
              "short_description" => "a nervous courier",
              "long_description" => "A wiry courier catching his breath by the door.",
              "lore" => "Carries a sealed letter he must not lose."
            }
          }
        ]
      }

      assert {:ok,
              {:freeform_npc,
               %{
                 name: "a nervous courier",
                 short_description: "a nervous courier",
                 long_description: "A wiry courier catching his breath by the door.",
                 lore: "Carries a sealed letter he must not lose.",
                 fixed: false
               }}} = IntentResolver.parse_wizard_world_response(response)
    end
  end
end
