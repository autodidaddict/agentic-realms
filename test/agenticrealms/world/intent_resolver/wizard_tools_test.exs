defmodule AgenticRealms.World.IntentResolver.WizardToolsTest do
  use ExUnit.Case, async: true

  alias AgenticRealms.World.IntentResolver

  describe "parse_wizard_blueprint_response/1" do
    test "extracts a draft from a single draft_object_blueprint tool_use" do
      response = %{
        "content" => [
          %{
            "type" => "tool_use",
            "name" => "draft_object_blueprint",
            "input" => %{
              "name" => "brass-bound chest",
              "short_description" => "a brass-bound chest",
              "long_description" =>
                "A weather-beaten chest carved with the seal of the Western Reach.",
              "fixed" => true
            }
          }
        ]
      }

      assert {:ok,
              {:draft_blueprint,
               %{
                 name: "brass-bound chest",
                 short_description: "a brass-bound chest",
                 long_description:
                   "A weather-beaten chest carved with the seal of the Western Reach.",
                 fixed: true
               }}} = IntentResolver.parse_wizard_blueprint_response(response)
    end

    test "defaults fixed to false when omitted" do
      response = %{
        "content" => [
          %{
            "type" => "tool_use",
            "name" => "draft_object_blueprint",
            "input" => %{
              "name" => "clay pot",
              "short_description" => "a small clay pot",
              "long_description" => "A small clay pot, half-empty of dry barley."
            }
          }
        ]
      }

      assert {:ok, {:draft_blueprint, %{fixed: false}}} =
               IntentResolver.parse_wizard_blueprint_response(response)
    end

    test "treats a refuse tool_use as an error with the model's message" do
      response = %{
        "content" => [
          %{
            "type" => "tool_use",
            "name" => "refuse",
            "input" => %{"message" => "That's a question, not an object."}
          }
        ]
      }

      assert {:error, "That's a question, not an object."} =
               IntentResolver.parse_wizard_blueprint_response(response)
    end

    test "rejects multiple tool_use blocks as multi-step" do
      response = %{
        "content" => [
          %{"type" => "tool_use", "name" => "refuse", "input" => %{"message" => "a"}},
          %{"type" => "tool_use", "name" => "refuse", "input" => %{"message" => "b"}}
        ]
      }

      assert {:error, msg} = IntentResolver.parse_wizard_blueprint_response(response)
      assert msg =~ "one action at a time"
    end

    test "rejects responses with no tool_use blocks" do
      response = %{"content" => [%{"type" => "text", "text" => "Sorry."}]}
      assert {:error, _} = IntentResolver.parse_wizard_blueprint_response(response)
    end

    test "rejects unknown tool name" do
      response = %{
        "content" => [
          %{
            "type" => "tool_use",
            "name" => "edit_object",
            "input" => %{"name" => "x"}
          }
        ]
      }

      assert {:error, _} = IntentResolver.parse_wizard_blueprint_response(response)
    end

    test "rejects draft with missing required field" do
      response = %{
        "content" => [
          %{
            "type" => "tool_use",
            "name" => "draft_object_blueprint",
            "input" => %{
              "name" => "x",
              "short_description" => "y"
              # long_description missing
            }
          }
        ]
      }

      assert {:error, _} = IntentResolver.parse_wizard_blueprint_response(response)
    end

    test "rejects malformed response shapes" do
      assert {:error, _} = IntentResolver.parse_wizard_blueprint_response(%{"content" => "nope"})
      assert {:error, _} = IntentResolver.parse_wizard_blueprint_response(%{})
      assert {:error, _} = IntentResolver.parse_wizard_blueprint_response(nil)
    end
  end
end
