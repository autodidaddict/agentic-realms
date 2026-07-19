defmodule Srd.Dice.ExprTest do
  use ExUnit.Case, async: true

  alias Srd.Dice.Expr

  describe "parse/1" do
    test "parses NdX with a modifier" do
      assert Expr.parse("3d10+5") == {:ok, %Expr{count: 3, sides: 10, modifier: 5}}
    end

    test "parses NdX with a negative modifier" do
      assert Expr.parse("2d6-1") == {:ok, %Expr{count: 2, sides: 6, modifier: -1}}
    end

    test "parses NdX with no modifier" do
      assert Expr.parse("1d4") == {:ok, %Expr{count: 1, sides: 4, modifier: 0}}
      assert Expr.parse("2d20") == {:ok, %Expr{count: 2, sides: 20, modifier: 0}}
    end

    test "treats a missing count as one" do
      assert Expr.parse("d20") == {:ok, %Expr{count: 1, sides: 20, modifier: 0}}
    end

    test "trims surrounding whitespace" do
      assert Expr.parse("  2d6  ") == {:ok, %Expr{count: 2, sides: 6, modifier: 0}}
    end

    test "passes an existing Expr through" do
      expr = %Expr{count: 1, sides: 8, modifier: 0}
      assert Expr.parse(expr) == {:ok, expr}
    end

    test "rejects a zero count" do
      assert {:error, {:invalid_dice, "0d6"}} = Expr.parse("0d6")
    end

    test "rejects nonsense" do
      assert {:error, {:invalid_dice, "banana"}} = Expr.parse("banana")
      assert {:error, {:invalid_dice, ""}} = Expr.parse("")
    end
  end

  describe "parse!/1" do
    test "returns the expression" do
      assert Expr.parse!("1d8") == %Expr{count: 1, sides: 8, modifier: 0}
    end

    test "raises on invalid notation" do
      assert_raise ArgumentError, ~r/invalid dice notation/, fn -> Expr.parse!("nope") end
    end
  end
end
