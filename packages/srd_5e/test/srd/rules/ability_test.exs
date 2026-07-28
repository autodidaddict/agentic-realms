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

  describe "all/0" do
    test "is the six abilities in canonical order" do
      assert Ability.all() == [:str, :dex, :con, :int, :wis, :cha]
    end
  end

  describe "name/1" do
    test "gives the display name for each ability" do
      assert Ability.name(:str) == "Strength"
      assert Ability.name(:dex) == "Dexterity"
      assert Ability.name(:con) == "Constitution"
      assert Ability.name(:int) == "Intelligence"
      assert Ability.name(:wis) == "Wisdom"
      assert Ability.name(:cha) == "Charisma"
    end

    test "names every ability all/0 lists" do
      for ability <- Ability.all() do
        assert is_binary(Ability.name(ability))
      end
    end

    test "raises for something that is not an ability" do
      assert_raise ArgumentError, ~r/unknown ability: :luck/, fn -> Ability.name(:luck) end
    end
  end

  describe "standard_array/0" do
    test "is the SRD's six scores, highest first" do
      assert Ability.standard_array() == [15, 14, 13, 12, 10, 8]
    end

    test "has one score per ability" do
      assert length(Ability.standard_array()) == length(Ability.all())
    end
  end
end
