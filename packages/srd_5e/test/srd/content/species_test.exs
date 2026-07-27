defmodule Srd.Content.SpeciesTest do
  use ExUnit.Case, async: true

  alias Srd.Content.Feature
  alias Srd.Content.Species
  alias Srd.Rules.Damage

  doctest Srd.Content.Species

  describe "all/0" do
    test "returns the SRD's nine species" do
      species = Species.all()
      assert length(species) == 9
      assert Enum.all?(species, &match?(%Species{}, &1))

      assert species |> Enum.map(& &1.slug) |> Enum.sort() ==
               [
                 "dragonborn",
                 "dwarf",
                 "elf",
                 "gnome",
                 "goliath",
                 "halfling",
                 "human",
                 "orc",
                 "tiefling"
               ]
    end
  end

  describe "the sub-tier" do
    test "the five species with a lineage trait name it" do
      with_lineages = Species.all(lineages?: true)

      assert with_lineages |> Enum.map(&{&1.slug, &1.lineage_trait}) |> Enum.sort() == [
               {"dragonborn", "Draconic Ancestry"},
               {"elf", "Elven Lineage"},
               {"gnome", "Gnomish Lineage"},
               {"goliath", "Giant Ancestry"},
               {"tiefling", "Fiendish Legacy"}
             ]
    end

    test "the four species without one carry no trait and no options" do
      for species <- Species.all(lineages?: false) do
        assert species.lineages == []
        assert species.lineage_trait == nil
      end
    end

    test "elven lineage offers drow, high elf, and wood elf" do
      assert Species.get("elf").lineages |> Enum.map(& &1.name) == [
               "Drow",
               "High Elf",
               "Wood Elf"
             ]
    end

    test "draconic ancestry carries a real damage type per dragon" do
      dragonborn = Species.get("dragonborn")
      assert length(dragonborn.lineages) == 10

      for lineage <- dragonborn.lineages do
        assert lineage.damage_type in Damage.types()
      end

      assert Species.lineage("dragonborn", "silver").damage_type == :cold
    end

    test "giant ancestry offers the six boons" do
      assert length(Species.get("goliath").lineages) == 6
    end

    test "lineages that grant spells carry them at levels 3 and 5" do
      drow = Species.lineage("elf", "drow")
      assert drow.features |> Enum.map(& &1.level) == [1, 3, 5]
    end
  end

  describe "lineage/2" do
    test "returns nil when the species has no such lineage" do
      assert Species.lineage("elf", "rock-gnome") == nil
      assert Species.lineage("orc", "drow") == nil
    end

    test "accepts a species struct" do
      assert Species.lineage(Species.get("tiefling"), "infernal").name == "Infernal"
    end
  end

  describe "traits" do
    test "size and speed come from the species" do
      assert Species.get("goliath").speed == 35
      assert Species.get("gnome").sizes == [:small]
      assert Species.get("human").sizes == [:small, :medium]
    end

    test "a trait can carry the choice it asks for" do
      keen_senses = Species.get("elf").features |> Enum.find(&(&1.name == "Keen Senses"))
      assert keen_senses.choice.kind == :skill
      assert keen_senses.choice.from == [:insight, :perception, :survival]
    end

    test "the human's Versatile trait offers the origin feats" do
      versatile = Species.get("human").features |> Enum.find(&(&1.name == "Versatile"))

      assert versatile.choice.from == ["alert", "magic-initiate", "savage-attacker", "skilled"]
    end

    test "traits arriving later carry their level" do
      flight = Species.get("dragonborn").features |> Enum.find(&(&1.name == "Draconic Flight"))
      assert flight.level == 5

      assert Feature.through_level(Species.get("dragonborn").features, 4)
             |> Enum.map(& &1.name)
             |> Enum.member?("Draconic Flight") == false
    end
  end

  describe "fetch!/1" do
    test "raises for an unknown slug" do
      assert_raise KeyError, fn -> Species.fetch!("aasimar") end
    end
  end
end
