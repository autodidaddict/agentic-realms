defmodule Srd.Rules.DamageTest do
  use ExUnit.Case, async: true

  alias Srd.Dice.Roll
  alias Srd.Rules.Damage

  # Damage only reads the roll total, so a minimal roll with that total is enough.
  defp roll(total) do
    %Roll{count: 1, sides: 12, modifier: 0, dice: [total], reduce: :sum, total: total}
  end

  describe "resolve/3" do
    test "with no defenses, final equals the raw roll" do
      result = Damage.resolve(roll(10), :fire)
      assert result.type == :fire
      assert result.raw == 10
      assert result.final == 10
    end

    test "resistance halves the damage, rounding down" do
      assert Damage.resolve(roll(7), :fire, resist: [:fire]).final == 3
    end

    test "vulnerability doubles the damage" do
      assert Damage.resolve(roll(6), :cold, vulnerable: [:cold]).final == 12
    end

    test "immunity zeroes the damage" do
      assert Damage.resolve(roll(9), :poison, immune: [:poison]).final == 0
    end

    test "a defense against a different type does not apply" do
      assert Damage.resolve(roll(8), :fire, resist: [:cold]).final == 8
    end

    test "rejects an unknown damage type" do
      assert_raise ArgumentError, ~r/unknown damage type: :plasma/, fn ->
        Damage.resolve(roll(5), :plasma)
      end
    end
  end

  describe "types/0" do
    test "lists the thirteen SRD damage types" do
      types = Damage.types()
      assert length(types) == 13
      assert :fire in types
      assert :slashing in types
      refute :plasma in types
    end
  end
end
