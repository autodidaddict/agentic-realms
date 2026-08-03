defmodule AgenticRealms.World.IntentResolver.ToolsTest do
  @moduledoc """
  Structural tests for the Anthropic tool definitions. Pins the tool set so a
  drift between the tools array and the resolver's dispatch table is caught.
  """
  use ExUnit.Case, async: true

  alias AgenticRealms.World.IntentResolver.Tools

  @canonical ~w(take drop move look inventory say emote tell whisper chat)

  test "exposes exactly 11 tools — 10 canonical actions plus refuse" do
    assert length(Tools.list()) == 11
  end

  test "every canonical action is present exactly once" do
    names = Enum.map(Tools.list(), & &1["name"])

    for action <- @canonical do
      assert Enum.count(names, &(&1 == action)) == 1, "expected #{action} exactly once"
    end
  end

  test "the refuse tool is present" do
    names = Enum.map(Tools.list(), & &1["name"])
    assert "refuse" in names
  end

  test "names/0 matches the tool list exactly" do
    list_names = Tools.list() |> Enum.map(& &1["name"]) |> MapSet.new()
    assert Tools.names() == list_names
  end

  test "every tool has a non-empty description and an object input_schema" do
    for tool <- Tools.list() do
      assert is_binary(tool["description"]) and tool["description"] != "",
             "#{tool["name"]} must have a description"

      assert tool["input_schema"]["type"] == "object",
             "#{tool["name"]} input_schema must be an object"
    end
  end

  test "move's direction is constrained to the six canonical directions" do
    move = Enum.find(Tools.list(), &(&1["name"] == "move"))
    enum = move["input_schema"]["properties"]["direction"]["enum"]
    assert Enum.sort(enum) == Enum.sort(~w(north south east west up down))
  end

  test "take and drop require an object; tell and whisper require recipient and text" do
    by_name = Map.new(Tools.list(), &{&1["name"], &1})

    assert by_name["take"]["input_schema"]["required"] == ["object"]
    assert by_name["drop"]["input_schema"]["required"] == ["object"]
    assert Enum.sort(by_name["tell"]["input_schema"]["required"]) == ["recipient", "text"]
    assert Enum.sort(by_name["whisper"]["input_schema"]["required"]) == ["recipient", "text"]
  end

  test "look and inventory take no required arguments" do
    by_name = Map.new(Tools.list(), &{&1["name"], &1})

    assert by_name["look"]["input_schema"]["required"] == []
    assert by_name["inventory"]["input_schema"]["required"] == []
  end

  describe "look tool — optional target property" do
    test "look exposes an optional 'target' string property" do
      look = Enum.find(Tools.list(), &(&1["name"] == "look"))
      props = look["input_schema"]["properties"]

      assert is_map(props["target"])
      assert props["target"]["type"] == "string"
      assert is_binary(props["target"]["description"]) and props["target"]["description"] != ""
    end

    test "target is not in required (so no-target look stays valid)" do
      look = Enum.find(Tools.list(), &(&1["name"] == "look"))
      assert look["input_schema"]["required"] == []
    end
  end
end
