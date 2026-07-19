defmodule Srd.Content.ArmorTest do
  use ExUnit.Case, async: true

  alias Srd.Content.Armor
  alias Srd.Content.Armors

  @categories ~w(light medium heavy shield)a

  describe "all/0" do
    test "returns every armor as a struct" do
      armor = Armors.all()
      assert length(armor) == 13
      assert Enum.all?(armor, &match?(%Armor{}, &1))
    end

    test "every armor has a category from the closed set" do
      assert Enum.all?(Armors.all(), &(&1.category in @categories))
    end
  end

  describe "get/1" do
    test "looks up armor by slug" do
      plate = Armors.get("plate")
      assert plate.name == "Plate Armor"
      assert plate.category == :heavy
      assert plate.base_ac == 18
      assert plate.strength == 15
      assert plate.stealth_disadvantage
    end

    test "light armor has no Strength requirement or stealth penalty" do
      leather = Armors.get("leather")
      assert leather.category == :light
      assert leather.base_ac == 11
      assert leather.strength == nil
      refute leather.stealth_disadvantage
    end

    test "a shield's base_ac is the bonus it grants" do
      shield = Armors.get("shield")
      assert shield.category == :shield
      assert shield.base_ac == 2
    end

    test "looks up multi-word armor by hyphenated slug" do
      assert Armors.get("studded-leather").name == "Studded Leather Armor"
      assert Armors.get("chain-mail").strength == 13
    end

    test "returns nil for an unknown slug" do
      assert Armors.get("mithral") == nil
    end
  end

  describe "fetch!/1" do
    test "raises for an unknown slug" do
      assert_raise KeyError, fn -> Armors.fetch!("mithral") end
    end
  end

  describe "new/1 validation" do
    test "rejects an unknown category" do
      assert_raise ArgumentError, ~r/unknown armor category/, fn ->
        Armor.new(%{slug: "x", name: "X", category: :bogus, base_ac: 10})
      end
    end
  end
end
