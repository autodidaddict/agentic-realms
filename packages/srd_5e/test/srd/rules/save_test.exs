defmodule Srd.Rules.SaveTest do
  use ExUnit.Case, async: true

  alias Srd.Dice.Roll
  alias Srd.Rules.Save

  # A plain d20 showing `nat` on the die, with a flat `mod`.
  defp d20(nat, mod \\ 0) do
    %Roll{count: 1, sides: 20, modifier: mod, dice: [nat], reduce: :sum, total: nat + mod}
  end

  describe "resolve/2" do
    test "succeeds when the total meets or beats the DC" do
      result = Save.resolve(d20(15), dc: 15)
      assert result.success?
      assert result.margin == 0
      assert result.dc == 15
    end

    test "fails when the total is below the DC" do
      result = Save.resolve(d20(8, 2), dc: 15)
      refute result.success?
      assert result.margin == -5
    end

    test "carries the natural die and total through" do
      result = Save.resolve(d20(11, 4), dc: 12)
      assert result.natural == 11
      assert result.total == 15
    end

    test "raises on a non-d20 roll" do
      d6 = %Roll{count: 1, sides: 6, modifier: 0, dice: [4], reduce: :sum, total: 4}

      assert_raise ArgumentError, ~r/d20 test requires a d20 roll, got d6/, fn ->
        Save.resolve(d6, dc: 10)
      end
    end
  end
end
