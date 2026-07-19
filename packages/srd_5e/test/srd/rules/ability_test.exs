defmodule Srd.Rules.AbilityTest do
  use ExUnit.Case, async: true

  alias Srd.Rules.Ability

  describe "modifier/1" do
    test "computes the ability modifier, rounding down" do
      assert Ability.modifier(10) == 0
      assert Ability.modifier(11) == 0
      assert Ability.modifier(12) == 1
      assert Ability.modifier(8) == -1
      assert Ability.modifier(7) == -2
      assert Ability.modifier(1) == -5
      assert Ability.modifier(20) == 5
      assert Ability.modifier(30) == 10
    end
  end
end
