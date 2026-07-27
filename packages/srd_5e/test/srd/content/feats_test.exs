defmodule Srd.Content.FeatsTest do
  use ExUnit.Case, async: true

  alias Srd.Content.Feat
  alias Srd.Content.Feats

  doctest Srd.Content.Feat
  doctest Srd.Content.Feats

  describe "all/0" do
    test "returns the SRD's seventeen feats" do
      feats = Feats.all()
      assert length(feats) == 17
      assert Enum.all?(feats, &match?(%Feat{}, &1))
    end

    test "splits them across the four categories" do
      counts =
        Feats.all()
        |> Enum.group_by(& &1.category)
        |> Map.new(fn {category, feats} -> {category, length(feats)} end)

      assert counts == %{origin: 4, general: 2, fighting_style: 4, epic_boon: 7}
    end
  end

  describe "all/1" do
    test "filters by category" do
      assert Feats.all(category: :general) |> Enum.map(& &1.slug) |> Enum.sort() ==
               ["ability-score-improvement", "grappler"]
    end

    test "filters by repeatability" do
      assert Feats.all(repeatable?: true) |> Enum.map(& &1.slug) |> Enum.sort() ==
               ["ability-score-improvement", "magic-initiate", "skilled"]
    end
  end

  describe "prerequisites" do
    test "origin feats have none" do
      assert Enum.all?(Feats.all(category: :origin), &(&1.prerequisites == []))
    end

    test "grappler needs level 4 and a 13 in Strength or Dexterity" do
      assert Feats.get("grappler").prerequisites == [{:level, 4}, {:ability, [:str, :dex], 13}]
    end

    test "fighting style feats need the Fighting Style feature" do
      assert Enum.all?(
               Feats.all(category: :fighting_style),
               &(&1.prerequisites == [{:feature, :fighting_style}])
             )
    end

    test "epic boons need level 19" do
      assert Enum.all?(
               Feats.all(category: :epic_boon),
               &({:level, 19} in &1.prerequisites)
             )
    end

    test "boon of spell recall also needs spellcasting" do
      assert {:feature, :spellcasting} in Feats.get("boon-of-spell-recall").prerequisites
    end
  end

  describe "meets?/2" do
    test "defaults to a level 1 character with nothing" do
      assert Feat.meets?(Feats.get("alert"))
      refute Feat.meets?(Feats.get("ability-score-improvement"))
    end

    test "an ability prerequisite is satisfied by any one of its abilities" do
      grappler = Feats.get("grappler")
      assert Feat.meets?(grappler, level: 4, abilities: %{dex: 13})
      assert Feat.meets?(grappler, level: 4, abilities: %{str: 20})
      refute Feat.meets?(grappler, level: 4, abilities: %{str: 12, dex: 12})
    end

    test "a feature prerequisite is satisfied by holding the feature" do
      archery = Feats.get("archery")
      refute Feat.meets?(archery)
      assert Feat.meets?(archery, features: [:fighting_style])
    end
  end

  describe "eligible/1" do
    test "a level 1 character with nothing gets the origin feats" do
      assert Feats.eligible() |> Enum.map(& &1.slug) |> Enum.sort() ==
               ["alert", "magic-initiate", "savage-attacker", "skilled"]
    end

    test "narrows by category" do
      assert Feats.eligible(level: 20, category: :epic_boon) |> length() == 6
    end

    test "a level 20 caster qualifies for every feat" do
      eligible =
        Feats.eligible(
          level: 20,
          abilities: %{str: 15},
          features: [:fighting_style, :spellcasting]
        )

      assert length(eligible) == 17
    end
  end
end
