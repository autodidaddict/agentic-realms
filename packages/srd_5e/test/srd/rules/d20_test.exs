defmodule Srd.Rules.D20Test do
  use ExUnit.Case, async: true

  alias Srd.Dice.Roll
  alias Srd.Rules.D20

  # A plain d20 showing `nat` on the die, with a flat `mod`.
  defp d20(nat, mod \\ 0) do
    %Roll{count: 1, sides: 20, modifier: mod, dice: [nat], reduce: :sum, total: nat + mod}
  end

  describe "test/2" do
    test "succeeds when the total meets or beats the target" do
      result = D20.test(d20(15), 15)
      assert result.success?
      assert result.margin == 0
    end

    test "fails when the total is below the target" do
      result = D20.test(d20(14), 15)
      refute result.success?
      assert result.margin == -1
    end

    test "natural is the unmodified die, not the total" do
      result = D20.test(d20(12, 5), 10)
      assert result.natural == 12
      assert result.total == 17
    end

    test "natural comes from the kept die under advantage" do
      # 2d20 keep-highest: dice [4, 18], +3 -> total 21, kept die 18
      adv = %Roll{count: 2, sides: 20, modifier: 3, dice: [4, 18], reduce: :max, total: 21}
      result = D20.test(adv, 15)
      assert result.natural == 18
      assert result.total == 21
      assert result.success?
      assert result.margin == 6
    end

    test "carries the target and total through" do
      result = D20.test(d20(18), 12)
      assert result.total == 18
      assert result.target == 12
      assert result.margin == 6
    end

    test "raises on a non-d20 roll" do
      d4 = %Roll{count: 1, sides: 4, modifier: 0, dice: [3], reduce: :sum, total: 3}

      assert_raise ArgumentError, ~r/d20 test requires a d20 roll, got d4/, fn ->
        D20.test(d4, 10)
      end
    end
  end
end
