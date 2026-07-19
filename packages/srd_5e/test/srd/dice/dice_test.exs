defmodule Srd.DiceTest do
  use ExUnit.Case, async: true

  alias Srd.Dice
  alias Srd.Dice.{Expr, Roll}

  describe "roll/2" do
    test "rolls a notation string" do
      roll = Dice.roll("2d6+3")
      assert %Roll{count: 2, sides: 6, modifier: 3, reduce: :sum} = roll
      assert length(roll.dice) == 2
      assert Enum.all?(roll.dice, &(&1 in 1..6))
      assert roll.total in 5..15
    end

    test "rolls a modifier-less string" do
      roll = Dice.roll("1d4")
      assert roll.count == 1
      assert roll.sides == 4
      assert roll.modifier == 0
      assert roll.total in 1..4
    end

    test "rolls an existing Expr" do
      roll = Dice.roll(%Expr{count: 3, sides: 10, modifier: 0})
      assert roll.sides == 10
      assert roll.total in 3..30
    end

    test "reduces with :max for advantage-style rolls" do
      roll = Dice.roll("2d20", reduce: :max)
      assert roll.reduce == :max
      assert roll.total == Enum.max(roll.dice)
      assert roll.total in 1..20
    end

    test "reduces with :drop_lowest" do
      roll = Dice.roll("4d6", reduce: :drop_lowest)
      assert roll.reduce == :drop_lowest
      assert roll.total in 3..18
    end

    test "raises on an unknown reduce tag" do
      assert_raise ArgumentError, ~r/unknown reduce tag/, fn ->
        Dice.roll("1d6", reduce: :bogus)
      end
    end
  end

  describe "d20/2" do
    test "rolls a single d20 plus the modifier" do
      roll = Dice.d20(5)
      assert %Roll{count: 1, sides: 20, modifier: 5, reduce: :sum} = roll
      assert roll.total in 6..25
    end

    test "advantage rolls 2d20 and keeps the max" do
      roll = Dice.d20(0, advantage: :advantage)
      assert roll.count == 2
      assert roll.reduce == :max
    end

    test "disadvantage rolls 2d20 and keeps the min" do
      roll = Dice.d20(0, advantage: :disadvantage)
      assert roll.count == 2
      assert roll.reduce == :min
    end
  end
end
