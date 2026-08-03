defmodule AgenticRealms.World.NPCChat.ReplyTest do
  @moduledoc """
  Unit tests for the chat reply parser.
  """

  use ExUnit.Case, async: true

  alias AgenticRealms.World.NPCChat.Reply

  defp say_response(text) do
    %{
      "content" => [
        %{"type" => "tool_use", "name" => "say", "input" => %{"text" => text}}
      ]
    }
  end

  defp emote_response(text) do
    %{
      "content" => [
        %{"type" => "tool_use", "name" => "emote", "input" => %{"text" => text}}
      ]
    }
  end

  describe "parse/1" do
    test "single say tool_use → {:speech, text}" do
      assert Reply.parse(say_response("Hello there.")) == {:speech, "Hello there."}
    end

    test "single emote tool_use → {:emote, text}" do
      assert Reply.parse(emote_response("raises an eyebrow curiously")) ==
               {:emote, "raises an eyebrow curiously"}
    end

    test "trims leading/trailing whitespace in text" do
      assert Reply.parse(say_response("  Hello.  ")) == {:speech, "Hello."}
    end

    test "unknown tool name → :malformed" do
      response = %{
        "content" => [
          %{"type" => "tool_use", "name" => "shout", "input" => %{"text" => "BOO"}}
        ]
      }

      assert Reply.parse(response) == {:error, :malformed}
    end

    test "empty text → :malformed" do
      assert Reply.parse(say_response("")) == {:error, :malformed}
    end

    test "whitespace-only text → :malformed" do
      assert Reply.parse(say_response("   ")) == {:error, :malformed}
    end

    test "missing text key → :malformed" do
      response = %{
        "content" => [
          %{"type" => "tool_use", "name" => "say", "input" => %{}}
        ]
      }

      assert Reply.parse(response) == {:error, :malformed}
    end

    test "two tool_use blocks → :malformed" do
      response = %{
        "content" => [
          %{"type" => "tool_use", "name" => "say", "input" => %{"text" => "A"}},
          %{"type" => "tool_use", "name" => "emote", "input" => %{"text" => "B"}}
        ]
      }

      assert Reply.parse(response) == {:error, :malformed}
    end

    test "zero tool_use blocks (only text content) → :malformed" do
      response = %{
        "content" => [
          %{"type" => "text", "text" => "I refuse to use a tool."}
        ]
      }

      assert Reply.parse(response) == {:error, :malformed}
    end

    test "missing content key → :malformed" do
      assert Reply.parse(%{"other" => []}) == {:error, :malformed}
    end

    test "content is not a list → :malformed" do
      assert Reply.parse(%{"content" => "string"}) == {:error, :malformed}
    end

    test "not a map at all → :malformed" do
      assert Reply.parse(nil) == {:error, :malformed}
      assert Reply.parse("string") == {:error, :malformed}
      assert Reply.parse([]) == {:error, :malformed}
    end
  end
end
