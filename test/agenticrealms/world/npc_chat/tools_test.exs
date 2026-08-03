defmodule AgenticRealms.World.NPCChat.ToolsTest do
  @moduledoc """
  Unit tests for the chat tool definitions.
  """

  use ExUnit.Case, async: true

  alias AgenticRealms.World.NPCChat.Tools

  describe "list/0" do
    test "returns exactly five tools (accept_quest, check_progress, finalize_quest)" do
      assert length(Tools.list()) == 5
    end

    test "each tool has name, description, input_schema keys" do
      for tool <- Tools.list() do
        assert is_binary(tool["name"])
        assert is_binary(tool["description"])
        assert is_map(tool["input_schema"])
      end
    end

    test "say and emote each require a text property of type string" do
      text_tools =
        Tools.list()
        |> Enum.filter(&(&1["name"] in ["say", "emote"]))

      for tool <- text_tools do
        assert tool["input_schema"]["required"] == ["text"]
        assert tool["input_schema"]["properties"]["text"]["type"] == "string"
      end
    end

    test "accept_quest requires a slug property of type string" do
      [accept] = Tools.list() |> Enum.filter(&(&1["name"] == "accept_quest"))
      assert accept["input_schema"]["required"] == ["slug"]
      assert accept["input_schema"]["properties"]["slug"]["type"] == "string"
    end

    test "names are the five tool names" do
      names = Tools.list() |> Enum.map(& &1["name"]) |> Enum.sort()
      assert names == ["accept_quest", "check_progress", "emote", "finalize_quest", "say"]
    end

    test "check_progress and finalize_quest each require a quest_id property" do
      [check] = Tools.list() |> Enum.filter(&(&1["name"] == "check_progress"))
      [final] = Tools.list() |> Enum.filter(&(&1["name"] == "finalize_quest"))

      for tool <- [check, final] do
        assert tool["input_schema"]["required"] == ["quest_id"]
        assert tool["input_schema"]["properties"]["quest_id"]["type"] == "string"
      end
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
    test "returns the five tool names" do
      assert Tools.names() ==
               MapSet.new([
                 "say",
                 "emote",
                 "accept_quest",
                 "check_progress",
                 "finalize_quest"
               ])
    end
  end
end
