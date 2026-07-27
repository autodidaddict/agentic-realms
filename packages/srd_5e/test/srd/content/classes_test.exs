defmodule Srd.Content.ClassesTest do
  use ExUnit.Case, async: true

  alias Srd.Content.Bundle
  alias Srd.Content.Class
  alias Srd.Content.Classes
  alias Srd.Content.Feature
  alias Srd.Content.Items
  alias Srd.Dice.Expr
  alias Srd.Rules.Skill

  doctest Srd.Content.Class
  doctest Srd.Content.Classes

  describe "all/0" do
    test "returns the SRD's twelve classes" do
      classes = Classes.all()
      assert length(classes) == 12
      assert Enum.all?(classes, &match?(%Class{}, &1))
    end

    test "every class chooses its subclass at level 3" do
      assert Enum.all?(Classes.all(), &(&1.subclass_level == 3))
    end
  end

  describe "core traits" do
    test "hit dice are parsed at load time" do
      assert %Expr{count: 1, sides: 12} = Classes.get("barbarian").hit_die
      assert %Expr{count: 1, sides: 6} = Classes.get("wizard").hit_die
    end

    test "saving throws are a pair of abilities" do
      assert Classes.get("cleric").saving_throws == [:wis, :cha]
      assert Enum.all?(Classes.all(), &(length(&1.saving_throws) == 2))
    end

    test "skill choices name real skills" do
      for class <- Classes.all() do
        assert class.skill_choice.kind == :skill
        assert class.skill_choice.choose >= 2
        assert Enum.all?(class.skill_choice.from, &(&1 in Skill.all()))
      end

      assert Classes.get("rogue").skill_choice.choose == 4
      assert Classes.get("bard").skill_choice.from == Enum.sort(Skill.all())
    end

    test "a primary ability can be one of two, or both of two" do
      assert Classes.get("fighter").primary_ability == {:any, [:str, :dex]}
      assert Classes.get("monk").primary_ability == {:all, [:dex, :wis]}
      assert Classes.get("wizard").primary_ability == {:all, [:int]}
    end

    test "weapon proficiency can be narrowed by property" do
      assert Classes.get("rogue").weapon_proficiencies == [
               :simple,
               {:martial, [:finesse, :light]}
             ]

      assert Classes.get("fighter").weapon_proficiencies == [:simple, :martial]
    end

    test "classes with no armor training carry an empty list" do
      assert Classes.get("wizard").armor_training == []
      assert Classes.get("paladin").armor_training == [:light, :medium, :heavy, :shield]
    end

    test "casters record how they cast" do
      assert Classes.get("wizard").spellcasting == %{ability: :int, kind: :prepared}
      assert Classes.get("warlock").spellcasting == %{ability: :cha, kind: :pact}
      assert Classes.get("barbarian").spellcasting == nil
    end
  end

  describe "all/1" do
    test "filters by spellcasting" do
      assert Classes.all(spellcasting?: true) |> length() == 8
    end

    test "filters by primary ability" do
      assert Classes.all(ability: :cha) |> Enum.map(& &1.slug) |> Enum.sort() ==
               ["bard", "paladin", "sorcerer", "warlock"]
    end

    test "filters by offered skill" do
      # The bard chooses from every skill, so it offers this one too.
      assert Classes.all(skill: :sleight_of_hand) |> Enum.map(& &1.slug) |> Enum.sort() ==
               ["bard", "rogue"]

      assert Classes.all(skill: :arcana) |> Enum.map(& &1.slug) |> Enum.sort() ==
               ["bard", "druid", "sorcerer", "warlock", "wizard"]
    end

    test "filters by armor training" do
      assert Classes.all(armor_training: :heavy) |> Enum.map(& &1.slug) |> Enum.sort() ==
               ["fighter", "paladin"]
    end
  end

  describe "multiclass_options/1" do
    test "a single primary ability needs a 13 in it" do
      assert Classes.multiclass_options(%{int: 13}) |> Enum.map(& &1.slug) == ["wizard"]
    end

    test "a two-ability class needs both" do
      refute Classes.multiclass_options(%{dex: 20}) |> Enum.any?(&(&1.slug == "monk"))
      assert Classes.multiclass_options(%{dex: 13, wis: 13}) |> Enum.any?(&(&1.slug == "monk"))
    end

    test "an either-or class needs one of them" do
      assert Classes.multiclass_options(%{dex: 13}) |> Enum.any?(&(&1.slug == "fighter"))
    end

    test "nothing qualifies on empty scores" do
      assert Classes.multiclass_options(%{}) == []
    end
  end

  describe "features" do
    test "every class grants features from level 1 to 20" do
      for class <- Classes.all() do
        levels = Enum.map(class.features, & &1.level)
        assert Enum.min(levels) == 1
        assert Enum.max(levels) >= 19
      end
    end

    test "each class names the level it picks a subclass" do
      for class <- Classes.all() do
        subclass_feature = Enum.find(class.features, &(&1.name == "#{class.name} Subclass"))
        assert subclass_feature, "#{class.slug} has no subclass feature"
        assert subclass_feature.level == class.subclass_level
      end
    end

    test "through_level/2 returns what a character has so far, in level order" do
      barbarian = Classes.get("barbarian")
      at_two = Feature.through_level(barbarian.features, 2)

      assert Enum.map(at_two, & &1.name) == [
               "Rage",
               "Unarmored Defense",
               "Weapon Mastery",
               "Danger Sense",
               "Reckless Attack"
             ]
    end

    test "a feature can carry the choice it asks for" do
      fighting_style =
        Classes.get("fighter").features |> Enum.find(&(&1.name == "Fighting Style"))

      assert fighting_style.choice.kind == :feat

      assert fighting_style.choice.from ==
               ["archery", "defense", "great-weapon-fighting", "two-weapon-fighting"]
    end

    test "weapon mastery choices expand to real weapon slugs" do
      mastery = Classes.get("barbarian").features |> Enum.find(&(&1.name == "Weapon Mastery"))
      assert mastery.choice.choose == 2
      assert "greataxe" in mastery.choice.from
      refute "longbow" in mastery.choice.from
    end

    test "epic boon choices expand to the epic boon feats" do
      boon = Classes.get("wizard").features |> Enum.find(&(&1.name == "Epic Boon"))
      assert length(boon.choice.from) == 7
      assert "boon-of-truesight" in boon.choice.from
    end
  end

  describe "starting equipment" do
    test "every class offers a gold-only option" do
      for class <- Classes.all() do
        assert Enum.any?(class.starting_equipment.from, &(&1.items == [] and &1.gp > 0))
      end
    end

    test "the fighter offers three options" do
      assert length(Classes.get("fighter").starting_equipment.from) == 3
    end

    test "a bundle can carry a choice the character still makes" do
      [bundle, _gold] = Classes.get("bard").starting_equipment.from
      assert [choice] = bundle.choices
      assert choice.kind == :tool
      assert choice.from == Items.slugs(:musical_instrument)
    end

    test "every item in every bundle resolves" do
      for class <- Classes.all(),
          bundle <- class.starting_equipment.from,
          entry <- bundle.items do
        assert Bundle.known?(entry.item), "#{class.slug} names unknown item #{entry.item}"
      end
    end
  end

  describe "fetch!/1" do
    test "raises for an unknown slug" do
      assert_raise KeyError, fn -> Classes.fetch!("artificer") end
    end
  end
end
