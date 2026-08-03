defmodule Srd.Rules.PointBuyTest do
  use ExUnit.Case, async: true

  doctest Srd.Rules.PointBuy

  alias Srd.Rules.Ability
  alias Srd.Rules.PointBuy

  defp spread(overrides \\ []) do
    Ability.all()
    |> Map.new(&{&1, PointBuy.min_score()})
    |> Map.merge(Map.new(overrides))
  end

  describe "the cost table" do
    test "starts free and rises with every step" do
      costs = Enum.map(PointBuy.scores(), &PointBuy.cost!/1)

      assert hd(costs) == 0
      assert costs == Enum.sort(costs)
      assert Enum.uniq(costs) == costs
    end

    test "the last two steps cost double, which is the point of the variant" do
      step = fn from -> PointBuy.cost!(from + 1) - PointBuy.cost!(from) end

      for from <- 8..12, do: assert(step.(from) == 1)
      assert step.(13) == 2
      assert step.(14) == 2
    end

    test "a score outside the buyable range has no cost rather than a wrong one" do
      assert PointBuy.cost(7) == :error
      assert PointBuy.cost(16) == :error
      assert PointBuy.cost(:fifteen) == :error
      assert_raise ArgumentError, fn -> PointBuy.cost!(16) end
    end
  end

  describe "legal?/1" do
    test "the canonical spread spends exactly the budget" do
      canonical = spread(str: 15, dex: 14, con: 13, int: 12, wis: 10, cha: 8)

      assert PointBuy.legal?(canonical)
      assert PointBuy.fully_spent?(canonical)
      assert PointBuy.remaining(canonical) == {:ok, 0}
    end

    test "spending nothing is legal, just wasteful" do
      assert PointBuy.legal?(spread())
      refute PointBuy.fully_spent?(spread())
      assert PointBuy.remaining(spread()) == {:ok, PointBuy.budget()}
    end

    test "three 15s is exactly the budget, and is meant to be reachable" do
      assert PointBuy.fully_spent?(spread(str: 15, dex: 15, con: 15))
    end

    test "overspending is not" do
      refute PointBuy.legal?(spread(str: 15, dex: 15, con: 15, int: 9))
    end

    test "a missing ability is not a partial spread, it is an illegal one" do
      assert PointBuy.legal?(spread()) and not PointBuy.legal?(Map.delete(spread(), :cha))
    end

    test "a score outside the range is rejected even when the total would fit" do
      refute PointBuy.legal?(spread(str: 18))
    end

    test "rejects things that are not spreads at all" do
      refute PointBuy.legal?(nil)
      refute PointBuy.legal?([])
    end
  end

  describe "can_increase?/2 and can_decrease?/2" do
    test "the floor cannot be lowered and the ceiling cannot be raised" do
      refute PointBuy.can_decrease?(spread(), :str)
      refute PointBuy.can_increase?(spread(str: 15), :str)
    end

    test "an increase is refused when the remaining points will not cover it" do
      tight = spread(str: 15, dex: 14, con: 13, int: 12, wis: 10, cha: 8)
      one_left = %{tight | cha: 8, wis: 9}

      assert PointBuy.remaining(one_left) == {:ok, 1}
      refute PointBuy.can_increase?(one_left, :con), "13 -> 14 costs 2, only 1 left"
      assert PointBuy.can_increase?(one_left, :cha), "8 -> 9 costs 1"
    end

    test "an unknown ability is neither raisable nor lowerable" do
      refute PointBuy.can_increase?(spread(), :luck)
      refute PointBuy.can_decrease?(spread(), :luck)
    end
  end
end
