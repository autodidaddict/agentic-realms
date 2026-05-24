defmodule AgenticRealms.World.NPCChat.ToolsTest do
  @moduledoc """
  Unit tests for the chat tool definitions (feature 010).

  See `specs/010-npc-conversations/contracts/tools.md`.
  """

  use ExUnit.Case, async: true

  alias AgenticRealms.World.NPCChat.Tools

  describe "list/0" do
    test "returns exactly two tools" do
      assert length(Tools.list()) == 2
    end

    test "each tool has name, description, input_schema keys" do
      for tool <- Tools.list() do
        assert is_binary(tool["name"])
        assert is_binary(tool["description"])
        assert is_map(tool["input_schema"])
      end
    end

    test "each tool requires a text property of type string" do
      for tool <- Tools.list() do
        assert tool["input_schema"]["required"] == ["text"]
        assert tool["input_schema"]["properties"]["text"]["type"] == "string"
      end
    end

    test "names are 'say' and 'emote'" do
      names = Tools.list() |> Enum.map(& &1["name"]) |> Enum.sort()
      assert names == ["emote", "say"]
    end

    test "list round-trips through Jason.encode!/decode! losslessly" do
      original = Tools.list()
      encoded = Jason.encode!(original)
      decoded = Jason.decode!(encoded)
      assert decoded == original
    end

    test "function is pure (idempotent)" do
      assert Tools.list() == Tools.list()
    end
  end

  describe "names/0" do
    test "returns exactly MapSet.new(['say', 'emote'])" do
      assert Tools.names() == MapSet.new(["say", "emote"])
    end
  end
end
