defmodule AgenticRealms.World.CommandParserTest do
  use ExUnit.Case, async: true

  alias AgenticRealms.World.CommandParser

  describe "empty / whitespace input" do
    test "empty string" do
      assert {:empty} = CommandParser.parse("")
    end

    test "whitespace only" do
      assert {:empty} = CommandParser.parse("   ")
    end

    test "mixed whitespace only" do
      assert {:empty} = CommandParser.parse("\n\t  ")
    end
  end

  describe "look" do
    test "look" do
      assert {:look} = CommandParser.parse("look")
    end

    test "uppercase + padding" do
      assert {:look} = CommandParser.parse("  LOOK  ")
    end

    test "l alias" do
      assert {:look} = CommandParser.parse("l")
    end

    test "look with trailing text is still :look (object-targeted look out of scope)" do
      assert {:look} = CommandParser.parse("look around")
    end
  end

  describe "inventory" do
    test "inventory" do
      assert {:inventory} = CommandParser.parse("inventory")
    end

    test "inv" do
      assert {:inventory} = CommandParser.parse("inv")
    end

    test "i" do
      assert {:inventory} = CommandParser.parse("i")
    end

    test "uppercase" do
      assert {:inventory} = CommandParser.parse("INV")
    end
  end

  describe "movement (FR-006)" do
    test "north / n" do
      assert {:move, :north} = CommandParser.parse("north")
      assert {:move, :north} = CommandParser.parse("n")
      assert {:move, :north} = CommandParser.parse("N")
      assert {:move, :north} = CommandParser.parse("  north  ")
    end

    test "south / s" do
      assert {:move, :south} = CommandParser.parse("south")
      assert {:move, :south} = CommandParser.parse("s")
    end

    test "east / e" do
      assert {:move, :east} = CommandParser.parse("east")
      assert {:move, :east} = CommandParser.parse("e")
    end

    test "west / w" do
      assert {:move, :west} = CommandParser.parse("west")
      assert {:move, :west} = CommandParser.parse("w")
    end

    test "up / u" do
      assert {:move, :up} = CommandParser.parse("up")
      assert {:move, :up} = CommandParser.parse("u")
    end

    test "down / d" do
      assert {:move, :down} = CommandParser.parse("down")
      assert {:move, :down} = CommandParser.parse("d")
    end

    test "go <direction>" do
      assert {:move, :north} = CommandParser.parse("go north")
      assert {:move, :north} = CommandParser.parse("go  NORTH")
    end

    test "go alone is unknown" do
      assert {:unknown, "go"} = CommandParser.parse("go")
    end

    test "go to a non-direction is unknown" do
      assert {:unknown, "go nowhere"} = CommandParser.parse("go nowhere")
    end
  end

  describe "take" do
    test "take with single-word name" do
      assert {:take, "lantern"} = CommandParser.parse("take lantern")
    end

    test "take with multi-word name" do
      assert {:take, "brass lantern"} = CommandParser.parse("take brass lantern")
    end

    test "normalizes case + collapses internal whitespace" do
      assert {:take, "brass lantern"} = CommandParser.parse("  TAKE   Brass  Lantern  ")
    end

    test "take with no target" do
      assert {:invalid_take_target} = CommandParser.parse("take")
    end

    test "take with only whitespace after verb" do
      assert {:invalid_take_target} = CommandParser.parse("take  ")
    end

    test "get alias" do
      assert {:take, "journal"} = CommandParser.parse("get journal")
    end

    test "pick alias (one-word, accepts awkward `pick up`)" do
      assert {:take, "up journal"} = CommandParser.parse("pick up journal")
    end
  end

  describe "drop" do
    test "drop with name" do
      assert {:drop, "letter"} = CommandParser.parse("drop letter")
    end

    test "drop with no target" do
      assert {:invalid_drop_target} = CommandParser.parse("drop")
    end

    test "put alias" do
      assert {:drop, "letter"} = CommandParser.parse("put letter")
    end
  end

  describe "unknown verbs (FR-018)" do
    test "single unknown verb" do
      assert {:unknown, "dance"} = CommandParser.parse("dance")
    end

    test "phrase" do
      assert {:unknown, "hello world"} = CommandParser.parse("hello world")
    end

    test "unknown is returned in original case" do
      assert {:unknown, "Dance"} = CommandParser.parse("Dance")
    end
  end
end
