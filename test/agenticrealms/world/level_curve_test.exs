defmodule AgenticRealms.World.LevelCurveTest do
  use ExUnit.Case, async: true

  alias AgenticRealms.World.LevelCurve

  describe "threshold/1" do
    test "matches the D&D-style compounding quadratic thresholds" do
      assert LevelCurve.threshold(1) == 0
      assert LevelCurve.threshold(2) == 100
      assert LevelCurve.threshold(3) == 300
      assert LevelCurve.threshold(4) == 600
      assert LevelCurve.threshold(5) == 1000
      assert LevelCurve.threshold(6) == 1500
    end
  end

  describe "level_for_xp/1" do
    test "clamps non-positive xp to level 1" do
      assert LevelCurve.level_for_xp(0) == 1
      assert LevelCurve.level_for_xp(-500) == 1
    end

    test "level boundaries are exact" do
      assert LevelCurve.level_for_xp(99) == 1
      assert LevelCurve.level_for_xp(100) == 2
      assert LevelCurve.level_for_xp(299) == 2
      assert LevelCurve.level_for_xp(300) == 3
      assert LevelCurve.level_for_xp(999) == 4
      assert LevelCurve.level_for_xp(1000) == 5
    end

    test "is monotonic non-decreasing across a wide range" do
      levels = Enum.map(0..5000//7, &LevelCurve.level_for_xp/1)
      assert levels == Enum.sort(levels)
    end

    test "a large award crosses multiple levels at once" do
      # 1000 xp from 0 lands at level 5, not level 2.
      assert LevelCurve.level_for_xp(1000) == 5
    end
  end

  describe "progress/1" do
    test "fresh player at 0 xp is 0% into level 1, 100 to next" do
      assert %{level: 1, into_level: 0, to_next: 100, fraction: +0.0} = LevelCurve.progress(0)
    end

    test "mid-level fraction is correct" do
      p = LevelCurve.progress(50)
      assert p.level == 1
      assert p.into_level == 50
      assert p.to_next == 100
      assert p.fraction == 0.5
    end

    test "just after reaching a level, fraction resets toward the next" do
      p = LevelCurve.progress(100)
      assert p.level == 2
      assert p.into_level == 0
      assert p.to_next == 200
      assert p.fraction == +0.0
    end

    test "fraction is always in [0, 1)" do
      for xp <- 0..3000//13 do
        f = LevelCurve.progress(xp).fraction
        assert f >= 0.0 and f < 1.0
      end
    end
  end
end
