defmodule AgenticRealms.World.DirectionTest do
  use ExUnit.Case, async: true

  alias AgenticRealms.World.Direction

  describe "parse/1" do
    test "full names" do
      assert {:ok, :north} = Direction.parse("north")
      assert {:ok, :south} = Direction.parse("south")
      assert {:ok, :east} = Direction.parse("east")
      assert {:ok, :west} = Direction.parse("west")
      assert {:ok, :up} = Direction.parse("up")
      assert {:ok, :down} = Direction.parse("down")
    end

    test "single-letter aliases" do
      assert {:ok, :north} = Direction.parse("n")
      assert {:ok, :south} = Direction.parse("s")
      assert {:ok, :east} = Direction.parse("e")
      assert {:ok, :west} = Direction.parse("w")
      assert {:ok, :up} = Direction.parse("u")
      assert {:ok, :down} = Direction.parse("d")
    end

    test "case-insensitive + whitespace-tolerant" do
      assert {:ok, :north} = Direction.parse("  NORTH  ")
      assert {:ok, :north} = Direction.parse("North")
      assert {:ok, :north} = Direction.parse("N")
    end

    test "go-prefixed" do
      assert {:ok, :north} = Direction.parse("go north")
      assert {:ok, :north} = Direction.parse("GO   north")
    end

    test "accepts already-canonical atoms" do
      assert {:ok, :north} = Direction.parse(:north)
    end

    test "rejects non-directions" do
      assert :error = Direction.parse("northwest")
      assert :error = Direction.parse("nowhere")
      assert :error = Direction.parse("")
    end
  end

  describe "opposite/1" do
    test "all six pairings" do
      assert :south = Direction.opposite(:north)
      assert :north = Direction.opposite(:south)
      assert :west = Direction.opposite(:east)
      assert :east = Direction.opposite(:west)
      assert :down = Direction.opposite(:up)
      assert :up = Direction.opposite(:down)
    end
  end

  describe "to_string/1" do
    test "atoms" do
      assert "north" = Direction.to_string(:north)
      assert "down" = Direction.to_string(:down)
    end

    test "is idempotent on canonical strings (for JSON-round-tripped events)" do
      assert "north" = Direction.to_string("north")
      assert "down" = Direction.to_string("down")
    end
  end
end
