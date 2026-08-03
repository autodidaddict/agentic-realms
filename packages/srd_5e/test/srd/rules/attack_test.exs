defmodule Srd.Rules.AttackTest do
  use ExUnit.Case, async: true

  alias Srd.Dice.Roll
  alias Srd.Rules.Attack

  defp d20(nat, mod \\ 0) do
    %Roll{count: 1, sides: 20, modifier: mod, dice: [nat], reduce: :sum, total: nat + mod}
  end

  describe "resolve/2" do
    test "hits when the total meets or beats AC" do
      result = Attack.resolve(d20(14, 5), target_ac: 15)
      assert result.hit?
      refute result.critical?
      assert result.natural == 14
      assert result.total == 19
      assert result.target_ac == 15
    end

    test "hits on a total exactly equal to AC" do
      result = Attack.resolve(d20(13, 2), target_ac: 15)
      assert result.hit?
      refute result.critical?
    end

    test "misses when the total is below AC" do
      result = Attack.resolve(d20(3, 2), target_ac: 15)
      refute result.hit?
      refute result.critical?
      assert result.natural == 3
    end

    test "a natural 20 always hits and crits, even against a higher AC" do
      result = Attack.resolve(d20(20), target_ac: 25)
      assert result.hit?
      assert result.critical?
      assert result.natural == 20
    end

    test "a natural 1 always misses, even when the total would beat AC" do
      result = Attack.resolve(d20(1, 20), target_ac: 15)
      refute result.hit?
      refute result.critical?
      assert result.natural == 1
    end

    test "detects a crit through the kept die under advantage" do
      adv = %Roll{count: 2, sides: 20, modifier: 7, dice: [20, 5], reduce: :max, total: 27}
      result = Attack.resolve(adv, target_ac: 15)
      assert result.hit?
      assert result.critical?
      assert result.natural == 20
    end
  end
end
