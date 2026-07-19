defmodule Srd.Content.WeaponsTest do
  use ExUnit.Case, async: true

  alias Srd.Content.Weapon
  alias Srd.Content.Weapons
  alias Srd.Dice.Expr

  @masteries ~w(cleave graze nick push sap slow topple vex)a

  describe "all/0" do
    test "returns every weapon as a struct" do
      weapons = Weapons.all()
      assert length(weapons) == 38
      assert Enum.all?(weapons, &match?(%Weapon{}, &1))
    end

    test "every weapon has a mastery from the closed set" do
      assert Enum.all?(Weapons.all(), &(&1.mastery in @masteries))
    end
  end

  describe "get/1" do
    test "looks up a weapon by slug" do
      longsword = Weapons.get("longsword")
      assert longsword.name == "Longsword"
      assert longsword.category == :martial
      assert longsword.kind == :melee
      assert longsword.damage_type == :slashing
      assert longsword.mastery == :sap
      assert :versatile in longsword.properties
    end

    test "parses the damage into a Dice.Expr at load time" do
      longsword = Weapons.get("longsword")
      assert %Expr{count: 1, sides: 8} = longsword.damage
      assert %Expr{count: 1, sides: 10} = longsword.versatile
    end

    test "carries the weapon's properties and damage type" do
      dagger = Weapons.get("dagger")
      assert dagger.properties == [:finesse, :light, :thrown]
      assert dagger.damage_type == :piercing
      assert dagger.mastery == :nick
    end

    test "looks up multi-word weapons by hyphenated slug" do
      assert Weapons.get("hand-crossbow").name == "Hand Crossbow"
      assert Weapons.get("war-pick").mastery == :sap
    end

    test "returns nil for an unknown slug" do
      assert Weapons.get("frostmourne") == nil
    end
  end

  describe "fetch!/1" do
    test "raises for an unknown slug" do
      assert_raise KeyError, fn -> Weapons.fetch!("frostmourne") end
    end
  end

  describe "integration with dice" do
    test "a weapon's damage rolls through Srd.Dice" do
      roll = Srd.Dice.roll(Weapons.get("greataxe").damage)
      assert roll.sides == 12
      assert roll.total in 1..12
    end

    test "the blowgun's flat 1 damage is encoded as a d1" do
      blowgun = Weapons.get("blowgun")
      assert %Expr{count: 1, sides: 1} = blowgun.damage
      assert Srd.Dice.roll(blowgun.damage).total == 1
    end
  end
end
