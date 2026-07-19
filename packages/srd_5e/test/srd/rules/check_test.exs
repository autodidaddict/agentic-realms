defmodule Srd.Rules.CheckTest do
  use ExUnit.Case, async: true

  alias Srd.Dice.Roll
  alias Srd.Rules.Check

  # A plain d20 showing `nat` on the die, with a flat `mod`.
  defp d20(nat, mod \\ 0) do
    %Roll{count: 1, sides: 20, modifier: mod, dice: [nat], reduce: :sum, total: nat + mod}
  end

  describe "resolve/2" do
    test "succeeds when the total meets or beats the DC" do
      result = Check.resolve(d20(15), dc: 15)
      assert result.success?
      assert result.margin == 0
      assert result.dc == 15
    end

    test "fails when the total is below the DC" do
      result = Check.resolve(d20(6, 3), dc: 15)
      refute result.success?
      assert result.margin == -6
    end

    test "carries the natural die and total through" do
      result = Check.resolve(d20(9, 5), dc: 10)
      assert result.natural == 9
      assert result.total == 14
    end

    test "raises on a non-d20 roll" do
      d8 = %Roll{count: 1, sides: 8, modifier: 0, dice: [5], reduce: :sum, total: 5}

      assert_raise ArgumentError, ~r/d20 test requires a d20 roll, got d8/, fn ->
        Check.resolve(d8, dc: 12)
      end
    end
  end

  describe "passive/2" do
    test "is 10 plus the modifier" do
      assert Check.passive(4) == 14
    end

    test "adds 5 for advantage and subtracts 5 for disadvantage" do
      assert Check.passive(4, advantage: :advantage) == 19
      assert Check.passive(4, advantage: :disadvantage) == 9
    end
  end
end
