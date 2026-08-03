defmodule Srd.Rules.ExperienceTest do
  use ExUnit.Case, async: true

  alias Srd.Rules.Experience

  @table [
    {1, 0},
    {2, 300},
    {3, 900},
    {4, 2_700},
    {5, 6_500},
    {6, 14_000},
    {7, 23_000},
    {8, 34_000},
    {9, 48_000},
    {10, 64_000},
    {11, 85_000},
    {12, 100_000},
    {13, 120_000},
    {14, 140_000},
    {15, 165_000},
    {16, 195_000},
    {17, 225_000},
    {18, 265_000},
    {19, 305_000},
    {20, 355_000}
  ]

  describe "max_level/0" do
    test "is 20" do
      assert Experience.max_level() == 20
    end
  end

  describe "table/0" do
    test "is the twenty published levels in ascending order" do
      assert Experience.table() == @table
    end

    test "thresholds strictly increase" do
      Experience.table()
      |> Enum.map(&elem(&1, 1))
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.each(fn [lower, higher] -> assert higher > lower end)
    end
  end

  describe "threshold/1" do
    test "matches the published table at every level" do
      for {level, xp} <- @table do
        assert Experience.threshold(level) == xp
      end
    end

    test "raises below level 1" do
      assert_raise FunctionClauseError, fn -> Experience.threshold(0) end
      assert_raise FunctionClauseError, fn -> Experience.threshold(-1) end
    end

    test "raises above level 20" do
      assert_raise FunctionClauseError, fn -> Experience.threshold(21) end
    end
  end

  describe "level_for_xp/1" do
    test "returns the level at each exact threshold" do
      for {level, xp} <- @table do
        assert Experience.level_for_xp(xp) == level
      end
    end

    test "returns the level below at one xp short of each threshold" do
      for {level, xp} <- @table, level > 1 do
        assert Experience.level_for_xp(xp - 1) == level - 1
      end
    end

    test "clamps to 1 at and below zero" do
      assert Experience.level_for_xp(0) == 1
      assert Experience.level_for_xp(-1) == 1
      assert Experience.level_for_xp(-50_000) == 1
    end

    test "caps at 20 past the last threshold" do
      assert Experience.level_for_xp(355_001) == 20
      assert Experience.level_for_xp(9_999_999) == 20
    end

    test "is monotonic non-decreasing across the whole table" do
      levels = Enum.map(0..360_000//1_000, &Experience.level_for_xp/1)

      levels
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.each(fn [a, b] -> assert b >= a end)
    end
  end

  describe "progress/1" do
    test "at the bottom of level 1" do
      assert Experience.progress(0) == %{
               level: 1,
               into_level: 0,
               to_next: 300,
               fraction: 0.0,
               maxed?: false
             }
    end

    test "mid-band" do
      assert Experience.progress(450) == %{
               level: 2,
               into_level: 150,
               to_next: 600,
               fraction: 0.25,
               maxed?: false
             }
    end

    test "at the bottom of a higher band" do
      assert Experience.progress(6_500) == %{
               level: 5,
               into_level: 0,
               to_next: 7_500,
               fraction: 0.0,
               maxed?: false
             }
    end

    test "at level 20 there is no next threshold" do
      assert Experience.progress(355_000) == %{
               level: 20,
               into_level: 0,
               to_next: nil,
               fraction: 1.0,
               maxed?: true
             }
    end

    test "past level 20 keeps counting experience into the level" do
      assert Experience.progress(400_000) == %{
               level: 20,
               into_level: 45_000,
               to_next: nil,
               fraction: 1.0,
               maxed?: true
             }
    end

    test "treats negative experience as zero" do
      assert Experience.progress(-100) == Experience.progress(0)
    end

    test "fraction stays in [0, 1) below level 20" do
      for xp <- 0..354_999//997 do
        %{fraction: fraction} = Experience.progress(xp)
        assert fraction >= 0.0 and fraction < 1.0
      end
    end
  end
end
