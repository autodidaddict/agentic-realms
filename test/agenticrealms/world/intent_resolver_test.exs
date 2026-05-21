defmodule AgenticRealms.World.IntentResolverTest do
  @moduledoc """
  Unit tests for `IntentResolver.parse_response/1` — the pure mapping from an
  Anthropic Messages API response body to a resolver outcome (action tuple or
  refusal). No DB, no HTTP: the response bodies are canned.

  End-to-end `resolve/2` behavior (context build + real Anthropic call) is
  covered by the `:integration`-tagged LiveView test.
  """
  use ExUnit.Case, async: true

  alias AgenticRealms.World.IntentResolver

  # Build an Anthropic-shaped response containing a single tool_use block.
  defp tool_response(name, input) do
    %{
      "content" => [
        %{"type" => "tool_use", "id" => "toolu_x", "name" => name, "input" => input}
      ],
      "stop_reason" => "tool_use"
    }
  end

  describe "parse_response/1 — happy path, all nine canonical verbs" do
    test "take maps to {:take, object}" do
      assert {:ok, {:take, "brass lantern"}} =
               IntentResolver.parse_response(
                 tool_response("take", %{"object" => "brass lantern"})
               )
    end

    test "drop maps to {:drop, object}" do
      assert {:ok, {:drop, "journal"}} =
               IntentResolver.parse_response(tool_response("drop", %{"object" => "journal"}))
    end

    test "move maps to {:move, direction_atom} for each canonical direction" do
      for dir <- ~w(north south east west up down) do
        atom = String.to_existing_atom(dir)

        assert {:ok, {:move, ^atom}} =
                 IntentResolver.parse_response(tool_response("move", %{"direction" => dir}))
      end
    end

    test "look maps to {:look}" do
      assert {:ok, {:look}} = IntentResolver.parse_response(tool_response("look", %{}))
    end

    test "look with a target maps to {:look, target} (feature 006)" do
      assert {:ok, {:look, "brass lantern"}} =
               IntentResolver.parse_response(
                 tool_response("look", %{"target" => "brass lantern"})
               )
    end

    test "look with an empty-string target falls back to {:look}" do
      assert {:ok, {:look}} =
               IntentResolver.parse_response(tool_response("look", %{"target" => ""}))
    end

    test "inventory maps to {:inventory}" do
      assert {:ok, {:inventory}} = IntentResolver.parse_response(tool_response("inventory", %{}))
    end

    test "say maps to {:say, text}, preserving casing" do
      assert {:ok, {:say, "Hello There"}} =
               IntentResolver.parse_response(tool_response("say", %{"text" => "Hello There"}))
    end

    test "emote maps to {:emote, text}" do
      assert {:ok, {:emote, "waves at the fire"}} =
               IntentResolver.parse_response(
                 tool_response("emote", %{"text" => "waves at the fire"})
               )
    end

    test "tell maps to {:tell, recipient, text}" do
      assert {:ok, {:tell, "alice", "running late"}} =
               IntentResolver.parse_response(
                 tool_response("tell", %{"recipient" => "alice", "text" => "running late"})
               )
    end

    test "whisper maps to {:whisper, recipient, text}" do
      assert {:ok, {:whisper, "bob", "watch out"}} =
               IntentResolver.parse_response(
                 tool_response("whisper", %{"recipient" => "bob", "text" => "watch out"})
               )
    end

    test "action tuples are shape-compatible with CommandParser sentinels" do
      # take/drop carry a string; move carries an atom; look/inventory are
      # bare; say/emote carry a string; tell/whisper carry two strings —
      # exactly what GameLive's existing case branches expect.
      assert {:ok, {:take, name}} =
               IntentResolver.parse_response(tool_response("take", %{"object" => "x"}))

      assert is_binary(name)

      assert {:ok, {:move, dir}} =
               IntentResolver.parse_response(tool_response("move", %{"direction" => "north"}))

      assert is_atom(dir)
    end
  end

  describe "parse_response/1 — refusals (US2)" do
    test "the refuse tool returns the model-authored message verbatim" do
      assert {:error, "Combat isn't supported yet."} =
               IntentResolver.parse_response(
                 tool_response("refuse", %{"message" => "Combat isn't supported yet."})
               )
    end

    test "a refuse response never produces a look action (resolver contract)" do
      # Resolver-level contract: when the model picks `refuse`, the resolver
      # surfaces the refusal and never substitutes {:look}, regardless of why
      # the model chose to refuse. (Pre-006 this test guarded the
      # near-mapping refusal rule; post-006 examine is supported, but the
      # resolver-level contract — refuse → error, never substitute — is
      # unchanged.)
      result =
        IntentResolver.parse_response(
          tool_response("refuse", %{
            "message" => "Combat is not supported yet."
          })
        )

      assert {:error, message} = result
      assert message =~ "Combat"
      refute match?({:ok, {:look}}, result)
      refute match?({:ok, {:look, _}}, result)
    end

    test "multiple tool_use blocks refuse with the one-action-at-a-time message" do
      response = %{
        "content" => [
          %{"type" => "tool_use", "id" => "t1", "name" => "take", "input" => %{"object" => "x"}},
          %{
            "type" => "tool_use",
            "id" => "t2",
            "name" => "move",
            "input" => %{"direction" => "north"}
          }
        ]
      }

      assert {:error, "Try one action at a time."} = IntentResolver.parse_response(response)
    end

    test "out-of-game refusal returns the model's message" do
      assert {:error, msg} =
               IntentResolver.parse_response(
                 tool_response("refuse", %{"message" => "Try a game action like look."})
               )

      assert msg == "Try a game action like look."
    end
  end

  describe "parse_response/1 — malformed responses (US3)" do
    test "a response with no tool_use block refuses gracefully" do
      response = %{"content" => [%{"type" => "text", "text" => "hello"}]}
      assert {:error, msg} = IntentResolver.parse_response(response)
      assert msg =~ "not sure what you meant"
    end

    test "an unrecognized tool name refuses gracefully" do
      assert {:error, msg} =
               IntentResolver.parse_response(
                 tool_response("teleport", %{"destination" => "moon"})
               )

      assert msg =~ "not sure what you meant"
    end

    test "a recognized tool with a missing required field refuses gracefully" do
      # `take` with no `object` — schema violation.
      assert {:error, msg} = IntentResolver.parse_response(tool_response("take", %{}))
      assert msg =~ "not sure what you meant"
    end

    test "a recognized tool with an empty required field refuses gracefully" do
      assert {:error, _} = IntentResolver.parse_response(tool_response("say", %{"text" => ""}))
    end

    test "move with a non-enum direction refuses gracefully" do
      assert {:error, msg} =
               IntentResolver.parse_response(tool_response("move", %{"direction" => "sideways"}))

      assert msg =~ "not sure what you meant"
    end

    test "a response missing the content field refuses gracefully" do
      assert {:error, _} = IntentResolver.parse_response(%{"stop_reason" => "end_turn"})
    end

    test "a non-map response refuses gracefully" do
      assert {:error, _} = IntentResolver.parse_response("garbage")
    end
  end
end
