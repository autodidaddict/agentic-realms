defmodule AgenticRealms.World.DirectionTest do
  use ExUnit.Case, async: true

  alias AgenticRealms.World.Direction

  describe "parse/1" do
    test "full names — cardinals + verticals" do
      assert {:ok, :north} = Direction.parse("north")
      assert {:ok, :south} = Direction.parse("south")
      assert {:ok, :east} = Direction.parse("east")
      assert {:ok, :west} = Direction.parse("west")
      assert {:ok, :up} = Direction.parse("up")
      assert {:ok, :down} = Direction.parse("down")
    end

    test "full names — diagonals (feature 012)" do
      assert {:ok, :northeast} = Direction.parse("northeast")
      assert {:ok, :northwest} = Direction.parse("northwest")
      assert {:ok, :southeast} = Direction.parse("southeast")
      assert {:ok, :southwest} = Direction.parse("southwest")
    end

    test "single-letter / short aliases" do
      assert {:ok, :north} = Direction.parse("n")
      assert {:ok, :south} = Direction.parse("s")
      assert {:ok, :east} = Direction.parse("e")
      assert {:ok, :west} = Direction.parse("w")
      assert {:ok, :up} = Direction.parse("u")
      assert {:ok, :down} = Direction.parse("d")
    end

    test "two-letter diagonal aliases (feature 012)" do
      assert {:ok, :northeast} = Direction.parse("ne")
      assert {:ok, :northwest} = Direction.parse("nw")
      assert {:ok, :southeast} = Direction.parse("se")
      assert {:ok, :southwest} = Direction.parse("sw")
    end

    test "case-insensitive + whitespace-tolerant" do
      assert {:ok, :north} = Direction.parse("  NORTH  ")
      assert {:ok, :north} = Direction.parse("North")
      assert {:ok, :north} = Direction.parse("N")
      assert {:ok, :northeast} = Direction.parse("  NE  ")
      assert {:ok, :northeast} = Direction.parse("NorthEast")
    end

    test "go-prefixed" do
      assert {:ok, :north} = Direction.parse("go north")
      assert {:ok, :north} = Direction.parse("GO   north")
      assert {:ok, :northeast} = Direction.parse("go ne")
    end

    test "accepts already-canonical atoms" do
      assert {:ok, :north} = Direction.parse(:north)
      assert {:ok, :northeast} = Direction.parse(:northeast)
      assert {:ok, :southwest} = Direction.parse(:southwest)
    end

    test "rejects non-directions" do
      assert :error = Direction.parse("nowhere")
      assert :error = Direction.parse("middle")
      assert :error = Direction.parse("")
      assert :error = Direction.parse("nner")
    end
  end

  describe "opposite/1" do
    test "cardinal + vertical pairings" do
      assert :south = Direction.opposite(:north)
      assert :north = Direction.opposite(:south)
      assert :west = Direction.opposite(:east)
      assert :east = Direction.opposite(:west)
      assert :down = Direction.opposite(:up)
      assert :up = Direction.opposite(:down)
    end

    test "diagonal pairings (feature 012)" do
      assert :southwest = Direction.opposite(:northeast)
      assert :northeast = Direction.opposite(:southwest)
      assert :southeast = Direction.opposite(:northwest)
      assert :northwest = Direction.opposite(:southeast)
    end
  end

  describe "to_string/1" do
    test "atoms" do
      assert "north" = Direction.to_string(:north)
      assert "down" = Direction.to_string(:down)
      assert "northeast" = Direction.to_string(:northeast)
      assert "southwest" = Direction.to_string(:southwest)
    end

    test "is idempotent on canonical strings (for JSON-round-tripped events)" do
      assert "north" = Direction.to_string("north")
      assert "down" = Direction.to_string("down")
      assert "northeast" = Direction.to_string("northeast")
      assert "southwest" = Direction.to_string("southwest")
    end
  end

  describe "canonical/0" do
    test "returns all 10 directions" do
      canonical = Direction.canonical()
      assert length(canonical) == 10
      assert :north in canonical
      assert :northeast in canonical
      assert :northwest in canonical
      assert :southeast in canonical
      assert :southwest in canonical
      assert :up in canonical
    end
  end
end
