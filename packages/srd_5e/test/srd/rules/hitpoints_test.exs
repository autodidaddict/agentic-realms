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
end
