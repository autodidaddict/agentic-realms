defmodule Srd.Rules.SkillTest do
  use ExUnit.Case, async: true

  alias Srd.Rules.Skill

  describe "all/0" do
    test "returns all 18 skills" do
      assert length(Skill.all()) == 18
    end
  end

  describe "ability/1" do
    test "maps a skill to its governing ability" do
      assert Skill.ability(:athletics) == :str
      assert Skill.ability(:stealth) == :dex
      assert Skill.ability(:arcana) == :int
      assert Skill.ability(:perception) == :wis
      assert Skill.ability(:persuasion) == :cha
    end

    test "raises for an unknown skill" do
      assert_raise KeyError, fn -> Skill.ability(:juggling) end
    end
  end

  describe "by_ability/1" do
    test "lists the skills governed by an ability" do
      assert Enum.sort(Skill.by_ability(:dex)) == [:acrobatics, :sleight_of_hand, :stealth]
    end
  end

  describe "check_modifier/3" do
    test "is just the ability modifier when not proficient" do
      assert Skill.check_modifier(3, 2) == 3
    end

    test "adds the proficiency bonus when proficient" do
      assert Skill.check_modifier(3, 2, proficient?: true) == 5
    end

    test "doubles the proficiency bonus with expertise" do
      assert Skill.check_modifier(3, 2, proficient?: true, expertise?: true) == 7
    end
  end
end
