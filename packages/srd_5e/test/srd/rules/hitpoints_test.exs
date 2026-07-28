defmodule Srd.Rules.HitpointsTest do
  use ExUnit.Case, async: true

  alias Srd.Rules.Hitpoints

  describe "new/3" do
    test "defaults temporary hit points to 0" do
      assert Hitpoints.new(10, 12) == %Hitpoints{hp: 10, max_hp: 12, temp_hp: 0, outcome: nil}
    end

    test "accepts temporary hit points" do
      assert Hitpoints.new(10, 12, 5).temp_hp == 5
    end
  end

  describe "damage/2" do
    test "reduces current hit points" do
      pool = Hitpoints.damage(Hitpoints.new(12, 12), 5)
      assert pool.hp == 7
      assert pool.outcome == :ok
    end

    test "temporary hit points absorb damage first" do
      pool = Hitpoints.damage(Hitpoints.new(7, 12, 3), 5)
      assert pool.hp == 5
      assert pool.temp_hp == 0
      assert pool.outcome == :ok
    end

    test "temporary hit points absorb partially" do
      pool = Hitpoints.damage(Hitpoints.new(10, 12, 10), 4)
      assert pool.hp == 10
      assert pool.temp_hp == 6
    end

    test "dropping to exactly 0 is downed" do
      pool = Hitpoints.damage(Hitpoints.new(4, 12), 4)
      assert pool.hp == 0
      assert pool.outcome == :downed
    end

    test "current hit points floor at 0" do
      pool = Hitpoints.damage(Hitpoints.new(3, 20), 5)
      assert pool.hp == 0
      assert pool.outcome == :downed
    end

    test "damage taken while at 0 is a hit while down" do
      pool = Hitpoints.damage(Hitpoints.new(0, 12), 5)
      assert pool.hp == 0
      assert pool.outcome == :hit_while_down
    end

    test "excess damage of at least the maximum is instant death" do
      pool = Hitpoints.damage(Hitpoints.new(12, 12), 30)
      assert pool.hp == 0
      assert pool.outcome == :dead
    end

    test "a hit at 0 of at least the maximum is instant death" do
      pool = Hitpoints.damage(Hitpoints.new(0, 12), 12)
      assert pool.outcome == :dead
    end

    test "damage fully absorbed at 0 is not a failure" do
      pool = Hitpoints.damage(Hitpoints.new(0, 12, 8), 5)
      assert pool.hp == 0
      assert pool.temp_hp == 3
      assert pool.outcome == :ok
    end

    test "rejects negative damage" do
      assert_raise FunctionClauseError, fn -> Hitpoints.damage(Hitpoints.new(10, 12), -5) end
    end
  end

  describe "heal/2" do
    test "restores hit points" do
      pool = Hitpoints.heal(Hitpoints.new(5, 12), 4)
      assert pool.hp == 9
      assert pool.outcome == :ok
    end

    test "clamps to the maximum" do
      pool = Hitpoints.heal(Hitpoints.new(5, 12), 20)
      assert pool.hp == 12
    end

    test "healing from 0 is recovery" do
      pool = Hitpoints.heal(Hitpoints.new(0, 12), 3)
      assert pool.hp == 3
      assert pool.outcome == :recovered
    end

    test "does not affect temporary hit points" do
      pool = Hitpoints.heal(Hitpoints.new(5, 12, 4), 3)
      assert pool.hp == 8
      assert pool.temp_hp == 4
    end
  end

  describe "starting/2" do
    test "is the die maximum plus the Constitution modifier" do
      assert Hitpoints.starting("1d6", 0) == 6
      assert Hitpoints.starting("1d8", 0) == 8
      assert Hitpoints.starting("1d10", 0) == 10
      assert Hitpoints.starting("1d12", 0) == 12
    end

    test "adds a positive Constitution modifier" do
      assert Hitpoints.starting("1d10", 2) == 12
      assert Hitpoints.starting("1d6", 5) == 11
    end

    test "subtracts a negative Constitution modifier" do
      assert Hitpoints.starting("1d10", -2) == 8
      assert Hitpoints.starting("1d6", -3) == 3
    end

    test "floors at 1 rather than reaching zero" do
      assert Hitpoints.starting("1d6", -6) == 1
      assert Hitpoints.starting("1d6", -9) == 1
      assert Hitpoints.starting("1d12", -20) == 1
    end

    test "accepts a parsed expression" do
      assert Hitpoints.starting(Srd.Dice.Expr.parse!("1d10"), 2) == 12
    end
  end

  describe "per_level/2" do
    test "is half the die rounded up, plus one, plus Constitution" do
      assert Hitpoints.per_level("1d6", 0) == 4
      assert Hitpoints.per_level("1d8", 0) == 5
      assert Hitpoints.per_level("1d10", 0) == 6
      assert Hitpoints.per_level("1d12", 0) == 7
    end

    test "applies the Constitution modifier" do
      assert Hitpoints.per_level("1d10", 2) == 8
      assert Hitpoints.per_level("1d6", -1) == 3
    end

    test "is not floored" do
      assert Hitpoints.per_level("1d6", -4) == 0
      assert Hitpoints.per_level("1d6", -6) == -2
    end

    test "accepts a parsed expression" do
      assert Hitpoints.per_level(Srd.Dice.Expr.parse!("1d8"), 1) == 6
    end
  end

  describe "maximum/3" do
    test "at level 1 equals starting/2" do
      for die <- ~w(1d6 1d8 1d10 1d12), con <- -2..3 do
        assert Hitpoints.maximum(die, 1, con) == Hitpoints.starting(die, con)
      end
    end

    test "accumulates the per-level gain" do
      assert Hitpoints.maximum("1d10", 2, 2) == 20
      assert Hitpoints.maximum("1d10", 3, 2) == 28
      assert Hitpoints.maximum("1d10", 5, 2) == 44
    end

    test "matches a hand-run total at a high level" do
      # d8 wizard, Constitution +1: 9 at level 1, then 6 per level for 19 more.
      assert Hitpoints.maximum("1d8", 20, 1) == 9 + 19 * 6
    end

    test "floors at 1 when Constitution drags the total under" do
      assert Hitpoints.maximum("1d6", 5, -6) == 1
    end

    test "accepts a parsed expression" do
      assert Hitpoints.maximum(Srd.Dice.Expr.parse!("1d10"), 3, 2) == 28
    end
  end

  describe "hit_dice/2" do
    test "is the class die counted by level" do
      assert Hitpoints.hit_dice("1d10", 1) == %Srd.Dice.Expr{count: 1, sides: 10, modifier: 0}
      assert Hitpoints.hit_dice("1d10", 7) == %Srd.Dice.Expr{count: 7, sides: 10, modifier: 0}
      assert Hitpoints.hit_dice("1d6", 20) == %Srd.Dice.Expr{count: 20, sides: 6, modifier: 0}
    end

    test "accepts a parsed expression" do
      assert Hitpoints.hit_dice(Srd.Dice.Expr.parse!("1d8"), 3).count == 3
    end
  end
end
